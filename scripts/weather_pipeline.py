#!/usr/bin/env python3
"""
Ocean forecast → WeatherLayers GL WebP pipeline.

Downloads global ocean/atmosphere forecast data from CMEMS and ECMWF,
processes each variable and time step into EPSG:4326 WebP (lossless)
suitable for WeatherLayers GL, writes a catalog.json, and optionally
uploads everything to Cloudflare R2 for CDN delivery.

Vector data (currents, wind): R=U, G=V, B=V(dup), A=mask → imageType: VECTOR
Scalar data (SST, etc):       R=value, G=0, B=0, A=mask  → imageType: SCALAR

Usage:
  python weather_pipeline.py [--output-dir /data/weather] [--days 5]

Env vars (copernicusmarine CLI reads these automatically):
  COPERNICUSMARINE_SERVICE_USERNAME
  COPERNICUSMARINE_SERVICE_PASSWORD

R2 CDN upload (optional — skipped if not set):
  R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME
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
    "wind": {
        "source": "ecmwf",
        "variables": {
            "wind": {"vars": ["u10", "v10"], "type": "vector", "scale": [-30, 30]},
        },
        "stride_hours": 3,
        "depth": None,
    },
}


def download_ecmwf_wind(days, output_path):
    """Download 10m wind forecast from ECMWF IFS Open Data (free, no credentials).

    Pins to the 00z run so timestamps start at today midnight UTC, matching
    CMEMS forecast variables. Falls back to yesterday's 00z if today's isn't
    available yet (00z data appears ~07-09 UTC).
    """
    from ecmwf.opendata import Client

    client = Client(source="ecmwf", model="ifs", resol="0p25")
    now = datetime.now(timezone.utc)
    today = now.strftime("%Y-%m-%d")
    yesterday = (now - timedelta(days=1)).strftime("%Y-%m-%d")

    steps_today = list(range(0, days * 24 + 1, 3))

    try:
        print(f"  Downloading ECMWF IFS wind (00z {today}, steps 0-{steps_today[-1]}h)")
        client.retrieve(
            date=today, time=0, type="fc",
            param=["10u", "10v"],
            step=steps_today,
            target=str(output_path),
        )
        return True
    except Exception as e:
        print(f"  Today 00z not available ({e}), trying yesterday 00z")

    steps_yesterday = list(range(24, (days + 1) * 24 + 1, 3))
    print(f"  Downloading ECMWF IFS wind (00z {yesterday}, steps 24-{steps_yesterday[-1]}h)")
    client.retrieve(
        date=yesterday, time=0, type="fc",
        param=["10u", "10v"],
        step=steps_yesterday,
        target=str(output_path),
    )
    return True


def _open_ecmwf_grib(path):
    """Open ECMWF GRIB2 file and normalize to match CMEMS xarray conventions.

    Handles cfgrib's time/step dimensions, 0-360 longitude, and coordinate
    naming differences so the rest of the pipeline can process it identically
    to CMEMS NetCDF data.
    """
    ds = xr.open_dataset(str(path), engine="cfgrib")

    if "step" in ds.dims:
        valid_times = ds.time.values + ds.step.values
        ds = ds.assign_coords(time=("step", valid_times)).swap_dims({"step": "time"})
    elif "valid_time" in ds.coords and "time" not in ds.dims:
        if "valid_time" in ds.dims:
            ds = ds.rename({"valid_time": "time"})
        else:
            ds = ds.swap_dims({list(ds.dims)[0]: "valid_time"}).rename({"valid_time": "time"})

    if ds.longitude.values.max() > 180:
        ds = ds.assign_coords(
            longitude=((ds.longitude + 180) % 360) - 180
        ).sortby("longitude")

    if "lat" in ds.dims and "latitude" not in ds.dims:
        ds = ds.rename({"lat": "latitude", "lon": "longitude"})

    return ds


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


def scale_to_uint8(data, vmin, vmax, nan_value=127.5):
    """Linearly scale float data to 0-255 uint8, NaN → nan_value."""
    scaled = (data - vmin) / (vmax - vmin) * 255.0
    scaled = np.clip(scaled, 0, 255)
    result = np.nan_to_num(scaled, nan=nan_value).astype(np.uint8)
    return result


def make_mask(data):
    """Alpha channel: fully opaque everywhere (land polygon handles masking)."""
    return np.full(data.shape, 255, dtype=np.uint8)


def process_scalar(ds, var_name, time_idx, scale):
    """Process a scalar variable into an RGBA PNG array."""
    da = ds[var_name].isel(time=time_idx)
    if "depth" in da.dims:
        da = da.isel(depth=0)
    data = da.values.astype(np.float32)

    # Flip latitude if needed (CMEMS stores lat descending, PNG needs top=90)
    if ds.latitude.values[0] < ds.latitude.values[-1]:
        data = np.flipud(data)

    r = scale_to_uint8(data, scale[0], scale[1], nan_value=0)
    alpha = make_mask(data)
    g = np.zeros_like(r)
    b = np.zeros_like(r)
    return np.stack([r, g, b, alpha], axis=-1)


def process_vector(ds, u_name, v_name, time_idx, scale, land_zero_mask=None):
    """Process vector (U, V) variables into an RGBA PNG array."""
    u_da = ds[u_name].isel(time=time_idx)
    v_da = ds[v_name].isel(time=time_idx)
    if "depth" in u_da.dims:
        u_da = u_da.isel(depth=0)
        v_da = v_da.isel(depth=0)
    u = u_da.values.astype(np.float32)
    v = v_da.values.astype(np.float32)

    if land_zero_mask is not None:
        u = np.where(land_zero_mask, 0.0, u)
        v = np.where(land_zero_mask, 0.0, v)

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

        data_path = tmp / f"{group_name}.nc"

        if group.get("source") == "ecmwf":
            data_path = tmp / f"{group_name}.grib2"
            try:
                ok = download_ecmwf_wind(days, data_path)
            except Exception as e:
                print(f"  ECMWF download failed ({group_name}): {e}")
                ok = False
            if not ok:
                print(f"  Skipping {group_name} (ECMWF download failed)")
                continue
            ds = _open_ecmwf_grib(data_path)
        else:
            g_start = start
            g_end = end
            ok = download_dataset(
                group["dataset_id"], all_vars, g_start, g_end,
                group["depth"], data_path,
            )
            if not ok:
                print(f"  Skipping {group_name} (download failed)")
                continue
            ds = xr.open_dataset(data_path)

        stride = group["stride_hours"]
        times = ds.time.values
        n_steps = len(times)

        lats = ds.latitude.values
        lons = ds.longitude.values
        bounds = [float(lons.min()), float(lats.min()), float(lons.max()), float(lats.max())]
        print(f"  {group_name} bounds: {bounds} (lat {len(lats)} x lon {len(lons)})")

        for var_key, vconfig in group["variables"].items():
            var_dir = output / var_key
            var_dir.mkdir(parents=True, exist_ok=True)
            timestamps = []

            for t_idx in range(0, n_steps, max(1, stride // _time_step_hours(times))):
                if t_idx >= n_steps:
                    break
                ts = _to_iso(times[t_idx])
                ts_safe = ts.replace(":", "")
                webp_path = var_dir / f"{ts_safe}.webp"

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
                    img.save(str(webp_path), format="WEBP", lossless=True, method=0)
                    timestamps.append(ts_safe)
                except Exception as e:
                    print(f"  Error processing {var_key} t={t_idx}: {e}")

            catalog[var_key] = {"timestamps": timestamps, "bounds": bounds}
            print(f"  {var_key}: {len(timestamps)} frames")

        ds.close()

    catalog_path = output / "catalog.json"
    with open(catalog_path, "w") as f:
        json.dump(catalog, f, indent=2)
    print(f"Catalog written: {catalog_path}")

    _cleanup_old_tiles(output, catalog)

    shutil.rmtree(tmp, ignore_errors=True)

    total_frames = sum(len(v["timestamps"]) for v in catalog.values())
    if total_frames == 0:
        print("PIPELINE FAILED: no data was produced", file=sys.stderr)
        sys.exit(1)
    print(f"Pipeline complete: {total_frames} total frames across {len(catalog)} variables.")

    _upload_to_r2(output)


def _cleanup_old_tiles(output_dir, catalog):
    """Delete orphaned WebP tiles not referenced by the current catalog."""
    removed = 0
    for var_key, info in catalog.items():
        var_dir = output_dir / var_key
        if not var_dir.is_dir():
            continue
        valid = set(ts + ".webp" for ts in info["timestamps"])
        for f in var_dir.iterdir():
            if f.suffix == ".webp" and f.name not in valid:
                f.unlink()
                removed += 1
    if removed:
        print(f"  Cleaned up {removed} orphaned tile(s)")


def _upload_to_r2(output_dir):
    """Upload all weather files to Cloudflare R2 for CDN delivery."""
    account_id = os.environ.get("R2_ACCOUNT_ID")
    access_key = os.environ.get("R2_ACCESS_KEY_ID")
    secret_key = os.environ.get("R2_SECRET_ACCESS_KEY")
    bucket = os.environ.get("R2_BUCKET_NAME", "shaka-weather")

    if not all([account_id, access_key, secret_key]):
        print("  R2 credentials not set, skipping CDN upload")
        return

    try:
        import boto3
    except ImportError:
        print("  boto3 not installed, skipping CDN upload")
        return

    endpoint = f"https://{account_id}.r2.cloudflarestorage.com"
    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name="auto",
    )

    uploaded = 0
    output = Path(output_dir)

    catalog_path = output / "catalog.json"
    if catalog_path.exists():
        s3.upload_file(
            str(catalog_path), bucket, "catalog.json",
            ExtraArgs={"ContentType": "application/json", "CacheControl": "public, max-age=300"},
        )
        uploaded += 1

    for webp_file in sorted(output.rglob("*.webp")):
        key = str(webp_file.relative_to(output))
        s3.upload_file(
            str(webp_file), bucket, key,
            ExtraArgs={"ContentType": "image/webp", "CacheControl": "public, max-age=21600"},
        )
        uploaded += 1

    print(f"  Uploaded {uploaded} files to R2 CDN ({bucket})")


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
