"""
Core tide prediction engine wrapping pyTMD + FES2022.

Provides two operations:
  1. predict_chart: hourly heights + high/low extremes for a date range
  2. predict_summary: current height, tide state, next high/low
"""

import datetime
import logging
import math
import os
from functools import lru_cache
from typing import Optional
from zoneinfo import ZoneInfo

import numpy as np
import pyTMD.io
import timescale.time
from scipy.interpolate import RegularGridInterpolator
from timezonefinder import TimezoneFinder

from config import COORD_PRECISION, FES_DATA_DIR, METERS_TO_FEET

logger = logging.getLogger("tide_engine")

_tz_finder: Optional[TimezoneFinder] = None
MODEL_NAME = "FES2022_extrapolated"

_dataset = None
_corrections = None
_minor = None
_mllw_interpolator: Optional[RegularGridInterpolator] = None


def _get_tz_finder() -> TimezoneFinder:
    global _tz_finder
    if _tz_finder is None:
        _tz_finder = TimezoneFinder()
    return _tz_finder


def get_timezone(lat: float, lon: float) -> str:
    """Derive IANA timezone ID from coordinates. Falls back to UTC for open ocean."""
    try:
        tz = _get_tz_finder().timezone_at(lng=lon, lat=lat)
        return tz or "Etc/UTC"
    except Exception:
        return "Etc/UTC"


def load_model(data_dir: str = FES_DATA_DIR) -> None:
    """Load FES2022 model and open the dataset once. Reused across all requests."""
    global _dataset, _corrections, _minor, _mllw_interpolator
    logger.info("Loading FES2022 model from %s ...", data_dir)
    m = pyTMD.io.model(data_dir).from_database(MODEL_NAME)
    n_files = len(m.z.model_file) if isinstance(m.z.model_file, list) else 1
    logger.info("Opening dataset (%d constituent files)...", n_files)
    # chunks={} with pyTMD==3.0.3 is the proven production combination
    # (Mar-Apr 2026). The Apr/Jun OOM crash loops were a pyTMD>=3.0.4
    # regression, not a chunking issue; chunks="auto" avoided the OOM but
    # made interpolation ~150s per location and ~10GB resident.
    _dataset = m.open_dataset(group="z", chunks={})
    _corrections = m.corrections
    _minor = m.minor
    logger.info("FES2022 dataset opened and ready")

    grid_path = os.path.join(os.path.dirname(__file__), "data", "mllw_grid.npz")
    if os.path.exists(grid_path):
        data = np.load(grid_path)
        _mllw_interpolator = RegularGridInterpolator(
            (data["lat"], data["lon"]),
            data["mllw_offset"],
            method="linear",
            bounds_error=False,
            fill_value=np.nan,
        )
        logger.info("MLLW grid loaded (%s)", grid_path)
    else:
        logger.warning("MLLW grid not found at %s — using MSL datum", grid_path)


def _get_mllw_offset_ft(lat: float, lon: float) -> float:
    """Return the MLLW offset in feet for a coordinate via bilinear interpolation."""
    if _mllw_interpolator is None:
        return 0.0
    val = float(_mllw_interpolator((lat, lon)))
    if not math.isfinite(val):
        return 0.0
    return val * METERS_TO_FEET


def _log_rss(stage: str) -> None:
    try:
        with open("/proc/self/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    logger.info("RSS %s: %.0f MB", stage, int(line.split()[1]) / 1024)
                    return
    except OSError:
        pass


def _predict_heights(lat: float, lon: float, times: np.ndarray) -> np.ndarray:
    """
    Predict tide heights (meters, MSL) for an array of datetime64 times.
    Uses the pre-loaded FES2022 dataset — skips model discovery and file
    opening that pyTMD.compute.tide_elevations repeats on every call.
    """
    x, y = np.atleast_1d(lon), np.atleast_1d(lat)
    X, Y = _dataset.tmd.coords_as(x, y, type="time series", crs=4326)

    xmin, xmax = float(np.min(X)), float(np.max(X))
    ymin, ymax = float(np.min(Y)), float(np.max(Y))
    _log_rss("before crop")
    ds_crop = _dataset.tmd.crop([xmin, xmax, ymin, ymax], buffer=0.5)
    _log_rss("after crop")

    ts = timescale.time.Timescale.from_datetime(times)
    if _corrections in ("OTIS", "ATLAS", "TMD3", "netcdf"):
        deltat = np.zeros_like(ts.tt_ut1)
    else:
        deltat = ts.tt_ut1

    local = ds_crop.tmd.interp(X, Y, method="linear", extrapolate=True, cutoff=10.0)
    _log_rss("after interp")
    tpred = local.tmd.predict(ts.tide, deltat=deltat, corrections=_corrections)
    _log_rss("after predict")
    tinfer = local.tmd.infer(
        ts.tide, deltat=deltat, corrections=_corrections, minor=_minor,
    )
    _log_rss("after infer")
    tpred += tinfer
    return np.asarray(tpred).flatten()


def _find_extremes(times_ms: list[int], heights_ft: list[float]) -> list[dict]:
    """Find local maxima (H) and minima (L) in the tide curve.

    Pipeline: raw local-extreme detection → cluster merge (3 h window) →
    neighbour-based H/L reclassification → relative-prominence filter.
    """
    raw: list[dict] = []
    n = len(heights_ft)
    if n < 3:
        return raw

    for i in range(1, n - 1):
        prev_h, curr_h, next_h = heights_ft[i - 1], heights_ft[i], heights_ft[i + 1]
        if curr_h > prev_h and curr_h >= next_h:
            raw.append({
                "epoch_ms": times_ms[i],
                "height_ft": round(curr_h, 2),
                "type": "H",
            })
        elif curr_h < prev_h and curr_h <= next_h:
            raw.append({
                "epoch_ms": times_ms[i],
                "height_ft": round(curr_h, 2),
                "type": "L",
            })

    merged = _merge_nearby_extremes(raw)
    merged = _reclassify_types(merged)

    total_range = (max(heights_ft) - min(heights_ft)) if heights_ft else 0.0
    merged = _filter_by_prominence(merged, total_range)

    return merged


_MERGE_WINDOW_MS = 3 * 3_600_000  # 3 hours


def _merge_nearby_extremes(raw: list[dict]) -> list[dict]:
    """Collapse clusters of extremes within _MERGE_WINDOW_MS into one each.

    Picks the point furthest from the cluster mean; type assignment is
    deferred to _reclassify_types.
    """
    if not raw:
        return raw

    merged: list[dict] = []
    cluster: list[dict] = [raw[0]]

    for ext in raw[1:]:
        if ext["epoch_ms"] - cluster[0]["epoch_ms"] <= _MERGE_WINDOW_MS:
            cluster.append(ext)
        else:
            merged.append(_pick_representative(cluster))
            cluster = [ext]

    merged.append(_pick_representative(cluster))
    return merged


def _pick_representative(cluster: list[dict]) -> dict:
    """Select the single most-extreme point from a noise cluster."""
    max_pt = max(cluster, key=lambda e: e["height_ft"])
    min_pt = min(cluster, key=lambda e: e["height_ft"])
    mean_h = sum(e["height_ft"] for e in cluster) / len(cluster)
    if abs(max_pt["height_ft"] - mean_h) >= abs(min_pt["height_ft"] - mean_h):
        return dict(max_pt)
    return dict(min_pt)


def _reclassify_types(merged: list[dict]) -> list[dict]:
    """Assign H/L by comparing each point's height to its immediate neighbours.

    Tidal extremes must alternate H/L.  This corrects any mis-labels
    from the noisy raw detection by using relative height context.
    """
    n = len(merged)
    if n <= 1:
        return merged
    for i in range(n):
        higher_than_prev = (i == 0) or merged[i]["height_ft"] > merged[i - 1]["height_ft"]
        higher_than_next = (i == n - 1) or merged[i]["height_ft"] > merged[i + 1]["height_ft"]
        if higher_than_prev and higher_than_next:
            merged[i] = merged[i] | {"type": "H"}
        else:
            merged[i] = merged[i] | {"type": "L"}
    return merged


def _filter_by_prominence(merged: list[dict], total_range: float) -> list[dict]:
    """Remove noise extremes whose prominence is below a relative threshold.

    Threshold adapts to the location's tidal range so that low-amplitude
    spots (atolls, enclosed bays) are not over-filtered.
    """
    if len(merged) <= 2:
        return merged
    threshold = max(0.1, 0.05 * total_range)
    result: list[dict] = []
    for i, ext in enumerate(merged):
        if i == 0 or i == len(merged) - 1:
            result.append(ext)
            continue
        diff_prev = abs(ext["height_ft"] - merged[i - 1]["height_ft"])
        diff_next = abs(ext["height_ft"] - merged[i + 1]["height_ft"])
        if min(diff_prev, diff_next) >= threshold:
            result.append(ext)
    if len(result) != len(merged):
        result = _reclassify_types(result)
    return result


def _cache_key(lat: float, lon: float, date_str: str, days: int) -> tuple:
    return (
        round(lat, COORD_PRECISION),
        round(lon, COORD_PRECISION),
        date_str,
        days,
    )


@lru_cache(maxsize=4096)
def _cached_predict(key: tuple) -> dict:
    lat_r, lon_r, date_str, days = key
    return _do_predict(lat_r, lon_r, date_str, days)


_FINE_STEP = 6  # minutes – single resolution for all predictions
_EXTREMES_BUFFER_MIN = 360  # 6 h each side – gives boundary extremes neighbours

def _do_predict(
    lat: float, lon: float, date_str: str, days: int
) -> dict:
    tz = ZoneInfo(get_timezone(lat, lon))
    local_midnight = datetime.datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=tz)
    utc_start = local_midnight.astimezone(datetime.timezone.utc).replace(tzinfo=None)

    total_minutes = days * 24 * 60
    epoch_base = int(local_midnight.timestamp() * 1000)

    # Wider window for extreme detection so boundary extremes have neighbours
    buf_start = utc_start - datetime.timedelta(minutes=_EXTREMES_BUFFER_MIN)
    buf_total = total_minutes + 2 * _EXTREMES_BUFFER_MIN
    buf_offsets = np.arange(0, buf_total + 1, _FINE_STEP)
    buf_times = np.array(
        [buf_start + datetime.timedelta(minutes=int(m)) for m in buf_offsets],
        dtype="datetime64[ms]",
    )

    buf_heights_m = _predict_heights(lat, lon, buf_times)
    mllw_offset = _get_mllw_offset_ft(lat, lon)
    buf_heights_ft = [
        round(float(h) * METERS_TO_FEET - mllw_offset, 2) if math.isfinite(float(h)) else 0.0
        for h in buf_heights_m
    ]

    buf_epoch_base = epoch_base - _EXTREMES_BUFFER_MIN * 60_000
    buf_ms = [buf_epoch_base + int(m) * 60_000 for m in buf_offsets]

    extremes = _find_extremes(buf_ms, buf_heights_ft)

    # Trim extremes to the requested day window
    day_end_ms = epoch_base + total_minutes * 60_000
    extremes = [e for e in extremes if epoch_base <= e["epoch_ms"] <= day_end_ms]

    # Points cover exactly the requested day (no buffer)
    day_idx_start = _EXTREMES_BUFFER_MIN // _FINE_STEP
    day_idx_end = day_idx_start + total_minutes // _FINE_STEP + 1
    points = [
        {"epoch_ms": buf_ms[i], "height_ft": buf_heights_ft[i]}
        for i in range(day_idx_start, min(day_idx_end, len(buf_ms)))
    ]

    return {"points": points, "extremes": extremes}


def _derive_summary(points: list[dict], extremes: list[dict]) -> dict:
    """Derive current height, tide state, and next high/low from chart data."""
    now_ms = int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000)

    current_height = 0.0
    for i in range(len(points) - 1):
        t0, t1 = points[i]["epoch_ms"], points[i + 1]["epoch_ms"]
        if t0 <= now_ms <= t1:
            frac = (now_ms - t0) / (t1 - t0) if t1 != t0 else 0
            current_height = round(
                points[i]["height_ft"] + frac * (points[i + 1]["height_ft"] - points[i]["height_ft"]), 2
            )
            break

    next_high = next_low = None
    for ext in extremes:
        if ext["epoch_ms"] <= now_ms:
            continue
        if ext["type"] == "H" and next_high is None:
            next_high = ext
        elif ext["type"] == "L" and next_low is None:
            next_low = ext
        if next_high and next_low:
            break

    if next_high and next_low:
        tide_state = "rising" if next_high["epoch_ms"] < next_low["epoch_ms"] else "falling"
    elif next_high:
        tide_state = "rising"
    elif next_low:
        tide_state = "falling"
    else:
        tide_state = "unknown"

    return {
        "current_height_ft": current_height,
        "tide_state": tide_state,
        "next_high_tide_epoch_ms": next_high["epoch_ms"] if next_high else None,
        "next_high_tide_ft": next_high["height_ft"] if next_high else None,
        "next_low_tide_epoch_ms": next_low["epoch_ms"] if next_low else None,
        "next_low_tide_ft": next_low["height_ft"] if next_low else None,
    }


def predict_chart(
    lat: float,
    lon: float,
    date_str: Optional[str] = None,
    days: int = 1,
    step_minutes: int = 30,
) -> dict:
    """
    Predict tide chart data for a location and date range.

    If date_str is None, computes today at the spot's local timezone.
    Returns chart points, extremes, inline summary, and local_date.
    """
    tz_id = get_timezone(lat, lon)

    if date_str is None:
        tz = ZoneInfo(tz_id)
        date_str = datetime.datetime.now(tz).strftime("%Y-%m-%d")

    key = _cache_key(lat, lon, date_str, days)
    result = _cached_predict(key)

    subsample = max(1, step_minutes // _FINE_STEP)
    points = result["points"][::subsample]

    summary = _derive_summary(result["points"], result["extremes"])

    return {
        "lat": round(lat, COORD_PRECISION),
        "lon": round(lon, COORD_PRECISION),
        "date": date_str,
        "local_date": date_str,
        "days": days,
        "datum": "MLLW" if _mllw_interpolator is not None else "MSL",
        "model": "FES2022",
        "timezoneId": tz_id,
        "points": points,
        "extremes": result["extremes"],
        "summary": summary,
    }


_YEAR_CHUNK_DAYS = 31  # generate the year in bounded windows to cap peak memory


def predict_year(
    lat: float,
    lon: float,
    start_date: Optional[str] = None,
    days: int = 365,
    step_minutes: int = 30,
) -> dict:
    """
    Precompute a long tide horizon (default 365 days) for one location and
    return the curve grouped into per-spot-local-date buckets.

    Memory safety: the horizon is computed in bounded ``_YEAR_CHUNK_DAYS``
    windows (one spatial crop each) and streamed into day buckets, so peak
    memory never scales with the horizon length. This is the path used by the
    upfront backfill / monthly top-up; it deliberately bypasses the per-day
    ``lru_cache`` so year-sized results never pollute it.

    Day bucketing uses the spot's real IANA timezone (not a longitude
    approximation), so each calendar day's points/extremes are correct across
    DST and timezone boundaries.
    """
    tz_id = get_timezone(lat, lon)
    tz = ZoneInfo(tz_id)

    if start_date is None:
        start_date = datetime.datetime.now(tz).strftime("%Y-%m-%d")
    start = datetime.datetime.strptime(start_date, "%Y-%m-%d").date()
    end_exclusive = start + datetime.timedelta(days=days)

    subsample = max(1, step_minutes // _FINE_STEP)

    day_points: dict[str, list[dict]] = {}
    day_extremes: dict[str, list[dict]] = {}
    seen_point_ms: set[int] = set()
    seen_ext: set[tuple] = set()

    def local_date_of(epoch_ms: int) -> str:
        return datetime.datetime.fromtimestamp(epoch_ms / 1000, tz).strftime("%Y-%m-%d")

    def in_range(local_date: str) -> bool:
        return start.isoformat() <= local_date < end_exclusive.isoformat()

    generated = 0
    while generated < days:
        chunk = min(_YEAR_CHUNK_DAYS, days - generated)
        chunk_start = (start + datetime.timedelta(days=generated)).strftime("%Y-%m-%d")
        # Bypass _cached_predict on purpose (see docstring).
        result = _do_predict(lat, lon, chunk_start, chunk)

        for p in result["points"][::subsample]:
            ms = p["epoch_ms"]
            if ms in seen_point_ms:
                continue
            seen_point_ms.add(ms)
            d = local_date_of(ms)
            if in_range(d):
                day_points.setdefault(d, []).append(p)

        for e in result["extremes"]:
            key = (e["epoch_ms"], e["type"])
            if key in seen_ext:
                continue
            seen_ext.add(key)
            d = local_date_of(e["epoch_ms"])
            if in_range(d):
                day_extremes.setdefault(d, []).append(e)

        generated += chunk

    datum = "MLLW" if _mllw_interpolator is not None else "MSL"
    tide_days = [
        {
            "local_date": d,
            "points": sorted(day_points[d], key=lambda x: x["epoch_ms"]),
            "extremes": sorted(day_extremes.get(d, []), key=lambda x: x["epoch_ms"]),
        }
        for d in sorted(day_points.keys())
    ]

    return {
        "lat": round(lat, COORD_PRECISION),
        "lon": round(lon, COORD_PRECISION),
        "start_date": start_date,
        "days": days,
        "datum": datum,
        "model": "FES2022",
        "timezoneId": tz_id,
        "step_minutes": step_minutes,
        "tide_days": tide_days,
    }


def predict_summary(lat: float, lon: float) -> dict:
    """
    Predict current tide state: height, rising/falling, next high and low.
    Uses a 2-day window from today (in the spot's local timezone).
    """
    tz_id = get_timezone(lat, lon)
    tz = ZoneInfo(tz_id)
    now = datetime.datetime.now(datetime.timezone.utc)
    date_str = datetime.datetime.now(tz).strftime("%Y-%m-%d")

    key = _cache_key(lat, lon, date_str, 2)
    result = _cached_predict(key)

    now_ms = int(now.timestamp() * 1000)

    current_height = 0.0
    points = result["points"]
    for i in range(len(points) - 1):
        t0, t1 = points[i]["epoch_ms"], points[i + 1]["epoch_ms"]
        if t0 <= now_ms <= t1:
            frac = (now_ms - t0) / (t1 - t0) if t1 != t0 else 0
            h0, h1 = points[i]["height_ft"], points[i + 1]["height_ft"]
            current_height = round(h0 + frac * (h1 - h0), 2)
            break

    next_high = None
    next_low = None
    for ext in result["extremes"]:
        if ext["epoch_ms"] <= now_ms:
            continue
        if ext["type"] == "H" and next_high is None:
            next_high = ext
        elif ext["type"] == "L" and next_low is None:
            next_low = ext
        if next_high and next_low:
            break

    tide_state = "unknown"
    if next_high and next_low:
        tide_state = "rising" if next_high["epoch_ms"] < next_low["epoch_ms"] else "falling"
    elif next_high:
        tide_state = "rising"
    elif next_low:
        tide_state = "falling"

    tz_id = get_timezone(lat, lon)

    return {
        "current_height_ft": current_height,
        "tide_state": tide_state,
        "next_high_tide_epoch_ms": next_high["epoch_ms"] if next_high else None,
        "next_high_tide_ft": next_high["height_ft"] if next_high else None,
        "next_low_tide_epoch_ms": next_low["epoch_ms"] if next_low else None,
        "next_low_tide_ft": next_low["height_ft"] if next_low else None,
        "datum": "MLLW" if _mllw_interpolator is not None else "MSL",
        "timezoneId": tz_id,
    }
