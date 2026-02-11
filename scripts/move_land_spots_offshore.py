#!/usr/bin/env python3
"""
Move land-based default spots ~0.25 mi offshore.

Algorithm per spot:
  1. Probe 8 compass directions (N, NE, E, SE, S, SW, W, NW) at increasing
     radii (100 m, 200 m, 400 m, 800 m, 1200 m) until the first water hit.
  2. Once water is found at (probe_lat, probe_lon), push an extra 0.25 mi
     (~402 m) in that same direction to create the final coordinate.
  3. Verify the final coordinate is indeed water.

Inputs:
  /tmp/land_spots_to_move.txt  (pipe-delimited: id|lat|lon|name)

Outputs:
  /tmp/moved_spots_report.txt   — human-readable report
  /tmp/spot_coord_patches.txt   — machine-readable old→new coordinate pairs
                                   (id|old_lat|old_lon|new_lat|new_lon|direction|name)

Usage:
  python3 scripts/move_land_spots_offshore.py
"""

import json
import math
import sys
import time
import urllib.request
from pathlib import Path

API_URL = "https://is-on-water.balbona.me/api/v1/get/{lat}/{lon}"
HEADERS = {"User-Agent": "shaka-spot-audit/1.0"}

# 0.25 nautical miles expressed in metres
PUSH_OFFSHORE_M = 402.336  # 0.25 statute miles in metres

# Earth radius in metres
R_EARTH = 6_371_000.0

# Compass directions: name → (Δlat_sign, Δlon_sign) unit vector components
DIRECTIONS = [
    ("N",  1,  0),
    ("NE", 1,  1),
    ("E",  0,  1),
    ("SE", -1, 1),
    ("S",  -1, 0),
    ("SW", -1, -1),
    ("W",  0,  -1),
    ("NW", 1,  -1),
]

# Probe radii in metres
PROBE_RADII_M = [100, 200, 400, 800, 1200]


# ── helpers ───────────────────────────────────────────────────────────────

def offset_coord(lat: float, lon: float, bearing_deg: float, distance_m: float):
    """
    Move (lat, lon) by `distance_m` along `bearing_deg` (0=N, 90=E).
    Returns (new_lat, new_lon).
    """
    lat_r = math.radians(lat)
    lon_r = math.radians(lon)
    brng = math.radians(bearing_deg)
    d = distance_m / R_EARTH

    new_lat = math.asin(
        math.sin(lat_r) * math.cos(d)
        + math.cos(lat_r) * math.sin(d) * math.cos(brng)
    )
    new_lon = lon_r + math.atan2(
        math.sin(brng) * math.sin(d) * math.cos(lat_r),
        math.cos(d) - math.sin(lat_r) * math.sin(new_lat),
    )

    return round(math.degrees(new_lat), 6), round(math.degrees(new_lon), 6)


def direction_bearing(dlat_sign: int, dlon_sign: int) -> float:
    """Convert compass unit-vector to bearing in degrees."""
    # atan2(east, north) → bearing
    brng_rad = math.atan2(dlon_sign, dlat_sign)
    return brng_rad * 180 / math.pi % 360


def is_water(lat: float, lon: float) -> bool | None:
    try:
        url = API_URL.format(lat=lat, lon=lon)
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return data.get("isWater", False)
    except Exception as e:
        print(f"  ⚠  API error for ({lat}, {lon}): {e}", file=sys.stderr)
        return None


# ── main ──────────────────────────────────────────────────────────────────

def main():
    land_path = Path("/tmp/land_spots_to_move.txt")
    spots = []
    for line in land_path.read_text().strip().splitlines():
        parts = line.split("|")
        spots.append({
            "id": parts[0],
            "lat": float(parts[1]),
            "lon": float(parts[2]),
            "name": parts[3] if len(parts) > 3 else "",
        })

    print(f"Processing {len(spots)} land spots…", file=sys.stderr)

    report_lines: list[str] = []
    patch_lines: list[str] = []
    success_count = 0
    fail_count = 0

    for i, s in enumerate(spots, 1):
        sid, lat, lon, name = s["id"], s["lat"], s["lon"], s["name"]
        found_water = False

        for radius_m in PROBE_RADII_M:
            if found_water:
                break
            for dir_name, dy, dx in DIRECTIONS:
                bearing = direction_bearing(dy, dx)
                probe_lat, probe_lon = offset_coord(lat, lon, bearing, radius_m)

                result = is_water(probe_lat, probe_lon)
                time.sleep(0.12)

                if result is True:
                    # Push 0.25 mi further in the same direction
                    final_lat, final_lon = offset_coord(
                        lat, lon, bearing, radius_m + PUSH_OFFSHORE_M
                    )

                    # Verify final position is water
                    verify = is_water(final_lat, final_lon)
                    time.sleep(0.12)

                    if verify is True:
                        report_lines.append(
                            f"OK  {sid}  ({lat},{lon}) → ({final_lat},{final_lon})  "
                            f"dir={dir_name}  probe={radius_m}m+402m  {name}"
                        )
                        patch_lines.append(
                            f"{sid}|{lat}|{lon}|{final_lat}|{final_lon}|{dir_name}|{name}"
                        )
                        success_count += 1
                        found_water = True
                        break
                    else:
                        # Final point not water — try next direction
                        report_lines.append(
                            f"WARN  {sid}  push-verify failed dir={dir_name} "
                            f"probe={radius_m}m — trying next"
                        )
                        continue

        if not found_water:
            report_lines.append(
                f"FAIL  {sid}  ({lat},{lon})  no water found within 1200m in any direction  {name}"
            )
            fail_count += 1

        if i % 10 == 0 or i == len(spots):
            print(
                f"  [{i}/{len(spots)}]  ok={success_count}  fail={fail_count}",
                file=sys.stderr,
            )

    # Write outputs
    report_path = Path("/tmp/moved_spots_report.txt")
    report_path.write_text("\n".join(report_lines) + "\n")

    patch_path = Path("/tmp/spot_coord_patches.txt")
    patch_path.write_text("\n".join(patch_lines) + "\n")

    print(f"\nReport  → {report_path}", file=sys.stderr)
    print(f"Patches → {patch_path}  ({len(patch_lines)} patches)", file=sys.stderr)
    print(f"\nSUCCESS: {success_count}", file=sys.stderr)
    print(f"FAILED : {fail_count}", file=sys.stderr)


if __name__ == "__main__":
    main()
