#!/usr/bin/env python3
"""
Second-pass mover for land spots that failed the first pass (1200m radius).
Uses extended probe radii up to 5km.

Reads failures from /tmp/moved_spots_report.txt (lines starting with "FAIL").
Writes results to /tmp/moved_spots_extended_report.txt and
appends to /tmp/spot_coord_patches.txt.
"""

import json
import math
import re
import sys
import time
import urllib.request
from pathlib import Path

API_URL = "https://is-on-water.balbona.me/api/v1/get/{lat}/{lon}"
HEADERS = {"User-Agent": "shaka-spot-audit/1.0"}
PUSH_OFFSHORE_M = 402.336
R_EARTH = 6_371_000.0

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

# Extended radii — pick up where pass 1 left off
PROBE_RADII_M = [1500, 2000, 2500, 3000, 4000, 5000]


def offset_coord(lat, lon, bearing_deg, distance_m):
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


def direction_bearing(dlat_sign, dlon_sign):
    return math.atan2(dlon_sign, dlat_sign) * 180 / math.pi % 360


def is_water(lat, lon):
    try:
        url = API_URL.format(lat=lat, lon=lon)
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return data.get("isWater", False)
    except Exception as e:
        print(f"  ⚠  API error ({lat},{lon}): {e}", file=sys.stderr)
        return None


def main():
    # Parse failed spots from first-pass report
    report = Path("/tmp/moved_spots_report.txt").read_text()
    fail_re = re.compile(r'^FAIL\s+(\S+)\s+\((-?[\d.]+),(-?[\d.]+)\)')
    spots = []
    for line in report.splitlines():
        m = fail_re.match(line)
        if m:
            spots.append({"id": m.group(1), "lat": float(m.group(2)), "lon": float(m.group(3))})

    print(f"Retrying {len(spots)} failed spots with extended radii…", file=sys.stderr)

    report_lines = []
    patch_lines = []
    success = 0
    fail = 0

    for i, s in enumerate(spots, 1):
        sid, lat, lon = s["id"], s["lat"], s["lon"]
        found = False

        for radius_m in PROBE_RADII_M:
            if found:
                break
            for dir_name, dy, dx in DIRECTIONS:
                bearing = direction_bearing(dy, dx)
                probe_lat, probe_lon = offset_coord(lat, lon, bearing, radius_m)
                result = is_water(probe_lat, probe_lon)
                time.sleep(0.12)
                if result is True:
                    final_lat, final_lon = offset_coord(lat, lon, bearing, radius_m + PUSH_OFFSHORE_M)
                    verify = is_water(final_lat, final_lon)
                    time.sleep(0.12)
                    if verify is True:
                        report_lines.append(f"OK  {sid}  ({lat},{lon}) → ({final_lat},{final_lon})  dir={dir_name}  probe={radius_m}m+402m")
                        patch_lines.append(f"{sid}|{lat}|{lon}|{final_lat}|{final_lon}|{dir_name}|{sid}")
                        success += 1
                        found = True
                        break

        if not found:
            report_lines.append(f"FAIL  {sid}  ({lat},{lon})  still no water within 5km")
            fail += 1

        if i % 5 == 0 or i == len(spots):
            print(f"  [{i}/{len(spots)}]  ok={success}  fail={fail}", file=sys.stderr)

    # Write extended report
    ext_report = Path("/tmp/moved_spots_extended_report.txt")
    ext_report.write_text("\n".join(report_lines) + "\n")

    # Append new patches to the main patch file
    if patch_lines:
        patch_path = Path("/tmp/spot_coord_patches.txt")
        with open(patch_path, "a") as f:
            f.write("\n".join(patch_lines) + "\n")

    print(f"\nExtended report → {ext_report}", file=sys.stderr)
    print(f"New patches: {success}  Still failed: {fail}", file=sys.stderr)


if __name__ == "__main__":
    main()
