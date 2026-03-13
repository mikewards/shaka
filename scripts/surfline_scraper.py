#!/usr/bin/env python3
"""
Surfline Spot Scraper via Playwright

Uses a headless browser to bypass Cloudflare and access Surfline's
undocumented API. Collects spot IDs + lat/lon from the taxonomy,
then fetches wave forecasts for each spot.
"""

import asyncio
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from playwright.async_api import async_playwright

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

SPOT_CATALOG_FILE = DATA_DIR / "surfline_spots.json"
SURFLINE_CACHE = DATA_DIR / "surfline_snapshot.json"

REGIONS = [
    ("California", "58f7ed51dadb30820bb387a6"),
    ("Hawaii", "58f7ed87dadb30820bb3c50d"),
    ("Florida", "58f7ed7bdadb30820bb3b6e5"),
    ("New York", "58f7ed71dadb30820bb3ac4f"),
    ("North Carolina", "58f7ed77dadb30820bb3b2b2"),
    ("New Jersey", "58f7ed73dadb30820bb3aeca"),
    ("Texas", "58f7ed84dadb30820bb3c213"),
    ("Oregon", "58f7ed53dadb30820bb38a85"),
    ("Australia", "58f7ef51dadb30820bb5c498"),
    ("Portugal", "58f7ef37dadb30820bb5a7e8"),
    ("France", "58f7ef3fdadb30820bb5b1b2"),
    ("Indonesia", "58f7eef1dadb30820bb556c9"),
    ("Mexico", "58f7eeecdadb30820bb550cc"),
    ("Brazil", "58f7efffdadb30820bb68b24"),
    ("United Kingdom", "58f7efcadadb30820bb64fb3"),
    ("South Africa", "58f7f015dadb30820bb6a402"),
    ("Japan", "58f7f061dadb30820bb6f78d"),
    ("Costa Rica", "58f7eef2dadb30820bb557af"),
    ("Puerto Rico", "58f7eeeedadb30820bb55333"),
]

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"


def collect_spots_from_taxonomy(node):
    """Recursively extract all spot nodes from a taxonomy tree."""
    spots = []
    if node.get("type") == "spot" and node.get("spot"):
        coords = node.get("location", {}).get("coordinates", [])
        spots.append({
            "spot_id": node["spot"],
            "name": node.get("name", ""),
            "lon": coords[0] if len(coords) > 0 else None,
            "lat": coords[1] if len(coords) > 1 else None,
        })
    for child in node.get("contains", []):
        spots.extend(collect_spots_from_taxonomy(child))
    for s in node.get("spots", []):
        spots.extend(collect_spots_from_taxonomy(s))
    return spots


async def fetch_all_spots(page):
    """Fetch spot catalog from all regions via taxonomy API."""
    all_spots = {}

    for region_name, region_id in REGIONS:
        url = f"https://services.surfline.com/taxonomy?type=taxonomy&id={region_id}&maxDepth=3"
        try:
            resp = await page.goto(url, wait_until="domcontentloaded", timeout=30000)
            if resp.status != 200:
                print(f"  [{region_name}] HTTP {resp.status}, skipping")
                continue

            text = await page.inner_text("body")
            data = json.loads(text)
            spots = collect_spots_from_taxonomy(data)

            new_count = 0
            for s in spots:
                sid = s["spot_id"]
                if sid not in all_spots and s["lat"] is not None:
                    s["region"] = region_name
                    all_spots[sid] = s
                    new_count += 1

            print(f"  [{region_name}] {len(spots)} spots found, {new_count} new (total: {len(all_spots)})")
        except Exception as e:
            print(f"  [{region_name}] ERROR: {e}")

        await asyncio.sleep(0.3)

    return list(all_spots.values())


async def fetch_wave_forecasts(page, spots, batch_size=50):
    """Fetch wave forecast for each spot. Operates in batches with progress."""
    total = len(spots)
    success = 0
    failed = 0

    for i, spot in enumerate(spots):
        sid = spot["spot_id"]
        url = f"https://services.surfline.com/kbyg/spots/forecasts/wave?spotId={sid}&days=1&intervalHours=1"

        try:
            resp = await page.goto(url, wait_until="domcontentloaded", timeout=15000)
            if resp.status == 200:
                text = await page.inner_text("body")
                data = json.loads(text)
                wave_entries = data.get("data", {}).get("wave", [])
                spot["forecast"] = []
                for w in wave_entries:
                    surf = w.get("surf", {})
                    swells = w.get("swells", [])
                    primary_swell = swells[0] if swells else {}
                    spot["forecast"].append({
                        "timestamp": w.get("timestamp"),
                        "wave_min_ft": surf.get("min"),
                        "wave_max_ft": surf.get("max"),
                        "swell_height_ft": primary_swell.get("height"),
                        "swell_period_s": primary_swell.get("period"),
                        "swell_direction_deg": primary_swell.get("direction"),
                    })
                success += 1
            else:
                spot["forecast"] = []
                failed += 1
        except Exception as e:
            spot["forecast"] = []
            failed += 1

        if (i + 1) % batch_size == 0 or i == total - 1:
            print(f"  [{i+1}/{total}] forecasts fetched (ok={success}, fail={failed})")

        await asyncio.sleep(0.15)

    return spots


async def main():
    print("\n" + "=" * 60)
    print("SURFLINE SCRAPER (Playwright)")
    print("=" * 60)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(user_agent=UA)
        page = await context.new_page()

        # Phase 1: Collect spot catalog
        print("\n[Phase 1] Collecting spots from taxonomy...")
        if SPOT_CATALOG_FILE.exists():
            print(f"  Using cached catalog from {SPOT_CATALOG_FILE}")
            with open(SPOT_CATALOG_FILE) as f:
                spots = json.load(f)
            print(f"  {len(spots)} spots loaded")
        else:
            spots = await fetch_all_spots(page)
            with open(SPOT_CATALOG_FILE, "w") as f:
                json.dump(spots, f)
            print(f"  Saved {len(spots)} spots to {SPOT_CATALOG_FILE}")

        # Phase 2: Fetch wave forecasts
        print(f"\n[Phase 2] Fetching wave forecasts for {len(spots)} spots...")
        spots = await fetch_wave_forecasts(page, spots)

        # Phase 3: Save final snapshot
        with_forecast = [s for s in spots if s.get("forecast")]
        snapshot = {
            "fetched_at_utc": datetime.now(timezone.utc).isoformat(),
            "total_spots": len(with_forecast),
            "spots": with_forecast,
        }
        with open(SURFLINE_CACHE, "w") as f:
            json.dump(snapshot, f)

        print(f"\n[Done] {len(with_forecast)} spots with forecasts saved to {SURFLINE_CACHE}")

        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
