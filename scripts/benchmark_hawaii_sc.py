#!/usr/bin/env python3
"""
Deep-dive benchmark: Santa Cruz, O'ahu, Maui
Baseline vs Optimized model. TEST ENVIRONMENT ONLY.
"""

import json
import math
import time
import requests
import numpy as np
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
SURFLINE_CACHE = DATA_DIR / "surfline_snapshot.json"
OPENMETEO_CACHE = DATA_DIR / "openmeteo_snapshot.json"
EXPOSURE_CACHE = DATA_DIR / "exposure_cache.json"

METERS_TO_FEET = 3.28084
OPEN = -1.0

# Optimized parameters from Phase B tuning
OPT_SCALE = 0.728
OPT_FLOOR = 0.492
OPT_MID2 = 0.706
OPT_MID5 = 0.950
OPT_CAP = 0.954


def offset_point(lat, lon, bearing_deg, distance_km):
    R = 6371.0
    lat_r, lon_r = math.radians(lat), math.radians(lon)
    b_r = math.radians(bearing_deg)
    d = distance_km / R
    new_lat = math.asin(math.sin(lat_r) * math.cos(d) +
                        math.cos(lat_r) * math.sin(d) * math.cos(b_r))
    new_lon = lon_r + math.atan2(math.sin(b_r) * math.sin(d) * math.cos(lat_r),
                                  math.cos(d) - math.sin(lat_r) * math.sin(new_lat))
    return math.degrees(new_lat), math.degrees(new_lon)


def is_water(lat, lon):
    url = f"https://is-on-water.balbona.me/api/v1/get/{lat:.6f}/{lon:.6f}"
    try:
        r = requests.get(url, timeout=10)
        if r.status_code == 200:
            return r.json().get("isWater", None)
    except:
        pass
    return None


def compute_exposure(lat, lon):
    land_dist = [OPEN] * 16
    for i in range(16):
        bearing = i * 22.5
        for ring_km in [1.0, 2.0, 5.0]:
            s_lat, s_lon = offset_point(lat, lon, bearing, ring_km)
            result = is_water(s_lat, s_lon)
            if result is False:
                land_dist[i] = ring_km
                break
    return land_dist


def land_dist_to_factor_baseline(dist_km):
    if dist_km < 0: return 1.0
    if dist_km <= 1.0: return 0.15
    if dist_km <= 2.0: return 0.15 + 0.30 * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0: return 0.45 + 0.40 * ((dist_km - 2.0) / 3.0)
    return 0.85


def land_dist_to_factor_optimized(dist_km):
    if dist_km < 0: return 1.0
    if dist_km <= 1.0: return OPT_FLOOR
    if dist_km <= 2.0: return OPT_FLOOR + (OPT_MID2 - OPT_FLOOR) * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0: return OPT_MID2 + (OPT_MID5 - OPT_MID2) * ((dist_km - 2.0) / 3.0)
    return OPT_CAP


def attenuate(height_ft, direction_deg, land_distances, factor_fn):
    n = len(land_distances)
    if n == 0 or all(d < 0 for d in land_distances):
        return height_ft, 1.0
    step = 360.0 / n
    norm_dir = ((direction_deg % 360) + 360) % 360
    exact_idx = norm_dir / step
    lower_idx = int(exact_idx) % n
    upper_idx = (lower_idx + 1) % n
    frac = exact_idx - int(exact_idx)
    factor = factor_fn(land_distances[lower_idx]) * (1.0 - frac) + \
             factor_fn(land_distances[upper_idx]) * frac
    return height_ft * factor, factor


def range_error(shaka_h, sl_min, sl_max):
    if sl_min <= shaka_h <= sl_max:
        return 0.0
    return shaka_h - sl_min if shaka_h < sl_min else shaka_h - sl_max


def fetch_openmeteo(lat, lon, target_ts):
    params = {
        "latitude": lat, "longitude": lon,
        "hourly": "wave_height,wave_period,wave_direction",
        "forecast_days": 1, "timeformat": "unixtime",
    }
    try:
        r = requests.get("https://marine-api.open-meteo.com/v1/marine",
                         params=params, timeout=15)
        hourly = r.json().get("hourly", {})
        times = hourly.get("time", [])
        if not times:
            return None
        best_idx = min(range(len(times)), key=lambda j: abs(times[j] - target_ts))
        return {
            "wave_height_m": hourly.get("wave_height", [0])[best_idx] or 0,
            "wave_direction_deg": hourly.get("wave_direction", [0])[best_idx] or 0,
            "wave_period_s": hourly.get("wave_period", [0])[best_idx] or 0,
        }
    except:
        return None


def run_region(region_name, spots_filter, all_spots, om_cache, exp_cache):
    """Run baseline vs optimized for a set of spots."""
    now_utc = int(datetime.now(timezone.utc).timestamp())

    filtered = [s for s in all_spots if spots_filter(s)]
    filtered.sort(key=lambda x: x.get("lon", 0))

    print(f"\n{'=' * 100}")
    print(f"  {region_name}: {len(filtered)} spots")
    print(f"{'=' * 100}")

    # Ensure we have Open-Meteo + exposure for all spots
    needs_om = []
    needs_exp = []
    for s in filtered:
        key = f"{s['lat']:.4f},{s['lon']:.4f}"
        if key not in om_cache:
            needs_om.append(s)
        if key not in exp_cache:
            needs_exp.append(s)

    if needs_om:
        print(f"  Fetching Open-Meteo for {len(needs_om)} spots...")
        for i, s in enumerate(needs_om):
            key = f"{s['lat']:.4f},{s['lon']:.4f}"
            fc = s.get("forecast", [])
            target = min(fc, key=lambda e: abs(e.get("timestamp", 0) - now_utc)).get("timestamp", now_utc) if fc else now_utc
            om = fetch_openmeteo(s["lat"], s["lon"], target)
            if om:
                om_cache[key] = om
            time.sleep(0.2)
        with open(OPENMETEO_CACHE, "w") as f:
            json.dump(om_cache, f)

    if needs_exp:
        print(f"  Computing exposure for {len(needs_exp)} spots (parallel)...")
        def worker(sp):
            return f"{sp['lat']:.4f},{sp['lon']:.4f}", compute_exposure(sp["lat"], sp["lon"])
        done = 0
        with ThreadPoolExecutor(max_workers=8) as pool:
            futs = {pool.submit(worker, sp): sp for sp in needs_exp}
            for fut in as_completed(futs):
                k, profile = fut.result()
                exp_cache[k] = profile
                done += 1
                if done % 10 == 0 or done == len(needs_exp):
                    print(f"    exposure: {done}/{len(needs_exp)}")
                    with open(EXPOSURE_CACHE, "w") as f:
                        json.dump(exp_cache, f)
        with open(EXPOSURE_CACHE, "w") as f:
            json.dump(exp_cache, f)

    # Run comparison
    header = (f"  {'Spot':28s} {'SL Range':>10s} {'OM Raw':>8s} "
              f"{'Base':>7s} {'BErr':>7s} {'Opt':>7s} {'OErr':>7s} {'Delta':>7s}")
    print(header)
    print(f"  {'-'*28} {'-'*10} {'-'*8} {'-'*7} {'-'*7} {'-'*7} {'-'*7} {'-'*7}")

    results = []
    for s in filtered:
        key = f"{s['lat']:.4f},{s['lon']:.4f}"
        om = om_cache.get(key)
        exp = exp_cache.get(key)
        if not om or not exp:
            continue

        fc = s.get("forecast", [])
        best = min(fc, key=lambda e: abs(e.get("timestamp", 0) - now_utc)) if fc else None
        if not best:
            continue
        sl_min, sl_max = float(best["wave_min_ft"]), float(best["wave_max_ft"])
        if sl_min <= 0 and sl_max <= 0:
            continue

        raw_ft = (om.get("wave_height_m", 0) or 0) * METERS_TO_FEET
        wave_dir = om.get("wave_direction_deg", 0) or 0

        base_h, base_f = attenuate(raw_ft, wave_dir, exp, land_dist_to_factor_baseline)
        opt_h, opt_f = attenuate(raw_ft, wave_dir, exp, land_dist_to_factor_optimized)
        opt_h_scaled = opt_h * OPT_SCALE

        base_err = range_error(base_h, sl_min, sl_max)
        opt_err = range_error(opt_h_scaled, sl_min, sl_max)
        delta = abs(base_err) - abs(opt_err)

        sl_str = f"{sl_min:.0f}-{sl_max:.0f}ft"
        arrow = "+" if delta > 0.1 else ("-" if delta < -0.1 else "=")

        print(f"  {s['name']:28s} {sl_str:>10s} {raw_ft:7.1f}ft "
              f"{base_h:6.1f}ft {base_err:+6.1f}f "
              f"{opt_h_scaled:6.1f}ft {opt_err:+6.1f}f "
              f"{arrow}{delta:+5.1f}ft")

        results.append({
            "name": s["name"], "sl_min": sl_min, "sl_max": sl_max,
            "base_err": base_err, "opt_err": opt_err, "delta": delta,
        })

    if results:
        base_mae = np.mean([abs(r["base_err"]) for r in results])
        opt_mae = np.mean([abs(r["opt_err"]) for r in results])
        base_in = sum(1 for r in results if r["base_err"] == 0)
        opt_in = sum(1 for r in results if r["opt_err"] == 0)
        improved = sum(1 for r in results if r["delta"] > 0.1)
        regressed = sum(1 for r in results if r["delta"] < -0.1)
        print(f"\n  SUMMARY: {len(results)} spots")
        print(f"    Baseline MAE={base_mae:.2f}ft  InRange={base_in}/{len(results)}")
        print(f"    Optimized MAE={opt_mae:.2f}ft  InRange={opt_in}/{len(results)}")
        print(f"    Improved: {improved}  Regressed: {regressed}  Unchanged: {len(results)-improved-regressed}")

    return results


def main():
    print("=" * 100)
    print("DEEP-DIVE BENCHMARK: Santa Cruz + O'ahu + Maui")
    print("Baseline (production) vs Optimized (Phase B)")
    print("TEST ENVIRONMENT ONLY - no production changes")
    print("=" * 100)

    with open(SURFLINE_CACHE) as f:
        all_data = json.load(f)
    all_spots = all_data["spots"]

    om_cache = {}
    if OPENMETEO_CACHE.exists():
        with open(OPENMETEO_CACHE) as f:
            om_cache = json.load(f)

    exp_cache = {}
    if EXPOSURE_CACHE.exists():
        with open(EXPOSURE_CACHE) as f:
            exp_cache = json.load(f)

    sc_filter = lambda s: 36.7 < s.get("lat", 0) < 37.2 and -122.3 < s.get("lon", 0) < -121.8
    oahu_filter = lambda s: 21.2 < s.get("lat", 0) < 21.75 and -158.4 < s.get("lon", 0) < -157.6
    maui_filter = lambda s: 20.6 < s.get("lat", 0) < 21.15 and -156.8 < s.get("lon", 0) < -155.9

    sc_results = run_region("SANTA CRUZ", sc_filter, all_spots, om_cache, exp_cache)
    oahu_results = run_region("O'AHU", oahu_filter, all_spots, om_cache, exp_cache)
    maui_results = run_region("MAUI", maui_filter, all_spots, om_cache, exp_cache)

    all_results = sc_results + oahu_results + maui_results
    if all_results:
        print(f"\n{'=' * 100}")
        print(f"OVERALL: {len(all_results)} spots across 3 regions")
        print(f"{'=' * 100}")
        base_mae = np.mean([abs(r["base_err"]) for r in all_results])
        opt_mae = np.mean([abs(r["opt_err"]) for r in all_results])
        base_in = sum(1 for r in all_results if r["base_err"] == 0)
        opt_in = sum(1 for r in all_results if r["opt_err"] == 0)
        print(f"  Baseline MAE={base_mae:.2f}ft  InRange={base_in}/{len(all_results)}")
        print(f"  Optimized MAE={opt_mae:.2f}ft  InRange={opt_in}/{len(all_results)}")


if __name__ == "__main__":
    main()
