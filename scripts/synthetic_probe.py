#!/usr/bin/env python3
"""
Synthetic user-journey probe for Shaka production.

Hits the exact endpoints the mobile app uses, with latency budgets and
response-shape assertions, plus drift checks on the highest-churn external
dependencies. Designed to run every 30 minutes from GitHub Actions.

Rationale: the Jun 2026 outage (hung Postgres -> infinite spinners) and the
Apr 2026 tide-service crash-removal were both invisible for days/weeks
because nothing exercised the user-facing path. This probe would have caught
every one of those failures within 30 minutes.

Exit code 0 = all checks pass. Non-zero = at least one failure (workflow
alerting handles notification). On success, pings PROBE_HEARTBEAT_URL if set,
so a missed heartbeat also covers "the probe itself stopped running".
"""

import datetime
import json
import os
import sys
import time
import urllib.request

API = "https://shaka-production.up.railway.app/v1"
LATENCY_BUDGET_S = 10
# Open-Meteo's old hardcoded fallback: 10 km/h = 5.39957 kts. Real data
# matching this exactly across responses means fabricated conditions.
FAKE_WIND_KTS = 5.39957

failures: list[str] = []


def fetch(url: str, headers: dict | None = None, timeout: int = LATENCY_BUDGET_S):
    req = urllib.request.Request(url, headers=headers or {})
    start = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        return resp.status, time.time() - start, body


def check(name: str, fn) -> None:
    try:
        fn()
        print(f"PASS {name}")
    except Exception as e:
        failures.append(f"{name}: {e}")
        print(f"FAIL {name}: {e}")


def expect(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def today() -> str:
    return datetime.date.today().isoformat()


# ---------- App-endpoint checks ----------

def check_health():
    status, elapsed, body = fetch(f"{API}/health")
    expect(status == 200, f"status {status}")
    d = json.loads(body)
    expect(d.get("db") == "ok", f"db={d.get('db')}")


def check_spot_detail():
    status, elapsed, body = fetch(f"{API}/spots/cali-la-jolla-cove?date={today()}")
    expect(status == 200, f"status {status}")
    expect(elapsed < LATENCY_BUDGET_S, f"latency {elapsed:.1f}s")
    d = json.loads(body)
    expect("conditions" in d, "missing conditions")
    wind = d["conditions"].get("windSpeedKts")
    expect(wind is None or abs(wind - FAKE_WIND_KTS) > 1e-4,
           "fabricated-default wind fingerprint detected")


def check_search():
    status, elapsed, body = fetch(f"{API}/spots/search?lat=33.5&lon=-117.8&date={today()}&radius=50")
    expect(status == 200, f"status {status}")
    expect(elapsed < LATENCY_BUDGET_S, f"latency {elapsed:.1f}s")
    spots = json.loads(body).get("spots", [])
    expect(len(spots) > 0, "no spots returned")
    winds = {s.get("conditions", {}).get("windSpeedKts") for s in spots}
    expect(winds != {FAKE_WIND_KTS}, "identical fabricated wind across all spots")


def check_region_intel():
    status, elapsed, body = fetch(f"{API}/regions/san_diego/intel?since=72h&tzOffset=-8")
    expect(status == 200, f"status {status} (scrape pipeline stale?)")
    expect(elapsed < LATENCY_BUDGET_S, f"latency {elapsed:.1f}s")
    d = json.loads(body)
    expect("hotSpecies" in d, "missing hotSpecies")


def check_user_spots():
    status, elapsed, _ = fetch(f"{API}/user-spots", headers={"X-Device-ID": "synthetic-probe"})
    expect(status == 200, f"status {status}")
    expect(elapsed < LATENCY_BUDGET_S, f"latency {elapsed:.1f}s")


def check_freshness():
    status, _, body = fetch(f"{API}/health/freshness")
    expect(status == 200, f"status {status}")
    d = json.loads(body)
    stale = set(d.get("staleTypes", []))
    # Core conditions data going stale = user-visible breakage
    core_stale = stale & {"tide", "swell", "wind"}
    expect(not core_stale, f"core data stale: {sorted(core_stale)}")


def check_jobs():
    status, _, body = fetch(f"{API}/health/jobs")
    expect(status == 200, f"status {status}")
    d = json.loads(body)
    breached = [k for k, v in d.items() if v.get("status") == "BREACH"]
    expect(not breached, f"jobs in BREACH: {breached}")


# ---------- Upstream drift checks ----------

def check_erddap_sst():
    status, _, _ = fetch("https://coastwatch.noaa.gov/erddap/info/noaacwBLENDEDsstDNDaily/index.json")
    expect(status == 200, f"status {status} (SST dataset moved?)")


def check_copernicus_wmts():
    status, _, body = fetch("https://wmts.marine.copernicus.eu/teroWmts?SERVICE=WMTS&REQUEST=GetCapabilities", timeout=20)
    expect(status == 200, f"status {status}")
    expect(b"cmems_obs-oc_glo_bgc-transp_nrt_l3-multi-4km_P1D_202311" in body,
           "ZSD layer version rotated out of GetCapabilities")


def check_gibs_tile():
    date = (datetime.date.today() - datetime.timedelta(days=2)).isoformat()
    status, _, _ = fetch(f"https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/OCI_PACE_Chlorophyll_a/default/{date}/GoogleMapsCompatible_Level7/5/5/8.png")
    expect(status == 200, f"status {status} (GIBS layer deprecated?)")


def check_scraper_target():
    date = (datetime.date.today() - datetime.timedelta(days=1)).strftime("%m-%d-%Y")
    status, _, body = fetch(
        f"https://www.sportfishingreport.com/dock_totals/?select={date}&region_id=0",
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"},
        timeout=20,
    )
    expect(status == 200, f"status {status}")
    expect(body.count(b"Dock Totals") >= 5, "dock totals HTML structure changed")
    expect(b"/landings/" in body, "landing links missing (selectors will break)")


def check_tide_service():
    status, _, body = fetch("https://lavish-radiance-production.up.railway.app/health", timeout=15)
    expect(status == 200, f"status {status}")
    expect(json.loads(body).get("status") == "ok", f"tide service not ready: {body[:80]}")


def main() -> int:
    checks = [
        ("api health (db ping)", check_health),
        ("spot detail", check_spot_detail),
        ("spot search", check_search),
        ("region intel", check_region_intel),
        ("user spots", check_user_spots),
        ("data freshness", check_freshness),
        ("job statuses", check_jobs),
        ("tide service", check_tide_service),
        ("upstream: ERDDAP SST dataset", check_erddap_sst),
        ("upstream: Copernicus WMTS layer", check_copernicus_wmts),
        ("upstream: GIBS tile", check_gibs_tile),
        ("upstream: sportfishingreport HTML", check_scraper_target),
    ]
    for name, fn in checks:
        check(name, fn)

    if failures:
        print(f"\n{len(failures)} check(s) failed:")
        for f in failures:
            print(f"  - {f}")
        return 1

    heartbeat = os.environ.get("PROBE_HEARTBEAT_URL")
    if heartbeat:
        try:
            fetch(heartbeat, timeout=10)
            print("heartbeat pinged")
        except Exception as e:
            print(f"heartbeat ping failed (non-fatal): {e}")

    print("\nAll checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
