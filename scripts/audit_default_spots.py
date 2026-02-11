#!/usr/bin/env python3
"""
Audit every default spot in SpotDatabase.kt and classify it as LAND or WATER.

Outputs:
  /tmp/spot_audit_report.txt  — full report (one line per spot)
  /tmp/land_spots_to_move.txt — only the LAND spots (pipe-delimited, for the move script)

Usage:
  python3 scripts/audit_default_spots.py [--dry-run]

  --dry-run   Parse spots only; skip the API calls and print the parsed list.
"""

import re
import sys
import json
import time
import urllib.request
from pathlib import Path

SPOT_DB_PATH = Path(__file__).resolve().parent.parent / \
    "shaka-api/src/main/kotlin/com/shaka/data/client/SpotDatabase.kt"

API_URL = "https://is-on-water.balbona.me/api/v1/get/{lat}/{lon}"

# ── 1) Parse SpotDatabase.kt ─────────────────────────────────────────────

SPOT_RE = re.compile(
    r'SpotRecord\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"[^"]*"\s*,\s*'
    r'Coordinates\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)',
    re.DOTALL,
)


def parse_spots() -> list[dict]:
    """Return [{id, name, lat, lon}, …] from SpotDatabase.kt."""
    text = SPOT_DB_PATH.read_text()
    spots = []
    for m in SPOT_RE.finditer(text):
        spots.append({
            "id": m.group(1),
            "name": m.group(2),
            "lat": float(m.group(3)),
            "lon": float(m.group(4)),
        })
    return spots


# ── 2) Land / water classifier ───────────────────────────────────────────

def is_water(lat: float, lon: float) -> bool | None:
    """True = water, False = land, None = API error."""
    try:
        url = API_URL.format(lat=lat, lon=lon)
        req = urllib.request.Request(url, headers={"User-Agent": "shaka-spot-audit/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return data.get("isWater", False)
    except Exception as e:
        print(f"  ⚠  API error for ({lat}, {lon}): {e}", file=sys.stderr)
        return None


# ── 3) Main ──────────────────────────────────────────────────────────────

def main():
    dry_run = "--dry-run" in sys.argv

    spots = parse_spots()
    print(f"Parsed {len(spots)} spots from {SPOT_DB_PATH.name}", file=sys.stderr)

    if dry_run:
        for s in spots:
            print(f"{s['id']}  ({s['lat']}, {s['lon']})  {s['name']}")
        return

    report_lines: list[str] = []
    land_lines: list[str] = []
    water_count = 0
    land_count = 0
    error_count = 0

    for i, s in enumerate(spots, 1):
        result = is_water(s["lat"], s["lon"])

        if result is True:
            tag = "WATER"
            water_count += 1
        elif result is False:
            tag = "LAND"
            land_count += 1
            land_lines.append(f"{s['id']}|{s['lat']}|{s['lon']}|{s['name']}")
        else:
            tag = "ERROR"
            error_count += 1

        line = f"{tag}|{s['id']}|{s['lat']}|{s['lon']}|{s['name']}"
        report_lines.append(line)

        if i % 50 == 0 or i == len(spots):
            print(
                f"  [{i}/{len(spots)}]  water={water_count}  land={land_count}  err={error_count}",
                file=sys.stderr,
            )

        time.sleep(0.12)  # ~8 req/s — stay well under rate limit

    # Write full report
    report_path = Path("/tmp/spot_audit_report.txt")
    report_path.write_text("\n".join(report_lines) + "\n")
    print(f"\nFull report → {report_path}  ({len(report_lines)} spots)", file=sys.stderr)

    # Write land-only list
    land_path = Path("/tmp/land_spots_to_move.txt")
    land_path.write_text("\n".join(land_lines) + "\n")
    print(f"Land spots  → {land_path}  ({len(land_lines)} spots)", file=sys.stderr)

    # Summary
    print(f"\n{'='*50}", file=sys.stderr)
    print(f"WATER : {water_count}", file=sys.stderr)
    print(f"LAND  : {land_count}", file=sys.stderr)
    print(f"ERROR : {error_count}", file=sys.stderr)
    print(f"TOTAL : {len(spots)}", file=sys.stderr)
    print(f"{'='*50}", file=sys.stderr)


if __name__ == "__main__":
    main()
