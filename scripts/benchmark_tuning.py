#!/usr/bin/env python3
"""
Phase B: Attenuation Model Tuning (TEST ENVIRONMENT ONLY)

Tests parameter changes against the Surfline benchmark data.
Does NOT modify any production Kotlin code.

Approach: test each change independently, then combine the best.
"""

import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from scipy.optimize import minimize_scalar, minimize

DATA_DIR = Path(__file__).parent / "data"
SURFLINE_CACHE = DATA_DIR / "surfline_snapshot.json"
OPENMETEO_CACHE = DATA_DIR / "openmeteo_snapshot.json"
EXPOSURE_CACHE = DATA_DIR / "exposure_cache.json"

METERS_TO_FEET = 3.28084
OPEN = -1.0


# ── Load benchmark data ─────────────────────────────────────────────────

def load_benchmark_spots(max_spots=200, seed=42):
    """Load and prepare the same spots used in Phase A."""
    import random

    with open(SURFLINE_CACHE) as f:
        surfline = json.load(f)
    with open(OPENMETEO_CACHE) as f:
        openmeteo = json.load(f)
    with open(EXPOSURE_CACHE) as f:
        exposure = json.load(f)

    now_utc = int(datetime.now(timezone.utc).timestamp())
    raw_spots = surfline.get("spots", [])
    valid = []

    for s in raw_spots:
        lat = s.get("lat")
        lon = s.get("lon")
        if lat is None or lon is None:
            continue

        forecast = s.get("forecast", [])
        if not forecast:
            continue

        best = min(forecast, key=lambda e: abs(e.get("timestamp", 0) - now_utc))
        sl_min = best.get("wave_min_ft")
        sl_max = best.get("wave_max_ft")
        if sl_min is None or sl_max is None:
            continue
        sl_min, sl_max = float(sl_min), float(sl_max)
        if sl_min <= 0 and sl_max <= 0:
            continue

        key = f"{lat:.4f},{lon:.4f}"
        om = openmeteo.get(key)
        exp = exposure.get(key)
        if om is None or exp is None:
            continue

        raw_wave_ft = (om.get("wave_height_m", 0) or 0) * METERS_TO_FEET
        wave_dir = om.get("wave_direction_deg", 0) or 0

        valid.append({
            "name": s.get("name", ""),
            "region": s.get("region", ""),
            "lat": float(lat),
            "lon": float(lon),
            "sl_min": sl_min,
            "sl_max": sl_max,
            "sl_mid": (sl_min + sl_max) / 2.0,
            "raw_ft": raw_wave_ft,
            "wave_dir": wave_dir,
            "exposure": exp,
        })

    rng = random.Random(seed)
    rng.shuffle(valid)
    if len(valid) > max_spots:
        valid = valid[:max_spots]

    holdout_count = max(1, len(valid) * 30 // 100)
    train = valid[holdout_count:]
    holdout = valid[:holdout_count]

    return train, holdout


# ── Model variants ───────────────────────────────────────────────────────

def land_dist_to_factor_v0(dist_km):
    """CURRENT PRODUCTION model (baseline)."""
    if dist_km < 0:
        return 1.0
    if dist_km <= 1.0:
        return 0.15
    if dist_km <= 2.0:
        return 0.15 + 0.30 * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0:
        return 0.45 + 0.40 * ((dist_km - 2.0) / 3.0)
    return 0.85


def make_land_dist_to_factor(floor, mid2, mid5, cap):
    """Parameterized version for optimization."""
    def fn(dist_km):
        if dist_km < 0:
            return 1.0
        if dist_km <= 1.0:
            return floor
        if dist_km <= 2.0:
            return floor + (mid2 - floor) * ((dist_km - 1.0) / 1.0)
        if dist_km <= 5.0:
            return mid2 + (mid5 - mid2) * ((dist_km - 2.0) / 3.0)
        return cap
    return fn


def attenuate(height_ft, direction_deg, land_distances, factor_fn, n_dirs=16):
    """Generic attenuate with configurable factor function and direction count."""
    if len(land_distances) != n_dirs:
        return height_ft, 1.0
    if all(d < 0 for d in land_distances):
        return height_ft, 1.0

    step = 360.0 / n_dirs
    norm_dir = ((direction_deg % 360) + 360) % 360
    exact_idx = norm_dir / step
    lower_idx = int(exact_idx) % n_dirs
    upper_idx = (lower_idx + 1) % n_dirs
    frac = exact_idx - int(exact_idx)

    lower_factor = factor_fn(land_distances[lower_idx])
    upper_factor = factor_fn(land_distances[upper_idx])
    factor = lower_factor * (1.0 - frac) + upper_factor * frac

    return height_ft * factor, factor


def evaluate_model(spots, factor_fn, surf_scale=1.0, n_dirs=16):
    """Run model on spots, return error metrics."""
    errors_range = []
    abs_errors = []
    mid_errors = []

    for sp in spots:
        corrected, atten = attenuate(sp["raw_ft"], sp["wave_dir"], sp["exposure"], factor_fn, n_dirs)
        shaka = corrected * surf_scale

        sl_min, sl_max = sp["sl_min"], sp["sl_max"]
        if sl_min <= shaka <= sl_max:
            err = 0.0
        elif shaka < sl_min:
            err = shaka - sl_min
        else:
            err = shaka - sl_max

        errors_range.append(err)
        abs_errors.append(abs(err))
        mid_errors.append(shaka - sp["sl_mid"])

    arr_range = np.array(errors_range)
    arr_abs = np.array(abs_errors)
    arr_mid = np.array(mid_errors)
    mean_sl = np.mean([s["sl_mid"] for s in spots])

    return {
        "mae": float(np.mean(arr_abs)),
        "rmse": float(np.sqrt(np.mean(arr_range ** 2))),
        "bias": float(np.mean(arr_range)),
        "in_range_pct": float(np.sum(arr_abs == 0) / len(spots) * 100),
        "mean_shaka": float(np.mean([
            attenuate(s["raw_ft"], s["wave_dir"], s["exposure"], factor_fn, n_dirs)[0] * surf_scale
            for s in spots
        ])),
        "mean_sl": float(mean_sl),
    }


def print_metrics(label, m):
    print(f"  {label:45s}  MAE={m['mae']:.2f}  RMSE={m['rmse']:.2f}  "
          f"Bias={m['bias']:+.2f}  InRange={m['in_range_pct']:.0f}%  "
          f"Shaka={m['mean_shaka']:.1f}ft  SL={m['mean_sl']:.1f}ft")


# ── Main tuning ──────────────────────────────────────────────────────────

def main():
    print("=" * 80)
    print("PHASE B: MODEL TUNING (test environment only)")
    print("=" * 80)

    train, holdout = load_benchmark_spots()
    print(f"\nLoaded {len(train)} training + {len(holdout)} holdout spots")

    # ── Test 0: Baseline (current production) ────────────────────────────
    print("\n" + "─" * 80)
    print("TEST 0: BASELINE (current production model)")
    print("─" * 80)
    m0_train = evaluate_model(train, land_dist_to_factor_v0)
    m0_hold = evaluate_model(holdout, land_dist_to_factor_v0)
    print_metrics("Baseline [TRAIN]", m0_train)
    print_metrics("Baseline [HOLDOUT]", m0_hold)

    # ── Test 1: Swell-to-surf scaling factor ─────────────────────────────
    print("\n" + "─" * 80)
    print("TEST 1: SWELL-TO-SURF SCALING (offshore → nearshore conversion)")
    print("─" * 80)

    best_scale = None
    best_mae = float("inf")
    for scale in np.arange(0.50, 1.01, 0.025):
        m = evaluate_model(train, land_dist_to_factor_v0, surf_scale=scale)
        if m["mae"] < best_mae:
            best_mae = m["mae"]
            best_scale = scale
        if scale in [0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.0]:
            print_metrics(f"scale={scale:.2f}", m)

    print(f"\n  >>> Best surf_scale = {best_scale:.3f} (MAE={best_mae:.3f} on train)")
    m1_hold = evaluate_model(holdout, land_dist_to_factor_v0, surf_scale=best_scale)
    print_metrics(f"scale={best_scale:.3f} [HOLDOUT]", m1_hold)

    # ── Test 2: Raise attenuation floor ──────────────────────────────────
    print("\n" + "─" * 80)
    print("TEST 2: RAISE ATTENUATION FLOOR (landDistToFactor)")
    print("─" * 80)

    best_floor = None
    best_mae2 = float("inf")
    for floor in np.arange(0.10, 0.60, 0.05):
        fn = make_land_dist_to_factor(floor, max(floor + 0.15, 0.45), 0.85, 0.90)
        m = evaluate_model(train, fn)
        if m["mae"] < best_mae2:
            best_mae2 = m["mae"]
            best_floor = floor
        print_metrics(f"floor={floor:.2f}", m)

    print(f"\n  >>> Best floor = {best_floor:.2f} (MAE={best_mae2:.3f} on train)")
    fn_best_floor = make_land_dist_to_factor(best_floor, max(best_floor + 0.15, 0.45), 0.85, 0.90)
    m2_hold = evaluate_model(holdout, fn_best_floor)
    print_metrics(f"floor={best_floor:.2f} [HOLDOUT]", m2_hold)

    # ── Test 3: Combined scaling + floor ─────────────────────────────────
    print("\n" + "─" * 80)
    print("TEST 3: COMBINED (scaling + floor together)")
    print("─" * 80)

    def objective(params):
        scale, floor, mid2, mid5, cap = params
        if not (0.4 <= scale <= 1.0 and 0.1 <= floor <= 0.6 and
                floor <= mid2 <= 0.95 and mid2 <= mid5 <= 1.0 and
                mid5 <= cap <= 1.0):
            return 10.0
        fn = make_land_dist_to_factor(floor, mid2, mid5, cap)
        m = evaluate_model(train, fn, surf_scale=scale)
        return m["mae"]

    from scipy.optimize import differential_evolution
    bounds = [(0.50, 1.0), (0.15, 0.55), (0.30, 0.80), (0.60, 0.95), (0.75, 1.0)]
    result = differential_evolution(objective, bounds, seed=42, maxiter=200,
                                     tol=1e-4, popsize=20)

    opt_scale, opt_floor, opt_mid2, opt_mid5, opt_cap = result.x
    print(f"\n  Optimized parameters:")
    print(f"    surf_scale     = {opt_scale:.3f}")
    print(f"    floor (<=1km)  = {opt_floor:.3f}")
    print(f"    mid2  (<=2km)  = {opt_mid2:.3f}")
    print(f"    mid5  (<=5km)  = {opt_mid5:.3f}")
    print(f"    cap   (>5km)   = {opt_cap:.3f}")

    fn_opt = make_land_dist_to_factor(opt_floor, opt_mid2, opt_mid5, opt_cap)
    m3_train = evaluate_model(train, fn_opt, surf_scale=opt_scale)
    m3_hold = evaluate_model(holdout, fn_opt, surf_scale=opt_scale)
    print_metrics("Optimized [TRAIN]", m3_train)
    print_metrics("Optimized [HOLDOUT]", m3_hold)

    # ── Summary comparison ───────────────────────────────────────────────
    print("\n" + "=" * 80)
    print("SUMMARY: HOLDOUT SET COMPARISON")
    print("=" * 80)
    print_metrics("Baseline (production)", m0_hold)
    print_metrics(f"Surf scale only ({best_scale:.3f})", m1_hold)
    print_metrics(f"Floor only ({best_floor:.2f})", m2_hold)
    print_metrics(f"Combined optimized", m3_hold)

    # ── Santa Cruz deep-dive with optimized model ────────────────────────
    print("\n" + "=" * 80)
    print("SANTA CRUZ DEEP-DIVE: Baseline vs Optimized")
    print("=" * 80)

    with open(SURFLINE_CACHE) as f:
        all_data = json.load(f)
    with open(OPENMETEO_CACHE) as f:
        openmeteo = json.load(f)
    with open(EXPOSURE_CACHE) as f:
        exposure_cache = json.load(f)

    now_utc = int(datetime.now(timezone.utc).timestamp())
    sc_spots = []
    for s in all_data["spots"]:
        lat, lon = s.get("lat", 0), s.get("lon", 0)
        if not (36.7 < lat < 37.2 and -122.3 < lon < -121.8):
            continue
        fc = s.get("forecast", [])
        if not fc:
            continue
        best = min(fc, key=lambda e: abs(e.get("timestamp", 0) - now_utc))
        sl_min, sl_max = best.get("wave_min_ft"), best.get("wave_max_ft")
        if sl_min is None or sl_max is None:
            continue
        key = f"{lat:.4f},{lon:.4f}"
        om = openmeteo.get(key)
        exp = exposure_cache.get(key)
        if om is None or exp is None:
            continue
        raw_ft = (om.get("wave_height_m", 0) or 0) * METERS_TO_FEET
        wave_dir = om.get("wave_direction_deg", 0) or 0
        sc_spots.append({
            "name": s["name"], "lat": lat, "lon": lon,
            "sl_min": float(sl_min), "sl_max": float(sl_max),
            "sl_mid": (float(sl_min) + float(sl_max)) / 2.0,
            "raw_ft": raw_ft, "wave_dir": wave_dir, "exposure": exp,
        })

    if sc_spots:
        print(f"\n  {'Spot':25s} {'SL Range':>10s} {'Baseline':>10s} {'Optimized':>10s} {'Improvement':>12s}")
        print(f"  {'-'*25} {'-'*10} {'-'*10} {'-'*10} {'-'*12}")
        for sp in sorted(sc_spots, key=lambda x: x["lon"]):
            base_h, base_f = attenuate(sp["raw_ft"], sp["wave_dir"], sp["exposure"], land_dist_to_factor_v0)
            opt_h, opt_f = attenuate(sp["raw_ft"], sp["wave_dir"], sp["exposure"], fn_opt)
            opt_h *= opt_scale

            sl_range = f"{sp['sl_min']:.0f}-{sp['sl_max']:.0f}ft"

            def range_err(h):
                if sp["sl_min"] <= h <= sp["sl_max"]:
                    return 0.0
                return h - sp["sl_min"] if h < sp["sl_min"] else h - sp["sl_max"]

            base_err = range_err(base_h)
            opt_err = range_err(opt_h)
            improved = abs(base_err) - abs(opt_err)
            arrow = "+" if improved > 0.1 else ("−" if improved < -0.1 else "=")

            print(f"  {sp['name']:25s} {sl_range:>10s} {base_h:7.1f}ft  {opt_h:7.1f}ft   {arrow} {improved:+.1f}ft")

    # ── Print proposed Kotlin changes ────────────────────────────────────
    print("\n" + "=" * 80)
    print("PROPOSED KOTLIN CHANGES (for review, NOT applied)")
    print("=" * 80)
    print(f"""
    // SpotDataCache.kt - landDistToFactor()
    private fun landDistToFactor(distKm: Double): Double {{
        if (distKm < 0) return 1.0
        return when {{
            distKm <= 1.0 -> {opt_floor:.3f}
            distKm <= 2.0 -> {opt_floor:.3f} + {opt_mid2 - opt_floor:.3f} * ((distKm - 1.0) / 1.0)
            distKm <= 5.0 -> {opt_mid2:.3f} + {opt_mid5 - opt_mid2:.3f} * ((distKm - 2.0) / 3.0)
            else -> {opt_cap:.3f}
        }}
    }}

    // Apply after attenuateSwell() wherever the final wave height is computed:
    val surfHeight = attenuatedSwellFt * {opt_scale:.3f}  // offshore-to-surf conversion
""")


if __name__ == "__main__":
    main()
