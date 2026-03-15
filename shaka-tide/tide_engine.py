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

import numpy as np
import pyTMD.compute
import pyTMD.io
from timezonefinder import TimezoneFinder

from config import COORD_PRECISION, FES_DATA_DIR, METERS_TO_FEET

logger = logging.getLogger("tide_engine")

_tz_finder: Optional[TimezoneFinder] = None
MODEL_NAME = "FES2022_extrapolated"


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
    """Validate FES2022 constituent files are loadable. Called once at startup."""
    logger.info("Validating FES2022 model from %s ...", data_dir)
    m = pyTMD.io.model(data_dir).from_database(MODEL_NAME)
    n_files = len(m.z.model_file) if isinstance(m.z.model_file, list) else 1
    logger.info("FES2022 model validated: %d constituent files found", n_files)


def _predict_heights(lat: float, lon: float, times: np.ndarray) -> np.ndarray:
    """
    Predict tide heights (meters, MSL) for an array of datetime64 times.
    Uses pyTMD.compute.tide_elevations (pyTMD 3.0 high-level API).
    """
    tide = pyTMD.compute.tide_elevations(
        np.atleast_1d(lon),
        np.atleast_1d(lat),
        times,
        directory=FES_DATA_DIR,
        model=MODEL_NAME,
        crs=4326,
        type="time series",
        standard="datetime",
        method="linear",
        extrapolate=True,
        cutoff=10.0,
        crop=True,
        buffer=2.0,
    )
    result = np.asarray(tide).flatten()
    return result


def _find_extremes(times_ms: list[int], heights_ft: list[float]) -> list[dict]:
    """Find local maxima (H) and minima (L) in the tide curve."""
    extremes = []
    n = len(heights_ft)
    if n < 3:
        return extremes

    for i in range(1, n - 1):
        prev_h, curr_h, next_h = heights_ft[i - 1], heights_ft[i], heights_ft[i + 1]
        if curr_h > prev_h and curr_h >= next_h:
            extremes.append({
                "epoch_ms": times_ms[i],
                "height_ft": round(curr_h, 2),
                "type": "H",
            })
        elif curr_h < prev_h and curr_h <= next_h:
            extremes.append({
                "epoch_ms": times_ms[i],
                "height_ft": round(curr_h, 2),
                "type": "L",
            })

    return extremes


def _cache_key(lat: float, lon: float, date_str: str, days: int, step: int) -> tuple:
    return (
        round(lat, COORD_PRECISION),
        round(lon, COORD_PRECISION),
        date_str,
        days,
        step,
    )


@lru_cache(maxsize=4096)
def _cached_predict(key: tuple) -> dict:
    lat_r, lon_r, date_str, days, step_minutes = key
    return _do_predict(lat_r, lon_r, date_str, days, step_minutes)


def _do_predict(
    lat: float, lon: float, date_str: str, days: int, step_minutes: int
) -> dict:
    start_dt = datetime.datetime.strptime(date_str, "%Y-%m-%d")
    end_dt = start_dt + datetime.timedelta(days=days)

    total_minutes = int((end_dt - start_dt).total_seconds() / 60)
    minute_offsets = np.arange(0, total_minutes + 1, step_minutes)
    times_dt = np.array(
        [start_dt + datetime.timedelta(minutes=int(m)) for m in minute_offsets],
        dtype="datetime64[ms]",
    )

    heights_m = _predict_heights(lat, lon, times_dt)
    heights_ft = [round(float(h) * METERS_TO_FEET, 2) for h in heights_m]

    epoch_base = int(start_dt.replace(tzinfo=datetime.timezone.utc).timestamp() * 1000)
    times_ms = [epoch_base + int(m) * 60_000 for m in minute_offsets]

    points = [{"epoch_ms": t, "height_ft": h} for t, h in zip(times_ms, heights_ft)]

    if step_minutes > 6:
        fine_offsets = np.arange(0, total_minutes + 1, 6)
        fine_times = np.array(
            [start_dt + datetime.timedelta(minutes=int(m)) for m in fine_offsets],
            dtype="datetime64[ms]",
        )
        fine_heights_m = _predict_heights(lat, lon, fine_times)
        fine_heights_ft = [round(float(h) * METERS_TO_FEET, 2) for h in fine_heights_m]
        fine_ms = [epoch_base + int(m) * 60_000 for m in fine_offsets]
        extremes = _find_extremes(fine_ms, fine_heights_ft)
    else:
        extremes = _find_extremes(times_ms, heights_ft)

    return {"points": points, "extremes": extremes}


def predict_chart(
    lat: float,
    lon: float,
    date_str: str,
    days: int = 1,
    step_minutes: int = 30,
) -> dict:
    """
    Predict tide chart data for a location and date range.

    Returns dict with points (epoch_ms, height_ft) and extremes (epoch_ms, height_ft, type).
    """
    key = _cache_key(lat, lon, date_str, days, step_minutes)
    result = _cached_predict(key)
    tz_id = get_timezone(lat, lon)

    return {
        "lat": round(lat, COORD_PRECISION),
        "lon": round(lon, COORD_PRECISION),
        "date": date_str,
        "days": days,
        "datum": "MSL",
        "model": "FES2022",
        "timezoneId": tz_id,
        "points": result["points"],
        "extremes": result["extremes"],
    }


def predict_summary(lat: float, lon: float) -> dict:
    """
    Predict current tide state: height, rising/falling, next high and low.
    Uses a 2-day window centered on now to find upcoming extremes.
    """
    now = datetime.datetime.now(datetime.timezone.utc)
    date_str = now.strftime("%Y-%m-%d")

    key = _cache_key(lat, lon, date_str, 2, 6)
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
