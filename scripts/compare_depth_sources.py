#!/usr/bin/env python3
"""
Compare NCEI depth values (stored in spot_exposure) against Google Elevation API
for all spots that have depth_source='ncei'.
"""

import csv
import os
import re
import statistics
import sys
import time
from pathlib import Path

import psycopg2
import requests

GOOGLE_API_KEY = os.environ.get("GOOGLE_ELEVATION_API_KEY", "")
GOOGLE_ELEVATION_URL = "https://maps.googleapis.com/maps/api/elevation/json"
BATCH_SIZE = 10
BATCH_DELAY = 0.1

SPOT_DB_PATH = Path(__file__).resolve().parent.parent / "shaka-api/src/main/kotlin/com/shaka/data/client/SpotDatabase.kt"
REPORT_CSV = Path(__file__).parent / "depth_comparison_report.csv"

DEPTH_SQL = """
SELECT spot_id, depth_m, depth_source
FROM spot_exposure
WHERE depth_source = 'ncei' AND depth_m IS NOT NULL;
"""

USER_COORDS_SQL = """
SELECT 'user-' || id::text AS spot_id, name, latitude, longitude
FROM user_spots;
"""


def load_env():
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


def parse_spot_database() -> dict[str, dict]:
    """Parse SpotDatabase.kt to extract spot IDs, names, and coordinates."""
    text = SPOT_DB_PATH.read_text()
    pattern = re.compile(
        r'SpotRecord\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"[^"]*"\s*,\s*Coordinates\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)'
    )
    spots = {}
    for m in pattern.finditer(text):
        spot_id, name, lat, lon = m.group(1), m.group(2), float(m.group(3)), float(m.group(4))
        spots[spot_id] = {"name": name, "lat": lat, "lon": lon}
    return spots


def fetch_ncei_depths(db_url: str) -> list[dict]:
    conn = psycopg2.connect(db_url)
    try:
        with conn.cursor() as cur:
            cur.execute(DEPTH_SQL)
            return [{"spot_id": r[0], "depth_m": r[1], "depth_source": r[2]} for r in cur.fetchall()]
    finally:
        conn.close()


def fetch_google_elevations(spots: list[dict]) -> dict[str, dict]:
    """Batch-fetch elevations from Google. Returns {spot_id: {elevation, resolution}}."""
    results = {}
    for i in range(0, len(spots), BATCH_SIZE):
        batch = spots[i : i + BATCH_SIZE]
        locations = "|".join(f"{s['lat']},{s['lon']}" for s in batch)
        resp = requests.get(
            GOOGLE_ELEVATION_URL,
            params={"locations": locations, "key": GOOGLE_API_KEY},
            timeout=30,
        )
        data = resp.json()
        if data.get("status") != "OK":
            print(f"  Google API error on batch {i // BATCH_SIZE}: {data.get('status')} - {data.get('error_message', '')}")
            continue

        for spot, result in zip(batch, data["results"]):
            results[spot["spot_id"]] = {
                "elevation": result["elevation"],
                "resolution": result.get("resolution"),
            }

        done = min(i + BATCH_SIZE, len(spots))
        print(f"  Fetched {done}/{len(spots)} from Google Elevation API")
        if i + BATCH_SIZE < len(spots):
            time.sleep(BATCH_DELAY)

    return results


def compare(spots: list[dict], google: dict[str, dict]) -> list[dict]:
    rows = []
    for s in spots:
        g = google.get(s["spot_id"])
        if g is None:
            continue
        ncei_depth = s["depth_m"]
        google_elev = g["elevation"]
        google_depth = abs(google_elev) if google_elev < 0 else -google_elev
        diff = ncei_depth - google_depth
        avg = (ncei_depth + google_depth) / 2 if (ncei_depth + google_depth) != 0 else 0.001
        pct = (diff / avg) * 100 if avg != 0 else 0

        rows.append({
            "spot_id": s["spot_id"],
            "name": s["name"],
            "lat": s["lat"],
            "lon": s["lon"],
            "ncei_depth_m": round(ncei_depth, 2),
            "google_depth_m": round(google_depth, 2),
            "google_raw_elev": round(google_elev, 2),
            "google_resolution_m": round(g["resolution"], 2) if g["resolution"] else None,
            "diff_m": round(diff, 2),
            "pct_diff": round(pct, 1),
        })
    return rows


def write_csv(rows: list[dict]):
    if not rows:
        return
    with open(REPORT_CSV, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)
    print(f"\nCSV written to {REPORT_CSV}")


def print_summary(rows: list[dict]):
    if not rows:
        print("No data to compare.")
        return

    diffs = [r["diff_m"] for r in rows]
    abs_diffs = [abs(d) for d in diffs]
    ncei_vals = [r["ncei_depth_m"] for r in rows]
    google_vals = [r["google_depth_m"] for r in rows]

    land_water_mismatch = [r for r in rows if r["ncei_depth_m"] > 0 and r["google_raw_elev"] > 0]
    big_pct = [r for r in rows if abs(r["pct_diff"]) > 20]

    print("\n" + "=" * 70)
    print(f"  NCEI vs Google Elevation — {len(rows)} spots compared")
    print("=" * 70)
    print(f"  Mean absolute difference:   {statistics.mean(abs_diffs):.2f} m")
    print(f"  Median absolute difference: {statistics.median(abs_diffs):.2f} m")
    print(f"  Max absolute difference:    {max(abs_diffs):.2f} m")
    if len(diffs) > 1:
        print(f"  Std dev of differences:     {statistics.stdev(diffs):.2f} m")
    print(f"  NCEI depth range:           {min(ncei_vals):.1f} – {max(ncei_vals):.1f} m")
    print(f"  Google depth range:         {min(google_vals):.1f} – {max(google_vals):.1f} m")

    try:
        n = len(rows)
        mean_n = statistics.mean(ncei_vals)
        mean_g = statistics.mean(google_vals)
        cov = sum((ncei_vals[i] - mean_n) * (google_vals[i] - mean_g) for i in range(n)) / n
        std_n = statistics.pstdev(ncei_vals)
        std_g = statistics.pstdev(google_vals)
        corr = cov / (std_n * std_g) if std_n > 0 and std_g > 0 else 0
        print(f"  Pearson correlation:        {corr:.4f}")
    except Exception:
        pass

    print(f"\n  Spots with >20% difference: {len(big_pct)}/{len(rows)}")
    print(f"  NCEI=water but Google=land: {len(land_water_mismatch)}")

    if big_pct:
        print(f"\n  Top outliers (by absolute difference):")
        for r in sorted(big_pct, key=lambda x: abs(x["diff_m"]), reverse=True)[:15]:
            print(f"    {r['name']:40s}  NCEI={r['ncei_depth_m']:7.1f}m  Google={r['google_depth_m']:7.1f}m  diff={r['diff_m']:+.1f}m ({r['pct_diff']:+.0f}%)")

    if land_water_mismatch:
        print(f"\n  Land/water mismatches (NCEI says water, Google says land):")
        for r in land_water_mismatch[:10]:
            print(f"    {r['name']:40s}  NCEI={r['ncei_depth_m']:.1f}m  GoogleElev={r['google_raw_elev']:.1f}m")

    print("=" * 70)


def main():
    load_env()
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("ERROR: DATABASE_URL not set. Check .env file.", file=sys.stderr)
        sys.exit(1)

    print("Parsing SpotDatabase.kt for coordinates...")
    coord_map = parse_spot_database()
    print(f"  Parsed {len(coord_map)} curated spots")

    print("Querying database for spots with NCEI depth data...")
    ncei_rows = fetch_ncei_depths(db_url)
    print(f"  Found {len(ncei_rows)} spots with NCEI depth")

    if not ncei_rows:
        print("Nothing to compare.")
        return

    merged = []
    skipped = 0
    for row in ncei_rows:
        coords = coord_map.get(row["spot_id"])
        if coords is None:
            skipped += 1
            continue
        merged.append({
            "spot_id": row["spot_id"],
            "name": coords["name"],
            "lat": coords["lat"],
            "lon": coords["lon"],
            "depth_m": row["depth_m"],
        })
    if skipped:
        print(f"  Skipped {skipped} spots (no coordinates found in SpotDatabase.kt)")
    print(f"  {len(merged)} spots ready for Google comparison")

    print(f"\nFetching Google Elevation API for {len(merged)} coordinates...")
    google = fetch_google_elevations(merged)
    print(f"  Got {len(google)} Google results")

    print("\nComparing...")
    rows = compare(merged, google)

    write_csv(rows)
    print_summary(rows)


if __name__ == "__main__":
    main()
