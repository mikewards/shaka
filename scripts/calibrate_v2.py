#!/usr/bin/env python3
"""
Scale factor calibration for V2 model.
Grid-searches scale factor and tests model variants.
Uses cached Open-Meteo + exposure data from benchmark_v2.py.
"""

import json
import math
import numpy as np
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
SURFLINE_CACHE = DATA_DIR / "surfline_snapshot.json"
OPENMETEO_V2_CACHE = DATA_DIR / "openmeteo_v2_snapshot.json"
EXPOSURE_CACHE = DATA_DIR / "exposure_cache.json"

METERS_TO_FEET = 3.28084
OPEN = -1.0

PROD_FLOOR = 0.492
PROD_MID2 = 0.706
PROD_MID5 = 0.950
PROD_CAP = 0.954


def land_dist_to_factor(dist_km):
    if dist_km < 0: return 1.0
    if dist_km <= 1.0: return PROD_FLOOR
    if dist_km <= 2.0: return PROD_FLOOR + (PROD_MID2 - PROD_FLOOR) * ((dist_km - 1.0) / 1.0)
    if dist_km <= 5.0: return PROD_MID2 + (PROD_MID5 - PROD_MID2) * ((dist_km - 2.0) / 3.0)
    return PROD_CAP


def attenuate(height_ft, direction_deg, land_distances):
    n = len(land_distances)
    if n == 0 or all(d < 0 for d in land_distances):
        return height_ft, 1.0
    step = 360.0 / n
    norm_dir = ((direction_deg % 360) + 360) % 360
    exact_idx = norm_dir / step
    lower_idx = int(exact_idx) % n
    upper_idx = (lower_idx + 1) % n
    frac = exact_idx - int(exact_idx)
    factor = land_dist_to_factor(land_distances[lower_idx]) * (1.0 - frac) + \
             land_dist_to_factor(land_distances[upper_idx]) * frac
    return height_ft * factor, factor


def period_multiplier(period_s):
    return max(0.85, min(1.15, 0.85 + (period_s - 5.0) * 0.03))


def angle_diff(a, b):
    return ((a - b) + 180) % 360 - 180


def wind_sea_contribution(total_m, swell_m, wind_speed_kmh, wind_dir, swell_dir):
    if total_m <= swell_m or swell_m <= 0:
        return 0.0
    wind_sea_m = math.sqrt(max(0, total_m**2 - swell_m**2))
    if wind_sea_m < 0.05 or wind_speed_kmh < 5:
        return 0.0
    alignment = math.cos(math.radians(angle_diff(wind_dir, swell_dir)))
    if alignment > 0:
        return wind_sea_m * 0.30 * alignment
    return 0.0


def range_error(h, sl_min, sl_max):
    if sl_min <= h <= sl_max:
        return 0.0
    return h - sl_min if h < sl_min else h - sl_max


def build_spot_data(all_spots, om_cache, exp_cache, region_filters):
    now_utc = int(datetime.now(timezone.utc).timestamp())
    rows = []
    for s in all_spots:
        if not any(f(s) for f in region_filters):
            continue
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
        rows.append({
            "name": s["name"],
            "sl_min": sl_min, "sl_max": sl_max,
            "exp": exp,
            "total_m": om.get("wave_height_m", 0) or 0,
            "total_dir": om.get("wave_direction_deg", 0) or 0,
            "swell_m": om.get("swell_height_m", 0) or 0,
            "swell_dir": om.get("swell_direction_deg", 0) or 0,
            "swell_period": om.get("swell_period_s", 0) or 0,
            "sec_h_m": om.get("secondary_swell_height_m", 0) or 0,
            "sec_dir": om.get("secondary_swell_direction_deg", 0) or 0,
            "sec_period": om.get("secondary_swell_period_s", 0) or 0,
            "wind_speed": om.get("wind_speed_kmh", 0) or 0,
            "wind_dir": om.get("wind_direction_deg", 0) or 0,
        })
    return rows


def compute_v2(row, scale, use_period, use_wind, use_secondary):
    swell_ft = row["swell_m"] * METERS_TO_FEET
    h, f = attenuate(swell_ft, row["swell_dir"], row["exp"])

    if use_period:
        pm = period_multiplier(row["swell_period"])
        eff_f = min(1.0, f * pm)
        primary = swell_ft * eff_f
    else:
        primary = h

    secondary = 0.0
    if use_secondary and row["sec_h_m"] > 0.05:
        sec_ft = row["sec_h_m"] * METERS_TO_FEET
        sec_h, sec_f = attenuate(sec_ft, row["sec_dir"], row["exp"])
        if use_period:
            sec_pm = period_multiplier(row["sec_period"])
            sec_eff_f = min(1.0, sec_f * sec_pm)
            secondary = sec_ft * sec_eff_f
        else:
            secondary = sec_h

    combined = math.sqrt(primary**2 + secondary**2) if use_secondary else primary

    if use_wind:
        wind_add = wind_sea_contribution(
            row["total_m"], row["swell_m"],
            row["wind_speed"], row["wind_dir"], row["swell_dir"]
        ) * METERS_TO_FEET
        combined += wind_add

    return combined * scale


def evaluate(rows, scale, use_period, use_wind, use_secondary):
    errors = []
    in_range = 0
    for r in rows:
        h = compute_v2(r, scale, use_period, use_wind, use_secondary)
        err = range_error(h, r["sl_min"], r["sl_max"])
        errors.append(abs(err))
        if err == 0:
            in_range += 1
    mae = np.mean(errors) if errors else 999
    return mae, in_range, len(rows)


def main():
    with open(SURFLINE_CACHE) as f:
        all_spots = json.load(f)["spots"]
    with open(OPENMETEO_V2_CACHE) as f:
        om_cache = json.load(f)
    with open(EXPOSURE_CACHE) as f:
        exp_cache = json.load(f)

    sc_filter = lambda s: 36.7 < s.get("lat", 0) < 37.2 and -122.3 < s.get("lon", 0) < -121.8
    oahu_filter = lambda s: 21.2 < s.get("lat", 0) < 21.75 and -158.4 < s.get("lon", 0) < -157.6
    maui_filter = lambda s: 20.6 < s.get("lat", 0) < 21.15 and -156.8 < s.get("lon", 0) < -155.9

    rows = build_spot_data(all_spots, om_cache, exp_cache, [sc_filter, oahu_filter, maui_filter])
    print(f"Loaded {len(rows)} spots for calibration\n")

    # Also compute production baseline for reference
    prod_errors = []
    prod_in = 0
    for r in rows:
        total_ft = r["total_m"] * METERS_TO_FEET
        h, _ = attenuate(total_ft, r["total_dir"], r["exp"])
        h_scaled = h * 0.728
        err = range_error(h_scaled, r["sl_min"], r["sl_max"])
        prod_errors.append(abs(err))
        if err == 0:
            prod_in += 1
    prod_mae = np.mean(prod_errors)
    print(f"PRODUCTION BASELINE: MAE={prod_mae:.3f}ft  InRange={prod_in}/{len(rows)}  Scale=0.728\n")

    # Test model variants
    configs = [
        ("A: swell only",                            False, False, False),
        ("B: swell + period",                         True,  False, False),
        ("C: swell + wind",                           False, True,  False),
        ("D: swell + period + wind",                  True,  True,  False),
        ("E: swell + secondary",                      False, False, True),
        ("F: swell + period + wind + secondary",      True,  True,  True),
    ]

    scales = np.arange(0.40, 1.01, 0.01)

    print(f"{'Config':45s} {'BestScale':>10s} {'MAE':>8s} {'InRange':>10s} {'vs Prod':>10s}")
    print("-" * 90)

    best_overall_mae = 999
    best_overall = None

    for label, use_p, use_w, use_s in configs:
        best_mae = 999
        best_scale = 0
        best_inrange = 0
        for sc in scales:
            mae, ir, n = evaluate(rows, sc, use_p, use_w, use_s)
            if mae < best_mae:
                best_mae = mae
                best_scale = sc
                best_inrange = ir

        delta = prod_mae - best_mae
        print(f"  {label:43s} {best_scale:9.3f}  {best_mae:7.3f}ft  {best_inrange:4d}/{len(rows):3d}  "
              f"{'▲' if delta > 0 else '▼'}{abs(delta):+.3f}ft")

        if best_mae < best_overall_mae:
            best_overall_mae = best_mae
            best_overall = (label, best_scale, use_p, use_w, use_s, best_inrange)

    print(f"\n{'=' * 90}")
    print(f"BEST: {best_overall[0]}  Scale={best_overall[1]:.3f}  "
          f"MAE={best_overall_mae:.3f}ft  InRange={best_overall[5]}/{len(rows)}")
    print(f"Production: MAE={prod_mae:.3f}ft  InRange={prod_in}/{len(rows)}")
    print(f"Improvement: {prod_mae - best_overall_mae:+.3f}ft MAE  "
          f"{best_overall[5] - prod_in:+d} InRange")
    print(f"{'=' * 90}")

    # Detailed per-spot comparison for best config
    label, scale, use_p, use_w, use_s, _ = best_overall
    print(f"\nDETAILED COMPARISON: {label} @ scale={scale:.3f}")
    print(f"  {'Spot':28s} {'SL Range':>10s} {'Prod':>7s} {'PErr':>7s} {'V2':>7s} {'V2Err':>7s} {'Delta':>7s}")
    print(f"  {'-'*28} {'-'*10} {'-'*7} {'-'*7} {'-'*7} {'-'*7} {'-'*7}")

    all_deltas = []
    for r in rows:
        total_ft = r["total_m"] * METERS_TO_FEET
        prod_h, _ = attenuate(total_ft, r["total_dir"], r["exp"])
        prod_h_s = prod_h * 0.728
        prod_err = range_error(prod_h_s, r["sl_min"], r["sl_max"])

        v2_h = compute_v2(r, scale, use_p, use_w, use_s)
        v2_err = range_error(v2_h, r["sl_min"], r["sl_max"])
        delta = abs(prod_err) - abs(v2_err)
        all_deltas.append(delta)

        sl_str = f"{r['sl_min']:.0f}-{r['sl_max']:.0f}ft"
        arrow = "+" if delta > 0.1 else ("-" if delta < -0.1 else "=")
        print(f"  {r['name']:28s} {sl_str:>10s} {prod_h_s:6.1f}ft {prod_err:+6.1f}f "
              f"{v2_h:6.1f}ft {v2_err:+6.1f}f {arrow}{delta:+5.1f}ft")

    improved = sum(1 for d in all_deltas if d > 0.1)
    regressed = sum(1 for d in all_deltas if d < -0.1)
    print(f"\n  Improved: {improved}  Regressed: {regressed}  "
          f"Unchanged: {len(all_deltas) - improved - regressed}")


if __name__ == "__main__":
    main()
