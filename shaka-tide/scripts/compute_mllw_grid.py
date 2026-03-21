#!/usr/bin/env python3
"""
Precompute global MLLW offset grid from FES2022.

Uses batch predictions (entire latitude row at once) for ~180x speedup
over point-by-point computation. Saves progress per-row for resume.

Usage:
    python compute_mllw_grid.py --fes-data-dir /path/to/fes2022
    python compute_mllw_grid.py --fes-data-dir /path/to/fes2022 --workers 4

Typical runtime: ~12 min with 4 workers on a 10-core Mac.
"""

import argparse
import datetime
import logging
import os
import time
from multiprocessing import Pool

import numpy as np
import pyTMD.io
import timescale.time

logger = logging.getLogger("compute_mllw_grid")

LAT_RANGE = (-78, 78)
LON_RANGE = (-180, 180)
DEFAULT_RESOLUTION = 0.5

MODEL_NAME = "FES2022_extrapolated"
REFERENCE_YEAR = 2024
HOURS_IN_YEAR = 8760
HALF_TIDAL_DAY_HOURS = 15

_dataset = None
_corrections = None
_minor = None


def _load_model(data_dir: str) -> None:
    global _dataset, _corrections, _minor
    m = pyTMD.io.model(data_dir).from_database(MODEL_NAME)
    _dataset = m.open_dataset(group="z", chunks={})
    _corrections = m.corrections
    _minor = m.minor


def _predict_row_batch(lat: float, lons: np.ndarray, times: np.ndarray) -> np.ndarray:
    """Predict a full year of hourly heights for all lon points at one latitude.

    Returns array of shape (n_lons, n_times) in meters relative to MSL.
    """
    lats = np.full_like(lons, lat)
    x, y = np.atleast_1d(lons), np.atleast_1d(lats)
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
    return np.asarray(tpred)


def _extract_mllw(heights: np.ndarray) -> float:
    """Compute MLLW from a year of hourly heights (meters, relative to MSL)."""
    n = len(heights)
    if n < 48:
        return np.nan
    finite = np.isfinite(heights)
    if np.sum(finite) < n * 0.5:
        return np.nan

    minima_idx = []
    for i in range(1, n - 1):
        if heights[i] < heights[i - 1] and heights[i] <= heights[i + 1]:
            if np.isfinite(heights[i]):
                minima_idx.append(i)
    if len(minima_idx) < 10:
        return np.nan

    days: list[list[int]] = [[minima_idx[0]]]
    for idx in minima_idx[1:]:
        if (idx - days[-1][-1]) < HALF_TIDAL_DAY_HOURS:
            days[-1].append(idx)
        else:
            days.append([idx])

    lower_lows = [min(heights[i] for i in day) for day in days]
    return float(np.mean(lower_lows))


def _make_year_times() -> np.ndarray:
    start = datetime.datetime(REFERENCE_YEAR, 1, 1)
    return np.array(
        [start + datetime.timedelta(hours=h) for h in range(HOURS_IN_YEAR)],
        dtype="datetime64[ms]",
    )


def _process_row_task(args: tuple) -> tuple:
    """Process one latitude row using batch prediction. Returns (row_index, row_data)."""
    row_idx, lat, lons, times, progress_dir = args

    row_file = os.path.join(progress_dir, f"row_{row_idx:04d}.npy")
    if os.path.exists(row_file):
        return (row_idx, np.load(row_file))

    try:
        heights_2d = _predict_row_batch(lat, lons, times)
    except Exception:
        row = np.full(len(lons), np.nan)
        np.save(row_file, row)
        return (row_idx, row)

    row = np.full(len(lons), np.nan)
    for j in range(len(lons)):
        h = heights_2d[j] if heights_2d.ndim == 2 else heights_2d
        if np.all(~np.isfinite(h)):
            continue
        row[j] = _extract_mllw(h)

    np.save(row_file, row)
    return (row_idx, row)


def _worker_init(data_dir: str) -> None:
    _load_model(data_dir)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compute global MLLW offset grid from FES2022",
    )
    parser.add_argument(
        "--fes-data-dir", required=True,
        help="Path to FES2022 data directory",
    )
    parser.add_argument(
        "--output", default=os.path.join(os.path.dirname(__file__), "..", "data", "mllw_grid.npz"),
        help="Output .npz file path",
    )
    parser.add_argument(
        "--resolution", type=float, default=DEFAULT_RESOLUTION,
        help=f"Grid resolution in degrees (default: {DEFAULT_RESOLUTION})",
    )
    parser.add_argument(
        "--workers", type=int, default=1,
        help="Number of parallel workers",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    progress_dir = os.path.join(os.path.dirname(os.path.abspath(args.output)), "mllw_progress")
    os.makedirs(progress_dir, exist_ok=True)

    lats = np.arange(LAT_RANGE[0], LAT_RANGE[1] + args.resolution, args.resolution)
    lons = np.arange(LON_RANGE[0], LON_RANGE[1], args.resolution)
    times = _make_year_times()

    already_done = sum(
        1 for i in range(len(lats))
        if os.path.exists(os.path.join(progress_dir, f"row_{i:04d}.npy"))
    )

    logger.info(
        "Grid: %d lat x %d lon = %d cells at %.2f° | %d/%d rows done",
        len(lats), len(lons), len(lats) * len(lons), args.resolution,
        already_done, len(lats),
    )

    if already_done >= len(lats):
        logger.info("All rows already computed, assembling grid...")
    else:
        t0 = time.time()
        tasks = [
            (i, lats[i], lons, times, progress_dir)
            for i in range(len(lats))
        ]

        if args.workers <= 1:
            logger.info("Loading FES2022 model (single process)...")
            _load_model(args.fes_data_dir)
            for task in tasks:
                row_idx = task[0]
                if os.path.exists(os.path.join(progress_dir, f"row_{row_idx:04d}.npy")):
                    continue
                _, row = _process_row_task(task)
                done = sum(1 for i in range(len(lats)) if os.path.exists(os.path.join(progress_dir, f"row_{i:04d}.npy")))
                valid = int(np.sum(~np.isnan(row)))
                elapsed = time.time() - t0
                new_done = done - already_done
                rate = new_done / elapsed if elapsed > 0 else 0
                remaining = len(lats) - done
                eta_min = remaining / rate / 60 if rate > 0 else 0
                logger.info(
                    "Row %d/%d lat=%.1f: %d ocean [%d/%d done, ETA %.1f min]",
                    row_idx + 1, len(lats), lats[row_idx], valid, done, len(lats), eta_min,
                )
        else:
            logger.info("Starting %d workers (batch mode)...", args.workers)
            with Pool(args.workers, initializer=_worker_init, initargs=(args.fes_data_dir,)) as pool:
                for row_idx, row in pool.imap_unordered(_process_row_task, tasks):
                    done = sum(1 for i in range(len(lats)) if os.path.exists(os.path.join(progress_dir, f"row_{i:04d}.npy")))
                    valid = int(np.sum(~np.isnan(row)))
                    elapsed = time.time() - t0
                    new_done = done - already_done
                    rate = new_done / elapsed if elapsed > 0 else 0
                    remaining = len(lats) - done
                    eta_min = remaining / rate / 60 if rate > 0 else 0
                    logger.info(
                        "Row %d/%d lat=%.1f: %d ocean [%d/%d done, ETA %.1f min]",
                        row_idx + 1, len(lats), lats[row_idx], valid, done, len(lats), eta_min,
                    )

    # Assemble final grid
    logger.info("Assembling final grid...")
    grid = np.full((len(lats), len(lons)), np.nan)
    for i in range(len(lats)):
        row_file = os.path.join(progress_dir, f"row_{i:04d}.npy")
        if os.path.exists(row_file):
            grid[i] = np.load(row_file)

    ocean_cells = int(np.sum(~np.isnan(grid)))
    logger.info("Grid complete: %d ocean cells", ocean_cells)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    np.savez_compressed(
        args.output,
        mllw_offset=grid, lat=lats, lon=lons,
        resolution=np.array(args.resolution),
        model=np.array("FES2022"),
        reference_year=np.array(REFERENCE_YEAR),
    )
    size_mb = os.path.getsize(args.output) / (1024 * 1024)
    logger.info("Saved to %s (%.1f MB)", args.output, size_mb)

    # Validation
    from scipy.interpolate import RegularGridInterpolator
    interp = RegularGridInterpolator(
        (lats, lons), grid, method="linear", bounds_error=False, fill_value=np.nan,
    )
    METERS_TO_FEET = 3.28084
    spots = [
        ("San Francisco", 37.81, -122.47),
        ("Miami Beach", 25.77, -80.13),
        ("Honolulu", 21.31, -157.86),
        ("Pipeline (Oahu)", 21.66, -158.05),
        ("Ocean Beach SD", 32.75, -117.25),
    ]
    logger.info("--- Validation (MLLW offset from MSL) ---")
    for name, lat, lon in spots:
        val = float(interp((lat, lon)))
        if np.isfinite(val):
            logger.info("  %s: %.3f m (%.2f ft)", name, val, abs(val) * METERS_TO_FEET)
        else:
            logger.info("  %s: NaN (land or no data)", name)


if __name__ == "__main__":
    main()
