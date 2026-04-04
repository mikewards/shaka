#!/usr/bin/env python3
"""
Surfline vs Shaka Swell Comparison Benchmark (Phase A)

Fetches Surfline wave heights via Apify, computes Shaka's attenuated swell
for the same coordinates, compares them, and produces a review report.
"""

import json
import math
import os
import random
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import requests

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

SURFLINE_CACHE = DATA_DIR / "surfline_snapshot.json"
OPENMETEO_CACHE = DATA_DIR / "openmeteo_snapshot.json"
EXPOSURE_CACHE = DATA_DIR / "exposure_cache.json"
RESULTS_CSV = DATA_DIR / "benchmark_results.csv"
SUMMARY_FILE = DATA_DIR / "benchmark_summary.txt"

METERS_TO_FEET = 3.28084
NUM_DIRECTIONS = 16
DIRECTION_STEP_DEG = 360.0 / NUM_DIRECTIONS
RING_DISTANCES_KM = [1.0, 2.0, 5.0]
OPEN = -1.0

# ---------------------------------------------------------------------------
# Surfline data via Apify
# ---------------------------------------------------------------------------

LOCATION_QUERIES = [
    ("Pipeline", "Hawaii", 5),
    ("Sunset Beach", "Hawaii", 5),
    ("Waikiki", "Hawaii", 5),
    ("Hookipa", "Hawaii", 3),
    ("Hanalei", "Hawaii", 3),
    ("Huntington Beach", "California", 5),
    ("Malibu", "California", 3),
    ("Trestles", "California", 3),
    ("Blacks Beach", "California", 3),
    ("Rincon", "California", 3),
    ("Ocean Beach San Francisco", "California", 3),
    ("Santa Cruz", "California", 5),
    ("Ventura", "California", 3),
    ("San Clemente", "California", 3),
    ("Oceanside", "California", 3),
    ("Pacifica", "California", 3),
    ("Mavericks", "California", 2),
    ("Outer Banks", "East Coast", 5),
    ("Cocoa Beach", "East Coast", 3),
    ("Wrightsville Beach", "East Coast", 3),
    ("Montauk", "East Coast", 3),
    ("Asbury Park", "East Coast", 3),
    ("Hossegor", "Europe", 3),
    ("Nazare", "Europe", 3),
    ("Peniche", "Europe", 3),
    ("Snapper Rocks", "Australia", 3),
    ("Bells Beach", "Australia", 3),
    ("Uluwatu", "Indonesia", 3),
    ("Puerto Escondido", "Mexico", 3),
    ("Sayulita", "Mexico", 2),
]


def fetch_surfline_data(force=False):
    """Fetch Surfline forecasts for ~100 spots via Apify locationSearch."""
    if SURFLINE_CACHE.exists() and not force:
        print(f"[Surfline] Using cached data from {SURFLINE_CACHE}")
        with open(SURFLINE_CACHE) as f:
            return json.load(f)

    token = os.environ.get("APIFY_API_TOKEN")
    if not token:
        print("[Surfline] ERROR: APIFY_API_TOKEN not set in environment.")
        print("  Run: export $(cat .env | xargs)  (from repo root)")
        sys.exit(1)

    from apify_client import ApifyClient
    client = ApifyClient(token)

    all_spots = []
    seen_ids = set()

    for query, region_tag, max_spots in LOCATION_QUERIES:
        print(f"[Surfline] Searching '{query}' (max {max_spots})...")
        try:
            run = client.actor("fortuitous_pirate/surfline-forecast").call(
                run_input={
                    "locationSearch": query,
                    "maxSpots": max_spots,
                    "days": 1,
                    "proxyConfiguration": {
                        "useApifyProxy": True,
                        "apifyProxyGroups": ["RESIDENTIAL"],
                    },
                },
                timeout_secs=120,
            )

            for item in client.dataset(run["defaultDatasetId"]).iterate_items():
                spot_info = item.get("spot", {})
                spot_id = spot_info.get("id", "")
                if spot_id in seen_ids:
                    continue
                seen_ids.add(spot_id)
                item["_region_tag"] = region_tag
                all_spots.append(item)

        except Exception as e:
            print(f"  WARNING: Failed for '{query}': {e}")

    snapshot = {
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(),
        "total_spots": len(all_spots),
        "spots": all_spots,
    }

    with open(SURFLINE_CACHE, "w") as f:
        json.dump(snapshot, f)
    print(f"[Surfline] Cached {len(all_spots)} spots to {SURFLINE_CACHE}")

    return snapshot


def select_benchmark_spots(surfline_data, seed=42, max_spots=500):
    """Select a diverse subset of spots for benchmarking.

    Supports both scraper format (flat: name, lat, lon, spot_id, region)
    and legacy Apify format (nested: spot.{id, name, lat, lon}).
    Picks the closest forecast entry to now for each spot.
    """
    raw_spots = surfline_data.get("spots", [])
    if not raw_spots:
        print("[Select] ERROR: No spots in Surfline data")
        sys.exit(1)

    print(f"[Select] Total Surfline spots available: {len(raw_spots)}")

    now_utc = int(datetime.now(timezone.utc).timestamp())
    valid = []

    for s in raw_spots:
        if "spot" in s and isinstance(s["spot"], dict):
            spot_info = s["spot"]
            lat = spot_info.get("lat")
            lon = spot_info.get("lon")
            name = spot_info.get("name", "Unknown")
            region = s.get("_region_tag", spot_info.get("subregion", "Unknown"))
            spot_id = spot_info.get("id", "")
        else:
            lat = s.get("lat")
            lon = s.get("lon")
            name = s.get("name", "Unknown")
            region = s.get("region", "Unknown")
            spot_id = s.get("spot_id", "")

        if lat is None or lon is None:
            continue

        forecast = s.get("forecast", [])
        if not forecast:
            continue

        best = None
        best_delta = float("inf")
        for entry in forecast:
            ts = entry.get("timestamp")
            if ts is None:
                continue
            delta = abs(ts - now_utc)
            if delta < best_delta:
                best_delta = delta
                best = entry

        if best is None:
            continue

        sl_min = best.get("wave_min_ft")
        sl_max = best.get("wave_max_ft")
        if sl_min is None or sl_max is None:
            continue
        sl_min, sl_max = float(sl_min), float(sl_max)
        if sl_min <= 0 and sl_max <= 0:
            continue

        valid.append({
            "name": name,
            "region": region,
            "lat": float(lat),
            "lon": float(lon),
            "surfline_min": sl_min,
            "surfline_max": sl_max,
            "surfline_mid": (sl_min + sl_max) / 2.0,
            "surfline_timestamp": best.get("timestamp", now_utc),
            "surfline_swell_height": best.get("swell_height_ft", best.get("swell_height")),
            "surfline_swell_period": best.get("swell_period_s", best.get("swell_period")),
            "surfline_swell_direction": best.get("swell_direction_deg", best.get("swell_direction")),
            "spot_id": spot_id,
        })

    print(f"[Select] Spots with valid wave data + coords: {len(valid)}")

    rng = random.Random(seed)
    rng.shuffle(valid)

    if max_spots and len(valid) > max_spots:
        valid = valid[:max_spots]
        print(f"[Select] Capped to {max_spots} spots for benchmark")

    holdout_count = max(1, len(valid) * 30 // 100)
    for i, sp in enumerate(valid):
        sp["is_holdout"] = i < holdout_count

    train = sum(1 for s in valid if not s["is_holdout"])
    holdout = sum(1 for s in valid if s["is_holdout"])
    print(f"[Select] Selected {len(valid)} spots: {train} train, {holdout} holdout")

    return valid


# ---------------------------------------------------------------------------
# Open-Meteo raw swell
# ---------------------------------------------------------------------------

def fetch_openmeteo_swell(spots, force=False):
    """Fetch raw swell data from Open-Meteo for each spot."""
    if OPENMETEO_CACHE.exists() and not force:
        print(f"[OpenMeteo] Using cached data from {OPENMETEO_CACHE}")
        with open(OPENMETEO_CACHE) as f:
            return json.load(f)

    results = {}
    total = len(spots)

    for i, sp in enumerate(spots):
        key = f"{sp['lat']:.4f},{sp['lon']:.4f}"
        if key in results:
            continue

        params = {
            "latitude": sp["lat"],
            "longitude": sp["lon"],
            "hourly": "wave_height,wave_period,wave_direction,"
                      "swell_wave_height,swell_wave_period,swell_wave_direction",
            "forecast_days": 1,
            "timeformat": "unixtime",
        }

        try:
            r = requests.get("https://marine-api.open-meteo.com/v1/marine",
                             params=params, timeout=15)
            r.raise_for_status()
            data = r.json()
            hourly = data.get("hourly", {})

            now_utc = int(datetime.now(timezone.utc).timestamp())
            sl_ts = sp.get("surfline_timestamp", now_utc)
            target_ts = sl_ts if sl_ts else now_utc

            times = hourly.get("time", [])
            best_idx = 0
            best_delta = abs(times[0] - target_ts) if times else float("inf")
            for j, t in enumerate(times):
                delta = abs(t - target_ts)
                if delta < best_delta:
                    best_delta = delta
                    best_idx = j

            def safe_get(arr, idx):
                if arr and idx < len(arr):
                    v = arr[idx]
                    return v if v is not None else 0.0
                return 0.0

            results[key] = {
                "matched_timestamp": times[best_idx] if times else None,
                "time_delta_sec": best_delta,
                "wave_height_m": safe_get(hourly.get("wave_height"), best_idx),
                "wave_period_s": safe_get(hourly.get("wave_period"), best_idx),
                "wave_direction_deg": safe_get(hourly.get("wave_direction"), best_idx),
                "swell_height_m": safe_get(hourly.get("swell_wave_height"), best_idx),
                "swell_period_s": safe_get(hourly.get("swell_wave_period"), best_idx),
                "swell_direction_deg": safe_get(hourly.get("swell_wave_direction"), best_idx),
            }

        except Exception as e:
            print(f"  WARNING: OpenMeteo failed for {sp['name']}: {e}")
            results[key] = None

        if (i + 1) % 10 == 0 or i == total - 1:
            print(f"[OpenMeteo] {i+1}/{total} spots fetched")

        time.sleep(0.2)

    with open(OPENMETEO_CACHE, "w") as f:
        json.dump(results, f)
    print(f"[OpenMeteo] Cached {len(results)} results to {OPENMETEO_CACHE}")

    return results


# ---------------------------------------------------------------------------
# Exposure profiles (land/water checks)
# ---------------------------------------------------------------------------

def offset_point(lat, lon, bearing_deg, distance_km):
    """Compute lat/lon at a given bearing and distance from a point."""
    R = 6371.0
    lat_r = math.radians(lat)
    lon_r = math.radians(lon)
    b_r = math.radians(bearing_deg)
    d = distance_km / R

    new_lat = math.asin(math.sin(lat_r) * math.cos(d) +
                        math.cos(lat_r) * math.sin(d) * math.cos(b_r))
    new_lon = lon_r + math.atan2(math.sin(b_r) * math.sin(d) * math.cos(lat_r),
                                  math.cos(d) - math.sin(lat_r) * math.sin(new_lat))
    return math.degrees(new_lat), math.degrees(new_lon)


def is_water(lat, lon):
    """Check if a point is water via the land/water API."""
    url = f"https://is-on-water.balbona.me/api/v1/get/{lat:.6f}/{lon:.6f}"
    try:
        r = requests.get(url, timeout=10)
        if r.status_code == 200:
            data = r.json()
            return data.get("isWater", None)
    except Exception:
        pass
    return None


def compute_exposure(lat, lon):
    """Compute 16-direction land distance profile for a spot."""
    land_dist = [OPEN] * NUM_DIRECTIONS

    for i in range(NUM_DIRECTIONS):
        bearing = i * DIRECTION_STEP_DEG
        for ring_km in RING_DISTANCES_KM:
            s_lat, s_lon = offset_point(lat, lon, bearing, ring_km)
            result = is_water(s_lat, s_lon)
            if result is False:
                land_dist[i] = ring_km
                break

    return land_dist


def fetch_exposure_profiles(spots, force=False):
    """Compute exposure profiles for all spots using parallel workers."""
    from concurrent.futures import ThreadPoolExecutor, as_completed

    cache = {}
    if EXPOSURE_CACHE.exists() and not force:
        with open(EXPOSURE_CACHE) as f:
            cache = json.load(f)

    to_compute = []
    for sp in spots:
        key = f"{sp['lat']:.4f},{sp['lon']:.4f}"
        if key not in cache:
            to_compute.append(sp)

    if not to_compute:
        print(f"[Exposure] All {len(cache)} profiles loaded from cache")
        return cache

    print(f"[Exposure] Need to compute {len(to_compute)} new profiles ({len(cache)} cached)")
    computed = 0

    def worker(sp):
        return (
            f"{sp['lat']:.4f},{sp['lon']:.4f}",
            sp["name"],
            compute_exposure(sp["lat"], sp["lon"]),
        )

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(worker, sp): sp for sp in to_compute}
        for future in as_completed(futures):
            key, name, profile = future.result()
            cache[key] = profile
            computed += 1
            if computed % 20 == 0 or computed == len(to_compute):
                print(f"[Exposure] {computed}/{len(to_compute)} computed")
                with open(EXPOSURE_CACHE, "w") as f:
                    json.dump(cache, f)

    with open(EXPOSURE_CACHE, "w") as f:
        json.dump(cache, f)
    print(f"[Exposure] Done: {computed} new + {len(cache)-computed} cached = {len(cache)} total")

    return cache


# ---------------------------------------------------------------------------
# Shaka attenuation model (Python port)
# ---------------------------------------------------------------------------

def land_dist_to_factor(dist_km):
    """Port of SpotDataCache.landDistToFactor() from Kotlin."""
    if dist_km < 0:
        return 1.0
    if dist_km <= 1.0:
        return 0.15
    if dist_km <= 2.0:
        return 0.15 + 0.30 * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0:
        return 0.45 + 0.40 * ((dist_km - 2.0) / 3.0)
    return 0.85


def attenuate_swell(height_ft, direction_deg, land_distances):
    """Port of SpotDataCache.attenuateSwell() from Kotlin."""
    if len(land_distances) != 16:
        return height_ft
    if all(d < 0 for d in land_distances):
        return height_ft

    step = 360.0 / 16
    norm_dir = ((direction_deg % 360) + 360) % 360
    exact_idx = norm_dir / step
    lower_idx = int(exact_idx) % 16
    upper_idx = (lower_idx + 1) % 16
    frac = exact_idx - int(exact_idx)

    lower_factor = land_dist_to_factor(land_distances[lower_idx])
    upper_factor = land_dist_to_factor(land_distances[upper_idx])
    factor = lower_factor * (1.0 - frac) + upper_factor * frac

    return height_ft * factor


# ---------------------------------------------------------------------------
# Comparison and analysis
# ---------------------------------------------------------------------------

def range_error(shaka_h, sl_min, sl_max):
    """Error relative to Surfline's min/max range. 0 if within range."""
    if sl_min <= shaka_h <= sl_max:
        return 0.0
    elif shaka_h < sl_min:
        return shaka_h - sl_min
    else:
        return shaka_h - sl_max


def run_comparison(spots, openmeteo_data, exposure_data):
    """Run the full comparison for all spots."""
    results = []

    for sp in spots:
        key = f"{sp['lat']:.4f},{sp['lon']:.4f}"
        om = openmeteo_data.get(key)
        exposure = exposure_data.get(key)

        if om is None or exposure is None:
            continue

        raw_wave_m = om.get("wave_height_m", 0)
        raw_wave_ft = raw_wave_m * METERS_TO_FEET
        wave_dir = om.get("wave_direction_deg", 0)
        wave_period = om.get("wave_period_s", 0)

        shaka_corrected_ft = attenuate_swell(raw_wave_ft, wave_dir, exposure)
        atten_factor = shaka_corrected_ft / raw_wave_ft if raw_wave_ft > 0 else 1.0

        sl_min = sp["surfline_min"]
        sl_max = sp["surfline_max"]
        sl_mid = sp["surfline_mid"]

        err_range = range_error(shaka_corrected_ft, sl_min, sl_max)
        err_mid = shaka_corrected_ft - sl_mid

        exposure_type = "open"
        if atten_factor < 0.5:
            exposure_type = "sheltered"
        elif atten_factor < 0.9:
            exposure_type = "semi-sheltered"

        size_class = "flat"
        if sl_mid >= 7:
            size_class = "large"
        elif sl_mid >= 4:
            size_class = "medium"
        elif sl_mid >= 2:
            size_class = "small"

        results.append({
            "name": sp["name"],
            "region": sp["region"],
            "lat": sp["lat"],
            "lon": sp["lon"],
            "is_holdout": sp["is_holdout"],
            "surfline_min": sl_min,
            "surfline_max": sl_max,
            "surfline_mid": sl_mid,
            "openmeteo_raw_ft": round(raw_wave_ft, 2),
            "wave_direction": wave_dir,
            "wave_period": wave_period,
            "shaka_corrected_ft": round(shaka_corrected_ft, 2),
            "attenuation_factor": round(atten_factor, 3),
            "error_vs_range": round(err_range, 2),
            "error_vs_mid": round(err_mid, 2),
            "abs_error_range": round(abs(err_range), 2),
            "exposure_type": exposure_type,
            "size_class": size_class,
            "time_delta_sec": om.get("time_delta_sec", 0),
        })

    return results


def write_csv(results):
    """Write results to CSV."""
    if not results:
        return
    headers = list(results[0].keys())
    with open(RESULTS_CSV, "w") as f:
        f.write(",".join(headers) + "\n")
        for r in results:
            vals = []
            for h in headers:
                v = r[h]
                if isinstance(v, str):
                    v = f'"{v}"'
                else:
                    v = str(v)
                vals.append(v)
            f.write(",".join(vals) + "\n")
    print(f"[Output] Results CSV: {RESULTS_CSV}")


def print_summary(results):
    """Print and save analysis summary."""
    lines = []
    def out(s=""):
        lines.append(s)
        print(s)

    out("=" * 70)
    out("SURFLINE vs SHAKA SWELL BENCHMARK -- PHASE A REPORT")
    out(f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
    out("=" * 70)

    train = [r for r in results if not r["is_holdout"]]
    holdout = [r for r in results if r["is_holdout"]]

    out(f"\nTotal spots analyzed: {len(results)}")
    out(f"  Training set: {len(train)}")
    out(f"  Holdout set:  {len(holdout)}")

    for label, subset in [("ALL SPOTS", results), ("TRAINING SET", train), ("HOLDOUT SET", holdout)]:
        if not subset:
            continue
        out(f"\n--- {label} ({len(subset)} spots) ---")

        range_errors = [r["error_vs_range"] for r in subset]
        abs_range_errors = [r["abs_error_range"] for r in subset]
        mid_errors = [r["error_vs_mid"] for r in subset]

        mae = np.mean(abs_range_errors)
        rmse = np.sqrt(np.mean([e**2 for e in range_errors]))
        bias = np.mean(range_errors)
        mean_obs = np.mean([r["surfline_mid"] for r in subset])
        scatter_idx = rmse / mean_obs if mean_obs > 0 else float("inf")

        in_range = sum(1 for e in range_errors if e == 0)
        in_range_pct = in_range / len(subset) * 100

        out(f"  MAE (vs range):     {mae:.2f} ft")
        out(f"  RMSE (vs range):    {rmse:.2f} ft")
        out(f"  Bias:               {bias:+.2f} ft {'(over-predicts)' if bias > 0 else '(under-predicts)'}")
        out(f"  Scatter Index:      {scatter_idx:.3f}")
        out(f"  Within SL range:    {in_range}/{len(subset)} ({in_range_pct:.0f}%)")
        out(f"  Mean Surfline mid:  {mean_obs:.1f} ft")
        out(f"  Mean Shaka:         {np.mean([r['shaka_corrected_ft'] for r in subset]):.1f} ft")
        out(f"  Mean OpenMeteo raw: {np.mean([r['openmeteo_raw_ft'] for r in subset]):.1f} ft")

    # Breakdown by exposure type
    out("\n--- ERROR BY EXPOSURE TYPE ---")
    for exp in ["open", "semi-sheltered", "sheltered"]:
        sub = [r for r in results if r["exposure_type"] == exp]
        if not sub:
            continue
        mae = np.mean([r["abs_error_range"] for r in sub])
        bias = np.mean([r["error_vs_range"] for r in sub])
        out(f"  {exp:16s}: n={len(sub):3d}  MAE={mae:.2f}ft  Bias={bias:+.2f}ft")

    # Breakdown by wave size
    out("\n--- ERROR BY WAVE SIZE ---")
    for sc in ["flat", "small", "medium", "large"]:
        sub = [r for r in results if r["size_class"] == sc]
        if not sub:
            continue
        mae = np.mean([r["abs_error_range"] for r in sub])
        bias = np.mean([r["error_vs_range"] for r in sub])
        out(f"  {sc:8s}: n={len(sub):3d}  MAE={mae:.2f}ft  Bias={bias:+.2f}ft")

    # Upstream vs attenuation error
    out("\n--- UPSTREAM (OpenMeteo) vs ATTENUATION ERROR ---")
    exposed = [r for r in results if r["attenuation_factor"] > 0.95]
    attenuated = [r for r in results if r["attenuation_factor"] <= 0.95]
    if exposed:
        mae_exp = np.mean([r["abs_error_range"] for r in exposed])
        bias_exp = np.mean([r["error_vs_range"] for r in exposed])
        out(f"  Exposed (factor>0.95):    n={len(exposed):3d}  MAE={mae_exp:.2f}ft  Bias={bias_exp:+.2f}ft")
        out(f"    -> This error is from OpenMeteo raw data, NOT attenuation")
    if attenuated:
        mae_att = np.mean([r["abs_error_range"] for r in attenuated])
        bias_att = np.mean([r["error_vs_range"] for r in attenuated])
        out(f"  Attenuated (factor<=0.95): n={len(attenuated):3d}  MAE={mae_att:.2f}ft  Bias={bias_att:+.2f}ft")
        out(f"    -> This error includes both OpenMeteo + attenuation model")

    # Worst discrepancies
    out("\n--- TOP 15 WORST DISCREPANCIES ---")
    sorted_by_err = sorted(results, key=lambda r: abs(r["error_vs_range"]), reverse=True)
    out(f"  {'Spot':<30s} {'SL Range':>10s} {'Shaka':>7s} {'Raw':>7s} {'Err':>7s} {'Factor':>7s} {'Type'}")
    out(f"  {'-'*30} {'-'*10} {'-'*7} {'-'*7} {'-'*7} {'-'*7} {'-'*15}")
    for r in sorted_by_err[:15]:
        sl = f"{r['surfline_min']:.0f}-{r['surfline_max']:.0f}ft"
        out(f"  {r['name']:<30s} {sl:>10s} {r['shaka_corrected_ft']:>6.1f}f {r['openmeteo_raw_ft']:>6.1f}f {r['error_vs_range']:>+6.1f}f {r['attenuation_factor']:>6.2f} {r['exposure_type']}")

    # Best matches
    out("\n--- TOP 10 BEST MATCHES (within Surfline range) ---")
    in_range_spots = [r for r in results if r["error_vs_range"] == 0]
    in_range_spots.sort(key=lambda r: r["surfline_mid"], reverse=True)
    out(f"  {'Spot':<30s} {'SL Range':>10s} {'Shaka':>7s} {'Factor':>7s} {'Type'}")
    for r in in_range_spots[:10]:
        sl = f"{r['surfline_min']:.0f}-{r['surfline_max']:.0f}ft"
        out(f"  {r['name']:<30s} {sl:>10s} {r['shaka_corrected_ft']:>6.1f}f {r['attenuation_factor']:>6.2f} {r['exposure_type']}")

    out("\n" + "=" * 70)
    out("END OF PHASE A REPORT")
    out("Review these results before proceeding to Phase B (model tuning).")
    out("=" * 70)

    with open(SUMMARY_FILE, "w") as f:
        f.write("\n".join(lines))
    print(f"\n[Output] Summary saved to {SUMMARY_FILE}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

THRESHOLDS = {
    "mae_max": 2.5,
    "rmse_max": 3.5,
    "bias_abs_max": 1.5,
    "in_range_pct_min": 30.0,
}


def check_thresholds(results):
    """Check benchmark results against thresholds. Returns (passed, violations)."""
    if not results:
        return False, ["No results to evaluate"]

    abs_range_errors = [r["abs_error_range"] for r in results]
    range_errors = [r["error_vs_range"] for r in results]

    mae = float(np.mean(abs_range_errors))
    rmse = float(np.sqrt(np.mean([e**2 for e in range_errors])))
    bias = float(np.mean(range_errors))
    in_range = sum(1 for e in range_errors if e == 0)
    in_range_pct = in_range / len(results) * 100

    violations = []
    if mae > THRESHOLDS["mae_max"]:
        violations.append(f"MAE {mae:.2f}ft > {THRESHOLDS['mae_max']}ft")
    if rmse > THRESHOLDS["rmse_max"]:
        violations.append(f"RMSE {rmse:.2f}ft > {THRESHOLDS['rmse_max']}ft")
    if abs(bias) > THRESHOLDS["bias_abs_max"]:
        violations.append(f"|Bias| {abs(bias):.2f}ft > {THRESHOLDS['bias_abs_max']}ft")
    if in_range_pct < THRESHOLDS["in_range_pct_min"]:
        violations.append(f"In-range {in_range_pct:.0f}% < {THRESHOLDS['in_range_pct_min']}%")

    if violations:
        print("\n[THRESHOLD CHECK] FAILED:")
        for v in violations:
            print(f"  - {v}")
    else:
        print("\n[THRESHOLD CHECK] PASSED: All metrics within acceptable bounds")

    return len(violations) == 0, violations


def main():
    print("\n" + "=" * 60)
    print("SURFLINE vs SHAKA SWELL BENCHMARK")
    print("=" * 60)

    # Step 1: Load Surfline data (from scraper or Apify cache)
    surfline = fetch_surfline_data()

    # Step 2: Select benchmark spots (200 diverse spots)
    spots = select_benchmark_spots(surfline, max_spots=200)

    # Step 3: Fetch Open-Meteo raw swell
    openmeteo = fetch_openmeteo_swell(spots)

    # Step 4: Compute exposure profiles
    exposure = fetch_exposure_profiles(spots)

    # Step 5: Run comparison
    print("\n[Compare] Running comparison...")
    results = run_comparison(spots, openmeteo, exposure)
    print(f"[Compare] {len(results)} spots compared successfully")

    # Step 6: Output
    write_csv(results)
    print()
    print_summary(results)

    # Step 7: Threshold check (exit 1 if regression detected)
    passed, _ = check_thresholds(results)
    if not passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
