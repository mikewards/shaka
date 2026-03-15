#!/usr/bin/env python3
"""
Copernicus CMEMS → WeatherLayers GL PNG pipeline.

Downloads global ocean forecast data, processes each variable and time step
into EPSG:4326 PNGs suitable for WeatherLayers GL, and writes a catalog.json.

Vector data (currents): R=U, G=V, B=V(dup), A=mask  →  imageType: VECTOR
Scalar data (SST, etc): R=value, G=0, B=0, A=mask    →  imageType: SCALAR

Usage:
  python weather_pipeline.py [--output-dir /data/weather] [--days 5]

Env vars (copernicusmarine CLI reads these automatically):
  COPERNICUSMARINE_SERVICE_USERNAME
  COPERNICUSMARINE_SERVICE_PASSWORD
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

import numpy as np
import xarray as xr
from PIL import Image


def _ensure_cmems_credentials():
    """Map Railway env vars to what copernicusmarine CLI expects, if needed."""
    u = os.environ.get("COPERNICUSMARINE_SERVICE_USERNAME")
    p = os.environ.get("COPERNICUSMARINE_SERVICE_PASSWORD")
    if u and p:
        return
    print("ERROR: COPERNICUSMARINE_SERVICE_USERNAME and "
          "COPERNICUSMARINE_SERVICE_PASSWORD must be set.\n"
          "Register at https://marine.copernicus.eu and add these to Railway.",
          file=sys.stderr)
    sys.exit(1)


DATASETS = {
    "phy_currents": {
        "dataset_id": "cmems_mod_glo_phy-cur_anfc_0.083deg_P1D-m",
        "variables": {
            "currents": {"vars": ["uo", "vo"], "type": "vector", "scale": [-3, 3]},
        },
        "stride_hours": 24,
        "depth": 0.5,
    },
    "phy_sst": {
        "dataset_id": "cmems_mod_glo_phy-thetao_anfc_0.083deg_P1D-m",
        "variables": {
            "sst": {"vars": ["thetao"], "type": "scalar", "scale": [-2, 35]},
        },
        "stride_hours": 24,
        "depth": 0.5,
    },
    "phy_salinity": {
        "dataset_id": "cmems_mod_glo_phy-so_anfc_0.083deg_P1D-m",
        "variables": {
            "salinity": {"vars": ["so"], "type": "scalar", "scale": [20, 40]},
        },
        "stride_hours": 24,
        "depth": 0.5,
    },
    "wav": {
        "dataset_id": "cmems_mod_glo_wav_anfc_0.083deg_PT3H-i",
        "variables": {
            "waves": {"vars": ["VHM0"], "type": "scalar", "scale": [0, 15]},
        },
        "stride_hours": 3,
        "depth": None,
    },
    "bgc_pft": {
        "dataset_id": "cmems_mod_glo_bgc-pft_anfc_0.25deg_P1D-m",
        "variables": {
            "chlorophyll":   {"vars": ["chl"],  "type": "scalar", "scale": [0, 20]},
            "phytoplankton": {"vars": ["phyc"], "type": "scalar", "scale": [0, 10]},
        },
        "stride_hours": 24,
        "depth": 0.5,
    },
    "bgc_zoo": {
        "dataset_id": "cmems_mod_glo_bgc-plankton_anfc_0.25deg_P1D-m",
        "variables": {
            "zooplankton": {"vars": ["zooc"], "type": "scalar", "scale": [0, 5]},
        },
        "stride_hours": 24,
        "depth": 0.5,
    },
}


def download_dataset(dataset_id, variables, start_dt, end_dt, depth, output_path):
    """Download a CMEMS dataset using the copernicusmarine CLI."""
    cmd = [
        "copernicusmarine", "subset",
        "--dataset-id", dataset_id,
        "--start-datetime", start_dt.strftime("%Y-%m-%dT%H:%M:%S"),
        "--end-datetime", end_dt.strftime("%Y-%m-%dT%H:%M:%S"),
        "--minimum-longitude", "-180",
        "--maximum-longitude", "180",
        "--minimum-latitude", "-90",
        "--maximum-latitude", "90",
        "--output-directory", str(output_path.parent),
        "--output-filename", output_path.name,
        "--overwrite",
    ]
    for var in variables:
        cmd.extend(["--variable", var])
    if depth is not None:
        cmd.extend(["--minimum-depth", "0", "--maximum-depth", str(depth)])

    print(f"  Downloading {dataset_id} → {output_path.name}")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    if result.returncode != 0:
        print(f"  DOWNLOAD FAILED ({dataset_id}):")
        print(f"  stdout: {result.stdout[-500:]}")
        print(f"  stderr: {result.stderr[-500:]}")
        return False
    return True


def scale_to_uint8(data, vmin, vmax):
    """Linearly scale float data to 0-255 uint8, NaN → 0."""
    scaled = (data - vmin) / (vmax - vmin) * 255.0
    scaled = np.clip(scaled, 0, 255)
    result = np.nan_to_num(scaled, nan=0).astype(np.uint8)
    return result


def make_mask(data):
    """Alpha channel: 255 where valid, 0 where NaN."""
    return np.where(np.isfinite(data), 255, 0).astype(np.uint8)


def process_scalar(ds, var_name, time_idx, scale):
    """Process a scalar variable into an RGBA PNG array."""
    da = ds[var_name].isel(time=time_idx)
    if "depth" in da.dims:
        da = da.isel(depth=0)
    data = da.values.astype(np.float32)

    # Flip latitude if needed (CMEMS stores lat descending, PNG needs top=90)
    if ds.latitude.values[0] < ds.latitude.values[-1]:
        data = np.flipud(data)

    r = scale_to_uint8(data, scale[0], scale[1])
    alpha = make_mask(data)
    g = np.zeros_like(r)
    b = np.zeros_like(r)
    return np.stack([r, g, b, alpha], axis=-1)


def process_vector(ds, u_name, v_name, time_idx, scale):
    """Process vector (U, V) variables into an RGBA PNG array."""
    u_da = ds[u_name].isel(time=time_idx)
    v_da = ds[v_name].isel(time=time_idx)
    if "depth" in u_da.dims:
        u_da = u_da.isel(depth=0)
        v_da = v_da.isel(depth=0)
    u = u_da.values.astype(np.float32)
    v = v_da.values.astype(np.float32)

    if ds.latitude.values[0] < ds.latitude.values[-1]:
        u = np.flipud(u)
        v = np.flipud(v)

    r = scale_to_uint8(u, scale[0], scale[1])
    g = scale_to_uint8(v, scale[0], scale[1])
    b = g.copy()  # B channel is ignored for vector, duplicate V
    alpha = make_mask(u) & make_mask(v)
    return np.stack([r, g, b, alpha], axis=-1)


def run_pipeline(output_dir, days):
    output = Path(output_dir)
    tmp = output / "_tmp"
    tmp.mkdir(parents=True, exist_ok=True)

    now = datetime.now(timezone.utc)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=days)

    catalog = {}

    for group_name, group in DATASETS.items():
        all_vars = []
        for vconfig in group["variables"].values():
            all_vars.extend(vconfig["vars"])
        all_vars = list(set(all_vars))

        nc_path = tmp / f"{group_name}.nc"
        ok = download_dataset(
            group["dataset_id"], all_vars, start, end,
            group["depth"], nc_path,
        )
        if not ok:
            print(f"  Skipping {group_name} (download failed)")
            continue

        ds = xr.open_dataset(nc_path)
        stride = group["stride_hours"]
        times = ds.time.values
        n_steps = len(times)

        for var_key, vconfig in group["variables"].items():
            var_dir = output / var_key
            var_dir.mkdir(parents=True, exist_ok=True)
            timestamps = []

            for t_idx in range(0, n_steps, max(1, stride // _time_step_hours(times))):
                if t_idx >= n_steps:
                    break
                ts = _to_iso(times[t_idx])
                ts_safe = ts.replace(":", "")
                png_path = var_dir / f"{ts_safe}.png"

                try:
                    if vconfig["type"] == "vector":
                        rgba = process_vector(
                            ds, vconfig["vars"][0], vconfig["vars"][1],
                            t_idx, vconfig["scale"],
                        )
                    else:
                        rgba = process_scalar(
                            ds, vconfig["vars"][0], t_idx, vconfig["scale"],
                        )
                    img = Image.fromarray(rgba, "RGBA")
                    img.save(str(png_path), optimize=True)
                    timestamps.append(ts_safe)
                except Exception as e:
                    print(f"  Error processing {var_key} t={t_idx}: {e}")

            catalog[var_key] = timestamps
            print(f"  {var_key}: {len(timestamps)} frames")

        ds.close()

    catalog_path = output / "catalog.json"
    with open(catalog_path, "w") as f:
        json.dump(catalog, f, indent=2)
    print(f"Catalog written: {catalog_path}")

    shutil.rmtree(tmp, ignore_errors=True)

    total_frames = sum(len(v) for v in catalog.values())
    if total_frames == 0:
        print("PIPELINE FAILED: no data was produced", file=sys.stderr)
        sys.exit(1)
    print(f"Pipeline complete: {total_frames} total frames across {len(catalog)} variables.")


def _time_step_hours(times):
    """Infer the native time step in hours."""
    if len(times) < 2:
        return 1
    dt = (times[1] - times[0]) / np.timedelta64(1, "h")
    return max(1, int(round(dt)))


def _to_iso(np_time):
    """Convert numpy datetime64 to ISO string."""
    ts = (np_time - np.datetime64("1970-01-01T00:00:00")) / np.timedelta64(1, "s")
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")


if __name__ == "__main__":
    _ensure_cmems_credentials()
    parser = argparse.ArgumentParser(description="Weather data pipeline")
    parser.add_argument("--output-dir", default="/data/weather",
                        help="Output directory for PNGs and catalog")
    parser.add_argument("--days", type=int, default=5,
                        help="Forecast days to download")
    args = parser.parse_args()
    run_pipeline(args.output_dir, args.days)
