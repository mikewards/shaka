#!/usr/bin/env python3
"""
Surfline vs Shaka Swell Comparison Benchmark

Compares Shaka's attenuated swell model against Surfline forecasts
for a curated roster of spots. Produces a detailed report with
regional breakdowns and threshold checks.

Usage:
  python surfline_benchmark.py                                     # use defaults
  python surfline_benchmark.py --roster data/benchmark_roster.json # explicit roster
"""

import argparse
import json
import math
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import requests

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

SURFLINE_CACHE = DATA_DIR / "surfline_snapshot.json"
OPENMETEO_CACHE = DATA_DIR / "openmeteo_snapshot.json"
EXPOSURE_CACHE = DATA_DIR / "exposure_cache.json"
ROSTER_FILE = DATA_DIR / "benchmark_roster.json"
RESULTS_CSV = DATA_DIR / "benchmark_results.csv"
SUMMARY_FILE = DATA_DIR / "benchmark_summary.txt"

METERS_TO_FEET = 3.28084

# ---------------------------------------------------------------------------
# Surfline data loading
# ---------------------------------------------------------------------------

def load_surfline_data():
    """Load Surfline forecasts from the scraper snapshot."""
    if not SURFLINE_CACHE.exists():
        print("[Surfline] ERROR: No snapshot found. Run surfline_scraper.py first.")
        sys.exit(1)
    print(f"[Surfline] Using cached data from {SURFLINE_CACHE}")
    with open(SURFLINE_CACHE) as f:
        return json.load(f)


def build_benchmark_spots(surfline_data, roster_path=None):
    """Match Surfline forecasts to roster spots, pick closest-to-now entry."""
    raw_spots = surfline_data.get("spots", [])
    if not raw_spots:
        print("[Select] ERROR: No spots in Surfline data")
        sys.exit(1)

    # Build lookup by spot_id
    by_id = {}
    for s in raw_spots:
        sid = s.get("spot_id", s.get("spot", {}).get("id", ""))
        if sid:
            by_id[sid] = s

    # Load roster
    rpath = Path(roster_path) if roster_path else ROSTER_FILE
    if not rpath.is_absolute():
        rpath = Path(__file__).parent / roster_path if roster_path else ROSTER_FILE
    if not rpath.exists():
        print(f"[Select] ERROR: Roster file not found: {rpath}")
        sys.exit(1)

    with open(rpath) as f:
        roster = json.load(f)
    print(f"[Select] Roster: {len(roster)} spots from {rpath.name}")

    now_utc = int(datetime.now(timezone.utc).timestamp())
    valid = []
    missing = 0

    for r in roster:
        sid = r["spot_id"]
        s = by_id.get(sid)
        if not s:
            missing += 1
            continue

        forecast = s.get("forecast", [])
        if not forecast:
            missing += 1
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
            missing += 1
            continue

        sl_min = best.get("wave_min_ft")
        sl_max = best.get("wave_max_ft")
        if sl_min is None or sl_max is None:
            missing += 1
            continue
        sl_min, sl_max = float(sl_min), float(sl_max)
        if sl_min <= 0 and sl_max <= 0:
            missing += 1
            continue

        valid.append({
            "name": r["name"],
            "region": r["region"],
            "lat": float(r["lat"]),
            "lon": float(r["lon"]),
            "surfline_min": sl_min,
            "surfline_max": sl_max,
            "surfline_mid": (sl_min + sl_max) / 2.0,
            "surfline_timestamp": best.get("timestamp", now_utc),
            "surfline_swell_height": best.get("swell_height_ft"),
            "surfline_swell_period": best.get("swell_period_s"),
            "surfline_swell_direction": best.get("swell_direction_deg"),
            "spot_id": sid,
        })

    holdout_count = max(1, len(valid) * 30 // 100)
    for i, sp in enumerate(valid):
        sp["is_holdout"] = i < holdout_count

    train = sum(1 for s in valid if not s["is_holdout"])
    holdout = sum(1 for s in valid if s["is_holdout"])
    print(f"[Select] Matched {len(valid)} spots ({missing} missing/invalid)")
    print(f"[Select] Split: {train} train, {holdout} holdout")

    return valid


# ---------------------------------------------------------------------------
# Open-Meteo raw swell (parallel)
# ---------------------------------------------------------------------------

def _fetch_one_openmeteo(sp):
    """Fetch Open-Meteo data for a single spot. Returns (key, result_or_None)."""
    key = f"{sp['lat']:.4f},{sp['lon']:.4f}"
    params = {
        "latitude": sp["lat"],
        "longitude": sp["lon"],
        "hourly": "wave_height,wave_period,wave_direction,"
                  "swell_wave_height,swell_wave_period,swell_wave_direction",
        "forecast_days": 1,
        "timeformat": "unixtime",
    }

    now_utc = int(datetime.now(timezone.utc).timestamp())
    target_ts = sp.get("surfline_timestamp", now_utc) or now_utc

    for attempt in range(2):
        try:
            r = requests.get("https://marine-api.open-meteo.com/v1/marine",
                             params=params, timeout=5)
            r.raise_for_status()
            data = r.json()
            hourly = data.get("hourly", {})

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

            return key, {
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
            if attempt == 0:
                time.sleep(1)
            else:
                return key, None, str(e)

    return key, None, "max retries"


def fetch_openmeteo_swell(spots):
    """Fetch raw swell data from Open-Meteo for each spot using parallel workers."""
    results = {}
    total = len(spots)
    ok = 0
    fail = 0
    errors = []

    # Deduplicate by coordinate key
    seen_keys = set()
    unique_spots = []
    for sp in spots:
        key = f"{sp['lat']:.4f},{sp['lon']:.4f}"
        if key not in seen_keys:
            seen_keys.add(key)
            unique_spots.append(sp)

    print(f"[OpenMeteo] Fetching {len(unique_spots)} unique locations (10 workers, 5s timeout)...")

    with ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(_fetch_one_openmeteo, sp): sp for sp in unique_spots}
        for future in as_completed(futures):
            result = future.result()
            key = result[0]
            if len(result) == 2:
                results[key] = result[1]
                ok += 1
            else:
                results[key] = None
                fail += 1
                errors.append(f"{futures[future]['name']}: {result[2]}")

            done = ok + fail
            if done % 50 == 0 or done == len(unique_spots):
                print(f"  [{done}/{len(unique_spots)}] ok={ok} fail={fail}")

    if errors:
        print(f"[OpenMeteo] {len(errors)} failures:")
        for e in errors[:5]:
            print(f"  WARNING: {e}")
        if len(errors) > 5:
            print(f"  ... and {len(errors) - 5} more")

    with open(OPENMETEO_CACHE, "w") as f:
        json.dump(results, f)
    print(f"[OpenMeteo] Done: {ok} ok, {fail} failed")

    return results


# ---------------------------------------------------------------------------
# Exposure profiles (pre-computed, cache only)
# ---------------------------------------------------------------------------

def load_exposure_profiles(spots):
    """Load pre-computed exposure profiles from cache. No live API calls."""
    if not EXPOSURE_CACHE.exists():
        print("[Exposure] ERROR: No exposure cache found. Pre-compute locally first.")
        sys.exit(1)

    with open(EXPOSURE_CACHE) as f:
        cache = json.load(f)

    missing = []
    for sp in spots:
        key = f"{sp['lat']:.4f},{sp['lon']:.4f}"
        if key not in cache:
            missing.append(sp["name"])

    if missing:
        print(f"[Exposure] WARNING: {len(missing)} spots missing from cache")
        if len(missing) <= 10:
            for name in missing:
                print(f"  - {name}")
    else:
        print(f"[Exposure] All {len(spots)} spots found in cache ({len(cache)} total profiles)")

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


def _print_metrics(out, subset, label):
    """Print standard metrics for a subset of results."""
    if not subset:
        return
    out(f"\n--- {label} ({len(subset)} spots) ---")

    range_errors = [r["error_vs_range"] for r in subset]
    abs_range_errors = [r["abs_error_range"] for r in subset]

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


def print_summary(results):
    """Print and save analysis summary."""
    lines = []
    def out(s=""):
        lines.append(s)
        print(s)

    out("=" * 70)
    out("SURFLINE vs SHAKA SWELL BENCHMARK")
    out(f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
    out("=" * 70)

    train = [r for r in results if not r["is_holdout"]]
    holdout = [r for r in results if r["is_holdout"]]

    out(f"\nTotal spots analyzed: {len(results)}")
    out(f"  Training set: {len(train)}")
    out(f"  Holdout set:  {len(holdout)}")

    _print_metrics(out, results, "ALL SPOTS")
    _print_metrics(out, train, "TRAINING SET")
    _print_metrics(out, holdout, "HOLDOUT SET")

    # Breakdown by region
    out("\n--- ERROR BY REGION ---")
    regions = sorted(set(r["region"] for r in results))
    for region in regions:
        sub = [r for r in results if r["region"] == region]
        if not sub:
            continue
        mae = np.mean([r["abs_error_range"] for r in sub])
        bias = np.mean([r["error_vs_range"] for r in sub])
        in_range = sum(1 for r in sub if r["error_vs_range"] == 0)
        pct = in_range / len(sub) * 100
        out(f"  {region:<20s}: n={len(sub):3d}  MAE={mae:.2f}ft  Bias={bias:+.2f}ft  InRange={pct:.0f}%")

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
    out(f"  {'Spot':<30s} {'Region':<15s} {'SL Range':>10s} {'Shaka':>7s} {'Raw':>7s} {'Err':>7s} {'Factor':>7s} {'Type'}")
    out(f"  {'-'*30} {'-'*15} {'-'*10} {'-'*7} {'-'*7} {'-'*7} {'-'*7} {'-'*15}")
    for r in sorted_by_err[:15]:
        sl = f"{r['surfline_min']:.0f}-{r['surfline_max']:.0f}ft"
        out(f"  {r['name']:<30s} {r['region']:<15s} {sl:>10s} {r['shaka_corrected_ft']:>6.1f}f {r['openmeteo_raw_ft']:>6.1f}f {r['error_vs_range']:>+6.1f}f {r['attenuation_factor']:>6.2f} {r['exposure_type']}")

    # Best matches
    out("\n--- TOP 10 BEST MATCHES (within Surfline range) ---")
    in_range_spots = [r for r in results if r["error_vs_range"] == 0]
    in_range_spots.sort(key=lambda r: r["surfline_mid"], reverse=True)
    out(f"  {'Spot':<30s} {'Region':<15s} {'SL Range':>10s} {'Shaka':>7s} {'Factor':>7s} {'Type'}")
    for r in in_range_spots[:10]:
        sl = f"{r['surfline_min']:.0f}-{r['surfline_max']:.0f}ft"
        out(f"  {r['name']:<30s} {r['region']:<15s} {sl:>10s} {r['shaka_corrected_ft']:>6.1f}f {r['attenuation_factor']:>6.2f} {r['exposure_type']}")

    out("\n" + "=" * 70)
    out("END OF BENCHMARK REPORT")
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
    parser = argparse.ArgumentParser(description="Surfline vs Shaka benchmark")
    parser.add_argument("--roster", type=str, default=None,
                        help="Path to benchmark roster JSON")
    args = parser.parse_args()

    print("\n" + "=" * 60)
    print("SURFLINE vs SHAKA SWELL BENCHMARK")
    print("=" * 60)

    surfline = load_surfline_data()
    spots = build_benchmark_spots(surfline, roster_path=args.roster)
    openmeteo = fetch_openmeteo_swell(spots)
    exposure = load_exposure_profiles(spots)

    print("\n[Compare] Running comparison...")
    results = run_comparison(spots, openmeteo, exposure)
    print(f"[Compare] {len(results)} spots compared successfully")

    write_csv(results)
    print()
    print_summary(results)

    passed, _ = check_thresholds(results)
    if not passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
