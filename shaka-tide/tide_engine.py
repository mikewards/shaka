"""
Core tide prediction engine wrapping pyTMD + FES2022.

Provides two operations:
  1. predict_chart: hourly heights + high/low extremes for a date range
  2. predict_summary: current height, tide state, next high/low
"""

import datetime
import logging
from functools import lru_cache
from typing import Optional
from zoneinfo import ZoneInfo

import numpy as np
import pyTMD.io
import timescale.time
from timezonefinder import TimezoneFinder

from config import COORD_PRECISION, FES_DATA_DIR, METERS_TO_FEET

logger = logging.getLogger("tide_engine")

_tz_finder: Optional[TimezoneFinder] = None
MODEL_NAME = "FES2022_extrapolated"

_dataset = None
_corrections = None
_minor = None


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
    global _dataset, _corrections, _minor
    logger.info("Loading FES2022 model from %s ...", data_dir)
    m = pyTMD.io.model(data_dir).from_database(MODEL_NAME)
    n_files = len(m.z.model_file) if isinstance(m.z.model_file, list) else 1
    logger.info("Opening dataset (%d constituent files)...", n_files)
    _dataset = m.open_dataset(group="z", chunks={})
    _corrections = m.corrections
    _minor = m.minor
    logger.info("FES2022 dataset opened and ready")


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
    ds_crop = _dataset.tmd.crop([xmin, xmax, ymin, ymax], buffer=0.5)

    ts = timescale.time.Timescale.from_datetime(times)
    if _corrections in ("OTIS", "ATLAS", "TMD3", "netcdf"):
        deltat = np.zeros_like(ts.tt_ut1)
    else:
        deltat = ts.tt_ut1

    local = ds_crop.tmd.interp(X, Y, method="linear", extrapolate=True, cutoff=10.0)
    tpred = local.tmd.predict(ts.tide, deltat=deltat, corrections=_corrections)
    tinfer = local.tmd.infer(
        ts.tide, deltat=deltat, corrections=_corrections, minor=_minor,
    )
    tpred += tinfer
    return np.asarray(tpred).flatten()


def _find_extremes(times_ms: list[int], heights_ft: list[float]) -> list[dict]:
    """Find local maxima (H) and minima (L) in the tide curve.

    Raw local extremes from 6-min samples produce noisy clusters near
    true peaks/troughs due to rounding.  A merge pass collapses any
    extremes within MERGE_WINDOW_MS into one representative point.
    """
    raw = []
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

    return _merge_nearby_extremes(raw)


_MERGE_WINDOW_MS = 3 * 3_600_000  # 3 hours


def _merge_nearby_extremes(raw: list[dict]) -> list[dict]:
    """Collapse clusters of extremes within _MERGE_WINDOW_MS into one each.

    Within a cluster, if any member is "H" the real event is a high tide
    (keep the point with max height); otherwise it's a low (keep min).
    Real tidal extremes are always 5+ hours apart, so a 3-hour window
    is safe.
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
    has_high = any(e["type"] == "H" for e in cluster)
    if has_high:
        return max(cluster, key=lambda e: e["height_ft"]) | {"type": "H"}
    return min(cluster, key=lambda e: e["height_ft"]) | {"type": "L"}


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

def _do_predict(
    lat: float, lon: float, date_str: str, days: int
) -> dict:
    tz = ZoneInfo(get_timezone(lat, lon))
    local_midnight = datetime.datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=tz)
    utc_start = local_midnight.astimezone(datetime.timezone.utc).replace(tzinfo=None)

    total_minutes = days * 24 * 60
    fine_offsets = np.arange(0, total_minutes + 1, _FINE_STEP)
    fine_times = np.array(
        [utc_start + datetime.timedelta(minutes=int(m)) for m in fine_offsets],
        dtype="datetime64[ms]",
    )

    fine_heights_m = _predict_heights(lat, lon, fine_times)
    fine_heights_ft = [round(float(h) * METERS_TO_FEET, 2) for h in fine_heights_m]

    epoch_base = int(local_midnight.timestamp() * 1000)
    fine_ms = [epoch_base + int(m) * 60_000 for m in fine_offsets]

    extremes = _find_extremes(fine_ms, fine_heights_ft)

    points = [{"epoch_ms": t, "height_ft": h} for t, h in zip(fine_ms, fine_heights_ft)]

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
        "datum": "MSL",
        "model": "FES2022",
        "timezoneId": tz_id,
        "points": points,
        "extremes": result["extremes"],
        "summary": summary,
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
        "datum": "MSL",
        "timezoneId": tz_id,
    }
