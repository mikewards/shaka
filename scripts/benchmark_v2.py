#!/usr/bin/env python3
"""
Swell Model V2 Benchmark: incremental testing of model improvements.
Compares Current Production vs V2 candidate against Surfline ground truth.
TEST ENVIRONMENT ONLY — no production changes.
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
OPENMETEO_V2_CACHE = DATA_DIR / "openmeteo_v2_snapshot.json"
EXPOSURE_CACHE = DATA_DIR / "exposure_cache.json"
EXPOSURE_V2_CACHE = DATA_DIR / "exposure_v2_cache.json"

RING_DISTANCES_V2 = [0.25, 0.5, 1.0, 2.0, 5.0]

METERS_TO_FEET = 3.28084
OPEN = -1.0

# --- Current production parameters ---
PROD_SCALE = 0.728
PROD_FLOOR = 0.492
PROD_MID2 = 0.706
PROD_MID5 = 0.950
PROD_CAP = 0.954


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


def refine_exposure(lat, lon, old_profile):
    """Refine an existing 3-ring profile by adding 0.25/0.5km checks
    for directions that showed land at 1km."""
    refined = list(old_profile)
    for i in range(16):
        if old_profile[i] != 1.0:
            continue
        bearing = i * 22.5
        for ring_km in [0.25, 0.5]:
            s_lat, s_lon = offset_point(lat, lon, bearing, ring_km)
            result = is_water(s_lat, s_lon)
            if result is False:
                refined[i] = ring_km
                break
    return refined


# ---------------------------------------------------------------------------
# Attenuation factor functions
# ---------------------------------------------------------------------------

def land_dist_to_factor_prod(dist_km):
    """Current production attenuation curve."""
    if dist_km < 0: return 1.0
    if dist_km <= 1.0: return PROD_FLOOR
    if dist_km <= 2.0: return PROD_FLOOR + (PROD_MID2 - PROD_FLOOR) * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0: return PROD_MID2 + (PROD_MID5 - PROD_MID2) * ((dist_km - 2.0) / 3.0)
    return PROD_CAP


def land_dist_to_factor_v2(dist_km):
    """V2 — same curve as production (finer grid reverted: 0.25km picks up coastline)."""
    if dist_km < 0: return 1.0
    if dist_km <= 1.0: return PROD_FLOOR
    if dist_km <= 2.0: return PROD_FLOOR + (PROD_MID2 - PROD_FLOOR) * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0: return PROD_MID2 + (PROD_MID5 - PROD_MID2) * ((dist_km - 2.0) / 3.0)
    return PROD_CAP


# ---------------------------------------------------------------------------
# Core attenuation
# ---------------------------------------------------------------------------

def attenuate(height_ft, direction_deg, land_distances, factor_fn):
    """Original 2-bin linear interpolation (used for production)."""
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


def attenuate_windowed(height_ft, direction_deg, land_distances, factor_fn):
    """Directional-spread attenuation: Gaussian-weighted across ±67.5° (±3 bins).
    Captures how wide the open-water window is, not just the direct bearing."""
    n = len(land_distances)
    if n == 0 or all(d < 0 for d in land_distances):
        return height_ft, 1.0
    step = 360.0 / n
    norm_dir = ((direction_deg % 360) + 360) % 360
    center_idx = norm_dir / step
    total_weight = 0.0
    weighted_factor = 0.0
    sigma = 30.0
    for offset in range(-3, 4):
        idx_exact = center_idx + offset
        lower = int(idx_exact) % n
        upper = (lower + 1) % n
        frac = idx_exact - math.floor(idx_exact)
        f = factor_fn(land_distances[lower]) * (1.0 - frac) + \
            factor_fn(land_distances[upper]) * frac
        angle_off = abs(offset) * step
        w = math.exp(-(angle_off ** 2) / (2 * sigma ** 2))
        weighted_factor += f * w
        total_weight += w
    factor = weighted_factor / total_weight if total_weight > 0 else 1.0
    return height_ft * factor, factor


def angle_diff(a, b):
    """Signed angle difference in [-180, 180]."""
    d = ((a - b) + 180) % 360 - 180
    return d


def wind_sea_contribution(total_m, swell_m, wind_speed_kmh, wind_dir_deg, swell_dir_deg):
    """Compute additive wind-sea height in meters.
    Onshore wind (blowing in same direction as swell) adds energy.
    Offshore wind (opposing swell) slightly dampens surface chop."""
    if total_m <= swell_m or swell_m <= 0:
        return 0.0
    wind_sea_m = math.sqrt(max(0, total_m**2 - swell_m**2))
    if wind_sea_m < 0.05 or wind_speed_kmh < 5:
        return 0.0

    # Wind comes FROM wind_dir_deg. Swell travels TOWARD swell_dir_deg.
    # "Onshore" means wind blows in same direction swell is traveling.
    alignment = math.cos(math.radians(angle_diff(wind_dir_deg, swell_dir_deg)))
    # alignment ≈ +1 → same direction (onshore), ≈ -1 → opposing (offshore)

    if alignment > 0:
        # Onshore: add 30% of wind-sea (choppy but adds height)
        return wind_sea_m * 0.30 * alignment
    else:
        # Offshore: wind-sea doesn't reach shore, slight chop reduction
        return 0.0


def shoaling_factor(period_s, depth_m=5.0):
    """Approximate wave height increase from shoaling as waves enter shallow water.
    Waves slow down and grow taller. Effect is stronger for longer-period waves
    at shallower depths."""
    if period_s <= 0:
        return 1.0
    L0 = 1.56 * period_s ** 2  # deep water wavelength (m)
    rel_depth = depth_m / L0
    if rel_depth > 0.5:
        return 1.0
    # Linear ramp: 1.0 at rel_depth=0.5, up to cap at very shallow
    Ks = 1.0 + 0.25 * max(0, 0.5 - rel_depth)
    return min(Ks, 1.20)  # cap at 20% boost


def period_multiplier(period_s):
    """Scale attenuation by swell period: short-period (5s) blocked more,
    long-period (15s) refracts around land → less blocked."""
    return max(0.85, min(1.15, 0.85 + (period_s - 5.0) * 0.03))


def range_error(shaka_h, sl_min, sl_max):
    if sl_min <= shaka_h <= sl_max:
        return 0.0
    return shaka_h - sl_min if shaka_h < sl_min else shaka_h - sl_max


# ---------------------------------------------------------------------------
# Open-Meteo fetch — now includes swell-only fields
# ---------------------------------------------------------------------------

def fetch_openmeteo(lat, lon, target_ts):
    result = {}

    # Marine API: waves + swell
    marine_params = {
        "latitude": lat, "longitude": lon,
        "hourly": (
            "wave_height,wave_period,wave_direction,"
            "swell_wave_height,swell_wave_period,swell_wave_direction,"
            "secondary_swell_wave_height,secondary_swell_wave_period,secondary_swell_wave_direction"
        ),
        "forecast_days": 1, "timeformat": "unixtime",
    }
    try:
        r = requests.get("https://marine-api.open-meteo.com/v1/marine",
                         params=marine_params, timeout=15)
        hourly = r.json().get("hourly", {})
        times = hourly.get("time", [])
        if not times:
            return None
        best_idx = min(range(len(times)), key=lambda j: abs(times[j] - target_ts))

        def val(field):
            return hourly.get(field, [None])[best_idx] or 0

        result.update({
            "wave_height_m": val("wave_height"),
            "wave_direction_deg": val("wave_direction"),
            "wave_period_s": val("wave_period"),
            "swell_height_m": val("swell_wave_height"),
            "swell_direction_deg": val("swell_wave_direction"),
            "swell_period_s": val("swell_wave_period"),
            "secondary_swell_height_m": val("secondary_swell_wave_height"),
            "secondary_swell_direction_deg": val("secondary_swell_wave_direction"),
            "secondary_swell_period_s": val("secondary_swell_wave_period"),
        })
    except:
        return None

    # Weather API: wind
    weather_params = {
        "latitude": lat, "longitude": lon,
        "hourly": "windspeed_10m,winddirection_10m",
        "forecast_days": 1, "timeformat": "unixtime",
    }
    try:
        r = requests.get("https://api.open-meteo.com/v1/forecast",
                         params=weather_params, timeout=15)
        hourly = r.json().get("hourly", {})
        times = hourly.get("time", [])
        if times:
            best_idx = min(range(len(times)), key=lambda j: abs(times[j] - target_ts))
            result["wind_speed_kmh"] = hourly.get("windspeed_10m", [None])[best_idx] or 0
            result["wind_direction_deg"] = hourly.get("winddirection_10m", [None])[best_idx] or 0
    except:
        pass

    result.setdefault("wind_speed_kmh", 0)
    result.setdefault("wind_direction_deg", 0)
    return result


# ---------------------------------------------------------------------------
# Region runner
# ---------------------------------------------------------------------------

def run_region(region_name, spots_filter, all_spots, om_cache, exp_cache, exp_v2_cache):
    now_utc = int(datetime.now(timezone.utc).timestamp())

    filtered = [s for s in all_spots if spots_filter(s)]
    filtered.sort(key=lambda x: x.get("lon", 0))

    print(f"\n{'=' * 120}")
    print(f"  {region_name}: {len(filtered)} spots")
    print(f"{'=' * 120}")

    needs_om = [s for s in filtered if f"{s['lat']:.4f},{s['lon']:.4f}" not in om_cache]
    needs_exp = [s for s in filtered if f"{s['lat']:.4f},{s['lon']:.4f}" not in exp_cache]

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
        with open(OPENMETEO_V2_CACHE, "w") as f:
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

    # Build V2 exposure: refine existing profiles with 0.25/0.5km inner rings
    needs_refine = []
    for s in filtered:
        key = f"{s['lat']:.4f},{s['lon']:.4f}"
        if key in exp_v2_cache:
            continue
        old = exp_cache.get(key)
        if old and any(d == 1.0 for d in old):
            needs_refine.append(s)
        elif old:
            exp_v2_cache[key] = old
    if needs_refine:
        print(f"  Refining exposure for {len(needs_refine)} spots (0.25/0.5km inner rings)...")
        def refine_worker(sp):
            k = f"{sp['lat']:.4f},{sp['lon']:.4f}"
            return k, refine_exposure(sp["lat"], sp["lon"], exp_cache[k])
        done_r = 0
        with ThreadPoolExecutor(max_workers=8) as pool:
            futs = {pool.submit(refine_worker, sp): sp for sp in needs_refine}
            for fut in as_completed(futs):
                k, profile = fut.result()
                exp_v2_cache[k] = profile
                done_r += 1
                if done_r % 10 == 0 or done_r == len(needs_refine):
                    print(f"    refine: {done_r}/{len(needs_refine)}")
        with open(EXPOSURE_V2_CACHE, "w") as f:
            json.dump(exp_v2_cache, f)

    header = (f"  {'Spot':28s} {'SL Range':>10s} {'TotalRaw':>9s} {'SwellRaw':>9s} "
              f"{'Prod':>7s} {'PErr':>7s} {'V2':>7s} {'V2Err':>7s} {'Delta':>7s}")
    print(header)
    print(f"  {'-'*28} {'-'*10} {'-'*9} {'-'*9} {'-'*7} {'-'*7} {'-'*7} {'-'*7} {'-'*7}")

    results = []
    for s in filtered:
        key = f"{s['lat']:.4f},{s['lon']:.4f}"
        om = om_cache.get(key)
        exp = exp_cache.get(key)
        exp_v2 = exp_v2_cache.get(key, exp)
        if not om or not exp:
            continue

        fc = s.get("forecast", [])
        best = min(fc, key=lambda e: abs(e.get("timestamp", 0) - now_utc)) if fc else None
        if not best:
            continue
        sl_min, sl_max = float(best["wave_min_ft"]), float(best["wave_max_ft"])
        if sl_min <= 0 and sl_max <= 0:
            continue

        total_raw_ft = (om.get("wave_height_m", 0) or 0) * METERS_TO_FEET
        total_dir = om.get("wave_direction_deg", 0) or 0

        swell_raw_m = om.get("swell_height_m", 0) or 0
        swell_raw_ft = swell_raw_m * METERS_TO_FEET
        swell_dir = om.get("swell_direction_deg", 0) or 0
        swell_period = om.get("swell_period_s", 0) or 0
        total_raw_m = om.get("wave_height_m", 0) or 0
        wind_speed = om.get("wind_speed_kmh", 0) or 0
        wind_dir = om.get("wind_direction_deg", 0) or 0

        # --- Current production: uses total wave_height ---
        prod_h, prod_f = attenuate(total_raw_ft, total_dir, exp, land_dist_to_factor_prod)
        prod_h_scaled = prod_h * PROD_SCALE

        # --- V2: swell-only + period modifier + secondary RMS + wind-sea ---
        # Primary swell
        v2_h, v2_f = attenuate(swell_raw_ft, swell_dir, exp, land_dist_to_factor_v2)
        pm = period_multiplier(swell_period)
        effective_f = min(1.0, v2_f * pm)
        v2_primary = swell_raw_ft * effective_f

        # Secondary swell (attenuated independently)
        sec_h_m = om.get("secondary_swell_height_m", 0) or 0
        sec_dir = om.get("secondary_swell_direction_deg", 0) or 0
        sec_period = om.get("secondary_swell_period_s", 0) or 0
        v2_secondary = 0.0
        if sec_h_m > 0.05:
            sec_h_ft = sec_h_m * METERS_TO_FEET
            sec_atten, sec_f = attenuate(sec_h_ft, sec_dir, exp, land_dist_to_factor_v2)
            sec_pm = period_multiplier(sec_period)
            sec_eff_f = min(1.0, sec_f * sec_pm)
            v2_secondary = sec_h_ft * sec_eff_f

        # RMS combine independent wave trains
        v2_h = math.sqrt(v2_primary ** 2 + v2_secondary ** 2)

        # Wind-sea contribution
        wind_add_m = wind_sea_contribution(total_raw_m, swell_raw_m, wind_speed, wind_dir, swell_dir)
        v2_h += wind_add_m * METERS_TO_FEET

        v2_h_scaled = v2_h * PROD_SCALE

        prod_err = range_error(prod_h_scaled, sl_min, sl_max)
        v2_err = range_error(v2_h_scaled, sl_min, sl_max)
        delta = abs(prod_err) - abs(v2_err)

        sl_str = f"{sl_min:.0f}-{sl_max:.0f}ft"
        arrow = "+" if delta > 0.1 else ("-" if delta < -0.1 else "=")

        print(f"  {s['name']:28s} {sl_str:>10s} {total_raw_ft:7.1f}ft {swell_raw_ft:7.1f}ft "
              f"{prod_h_scaled:6.1f}ft {prod_err:+6.1f}f "
              f"{v2_h_scaled:6.1f}ft {v2_err:+6.1f}f "
              f"{arrow}{delta:+5.1f}ft")

        results.append({
            "name": s["name"], "sl_min": sl_min, "sl_max": sl_max,
            "total_raw_ft": total_raw_ft, "swell_raw_ft": swell_raw_ft,
            "swell_period": swell_period,
            "prod_h": prod_h_scaled, "prod_err": prod_err,
            "v2_h": v2_h_scaled, "v2_err": v2_err, "delta": delta,
        })

    if results:
        prod_mae = np.mean([abs(r["prod_err"]) for r in results])
        v2_mae = np.mean([abs(r["v2_err"]) for r in results])
        prod_in = sum(1 for r in results if r["prod_err"] == 0)
        v2_in = sum(1 for r in results if r["v2_err"] == 0)
        improved = sum(1 for r in results if r["delta"] > 0.1)
        regressed = sum(1 for r in results if r["delta"] < -0.1)
        print(f"\n  SUMMARY: {len(results)} spots")
        print(f"    Production  MAE={prod_mae:.2f}ft  InRange={prod_in}/{len(results)}")
        print(f"    V2 (swell)  MAE={v2_mae:.2f}ft  InRange={v2_in}/{len(results)}")
        print(f"    Improved: {improved}  Regressed: {regressed}  Unchanged: {len(results)-improved-regressed}")

    return results


def main():
    print("=" * 120)
    print("SWELL MODEL V2 BENCHMARK")
    print("Changes #1,2,4,7: swell + period atten + wind-sea + secondary RMS")
    print("TEST ENVIRONMENT ONLY")
    print("=" * 120)

    with open(SURFLINE_CACHE) as f:
        all_data = json.load(f)
    all_spots = all_data["spots"]

    om_cache = {}
    if OPENMETEO_V2_CACHE.exists():
        with open(OPENMETEO_V2_CACHE) as f:
            om_cache = json.load(f)

    exp_cache = {}
    if EXPOSURE_CACHE.exists():
        with open(EXPOSURE_CACHE) as f:
            exp_cache = json.load(f)

    exp_v2_cache = {}
    if EXPOSURE_V2_CACHE.exists():
        with open(EXPOSURE_V2_CACHE) as f:
            exp_v2_cache = json.load(f)

    sc_filter = lambda s: 36.7 < s.get("lat", 0) < 37.2 and -122.3 < s.get("lon", 0) < -121.8
    oahu_filter = lambda s: 21.2 < s.get("lat", 0) < 21.75 and -158.4 < s.get("lon", 0) < -157.6
    maui_filter = lambda s: 20.6 < s.get("lat", 0) < 21.15 and -156.8 < s.get("lon", 0) < -155.9

    sc_results = run_region("SANTA CRUZ", sc_filter, all_spots, om_cache, exp_cache, exp_v2_cache)
    oahu_results = run_region("O'AHU", oahu_filter, all_spots, om_cache, exp_cache, exp_v2_cache)
    maui_results = run_region("MAUI", maui_filter, all_spots, om_cache, exp_cache, exp_v2_cache)

    all_results = sc_results + oahu_results + maui_results
    if all_results:
        print(f"\n{'=' * 120}")
        print(f"OVERALL: {len(all_results)} spots across 3 regions")
        print(f"{'=' * 120}")
        prod_mae = np.mean([abs(r["prod_err"]) for r in all_results])
        v2_mae = np.mean([abs(r["v2_err"]) for r in all_results])
        prod_in = sum(1 for r in all_results if r["prod_err"] == 0)
        v2_in = sum(1 for r in all_results if r["v2_err"] == 0)
        improved = sum(1 for r in all_results if r["delta"] > 0.1)
        regressed = sum(1 for r in all_results if r["delta"] < -0.1)
        print(f"  Production  MAE={prod_mae:.2f}ft  InRange={prod_in}/{len(all_results)}")
        print(f"  V2 (swell)  MAE={v2_mae:.2f}ft  InRange={v2_in}/{len(all_results)}")
        print(f"  Improved: {improved}  Regressed: {regressed}  Unchanged: {len(all_results)-improved-regressed}")

        avg_total = np.mean([r["total_raw_ft"] for r in all_results])
        avg_swell = np.mean([r["swell_raw_ft"] for r in all_results])
        print(f"\n  Avg raw total: {avg_total:.2f}ft  Avg raw swell: {avg_swell:.2f}ft  Diff: {avg_total - avg_swell:.2f}ft")


if __name__ == "__main__":
    main()
