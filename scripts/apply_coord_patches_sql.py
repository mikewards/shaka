#!/usr/bin/env python3
"""
Apply the same coordinate patches to db/init.sql.
Matches INSERT statements by old latitude/longitude values and replaces them.

Usage:
  python3 scripts/apply_coord_patches_sql.py [--dry-run]
"""

import re
import sys
from pathlib import Path

SQL_PATH = Path(__file__).resolve().parent.parent / "db/init.sql"
PATCH_FILE = Path("/tmp/spot_coord_patches.txt")


def float_eq(a: str, b: float, tol: float = 0.0001) -> bool:
    """Check if a string and float represent the same coordinate."""
    try:
        return abs(float(a) - b) < tol
    except ValueError:
        return False


def main():
    dry_run = "--dry-run" in sys.argv

    # Load patches
    patches = []
    for line in PATCH_FILE.read_text().strip().splitlines():
        if not line.strip():
            continue
        parts = line.split("|")
        patches.append({
            "id": parts[0],
            "old_lat": float(parts[1]),
            "old_lon": float(parts[2]),
            "new_lat": parts[3],
            "new_lon": parts[4],
        })

    print(f"Loaded {len(patches)} patches", file=sys.stderr)

    text = SQL_PATH.read_text()
    original = text
    applied = 0

    for p in patches:
        old_lat, old_lon = p["old_lat"], p["old_lon"]
        new_lat, new_lon = p["new_lat"], p["new_lon"]

        # Match: latitude value followed by longitude value in a VALUES clause
        # Coordinates appear as: ..., <lat>, <lon>, ...
        # We need to match the specific pair of numbers
        # Use a regex that finds the lat/lon pair within a VALUES context
        pattern = re.compile(
            r"(VALUES\s*\([^)]*?'[^']*'(?:''[^']*')*\s*,\s*'[^']*(?:''[^']*)*'\s*,\s*)"
            r"(-?[\d.]+)\s*,\s*(-?[\d.]+)"
        )

        new_text = text
        for m in pattern.finditer(text):
            found_lat = float(m.group(2))
            found_lon = float(m.group(3))
            if abs(found_lat - old_lat) < 0.001 and abs(found_lon - old_lon) < 0.001:
                replacement = f"{m.group(1)}{new_lat}, {new_lon}"
                new_text = text[:m.start()] + replacement + text[m.end():]
                applied += 1
                break

        text = new_text

    print(f"Applied: {applied} / {len(patches)}", file=sys.stderr)

    if dry_run:
        print("[DRY RUN] No files modified.", file=sys.stderr)
        return

    if text != original:
        SQL_PATH.write_text(text)
        print(f"Updated {SQL_PATH.name}", file=sys.stderr)
    else:
        print("No changes.", file=sys.stderr)


if __name__ == "__main__":
    main()
