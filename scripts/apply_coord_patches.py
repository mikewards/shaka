#!/usr/bin/env python3
"""
Apply coordinate patches from move_land_spots_offshore.py to SpotDatabase.kt.

Reads:
  /tmp/spot_coord_patches.txt — id|old_lat|old_lon|new_lat|new_lon|direction|name

Produces:
  - Updates SpotDatabase.kt in-place
  - Writes /tmp/coord_patch_diff.txt with before/after for review

Usage:
  python3 scripts/apply_coord_patches.py [--dry-run]
"""

import re
import sys
from pathlib import Path

SPOT_DB_PATH = Path(__file__).resolve().parent.parent / \
    "shaka-api/src/main/kotlin/com/shaka/data/client/SpotDatabase.kt"

PATCH_FILE = Path("/tmp/spot_coord_patches.txt")


def main():
    dry_run = "--dry-run" in sys.argv

    # Load patches
    patches = {}
    for line in PATCH_FILE.read_text().strip().splitlines():
        if not line.strip():
            continue
        parts = line.split("|")
        spot_id = parts[0]
        patches[spot_id] = {
            "old_lat": parts[1],
            "old_lon": parts[2],
            "new_lat": parts[3],
            "new_lon": parts[4],
            "direction": parts[5],
            "name": parts[6] if len(parts) > 6 else "",
        }

    print(f"Loaded {len(patches)} patches from {PATCH_FILE}", file=sys.stderr)

    # Read SpotDatabase.kt
    text = SPOT_DB_PATH.read_text()
    original = text

    diff_lines: list[str] = []
    applied = 0
    missed = 0

    for spot_id, p in patches.items():
        new_lat, new_lon = p["new_lat"], p["new_lon"]

        # Match by spot ID, then find and replace the Coordinates(...) on that line.
        # Pattern: SpotRecord("<id>", ... Coordinates(<any_lat>, <any_lon>) ...)
        escaped_id = re.escape(spot_id)
        pattern = (
            rf'(SpotRecord\(\s*"{escaped_id}"\s*,.*?Coordinates\(\s*)'
            rf'(-?[\d.]+)\s*,\s*(-?[\d.]+)'
            rf'(\s*\))'
        )

        match = re.search(pattern, text, flags=re.DOTALL)
        if match:
            old_lat_in_file = match.group(2)
            old_lon_in_file = match.group(3)
            replacement = f"{match.group(1)}{new_lat}, {new_lon}{match.group(4)}"
            text = text[:match.start()] + replacement + text[match.end():]
            applied += 1
            diff_lines.append(
                f"  {spot_id}: Coordinates({old_lat_in_file}, {old_lon_in_file}) → "
                f"Coordinates({new_lat}, {new_lon})  [{p['direction']}]  {p['name']}"
            )
        else:
            missed += 1
            diff_lines.append(f"  MISS {spot_id}: SpotRecord not found in file")
            print(f"  ⚠ MISS: {spot_id}", file=sys.stderr)

    # Write diff
    diff_path = Path("/tmp/coord_patch_diff.txt")
    diff_path.write_text("\n".join(diff_lines) + "\n")
    print(f"\nDiff report → {diff_path}", file=sys.stderr)
    print(f"Applied: {applied}  Missed: {missed}", file=sys.stderr)

    if dry_run:
        print("\n[DRY RUN] No files modified.", file=sys.stderr)
        return

    if text != original:
        SPOT_DB_PATH.write_text(text)
        print(f"Updated {SPOT_DB_PATH.name} with {applied} coordinate changes", file=sys.stderr)
    else:
        print("No changes to write.", file=sys.stderr)


if __name__ == "__main__":
    main()
