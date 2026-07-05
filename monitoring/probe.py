#!/usr/bin/env python3
"""
Synthetic monitor v2 for the Shaka production backend.

Design: docs/synthetic-monitor-design.md. Journey shapes: monitoring/journeys.json.

Two tiers:
  Tier 1 — user-impacting checks that can page (workflow exit 1 = one email),
           gated by consecutive-failure grace and recovery hysteresis.
  Tier 2 — drift checks that only ever update the pinned status issue.

Alerting is state-transition based via a pinned GitHub issue labeled
`monitor-status` (state persists in an HTML comment block in the body):
  - NEW critical (after grace)  -> body edit + exit 1  (the one email)
  - ongoing critical            -> body edit only, exit 0 (comments email
                                   everyone — never comment routinely)
  - re-escalation               -> deliberate comment at 72h and 7d
  - recovery (after hysteresis) -> deliberate comment + close incident, exit 0
  - human interference          -> unparsable/missing issue = state "unknown";
                                   never pages until grace re-accumulates;
                                   multiple issues -> newest wins, rest closed

A Sentry Cron check-in (SENTRY_CRON_CHECKIN_URL) is sent at the end of EVERY
run, pass or fail — the dead-man's switch for "the probe itself stopped
running" (GitHub disables schedules after 60 days of repo inactivity, etc.).

Probe-owned business constants (deliberately NOT read from backend config —
they exist so the backend cannot self-ratify a bad change) live in
journeys.json: the T4 generatedAt recency anchor (30h) and T5's 7 day-curves.

Modes:
  production (default)      full checks against prod, GitHub state machine
  --local                   CI contract mode: seeded localhost API, shape
                            assertions only, no GitHub/Sentry, exit 1 on any
                            tier-1 failure (fails the PR)
  --dry-run                 no GitHub writes, prints what would happen
  --force-notify            inject a synthetic critical to test the paging path
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

# ---------------- Probe mechanics (no business thresholds here) ----------------
LATENCY_BUDGET_S = 10
PER_CHECK_RETRIES = 1          # one retry per check within a run
RETRY_BACKOFF_S = 5
TIER1_ONSET_RUNS = 2           # consecutive failing runs before paging (~1h)
RECOVERY_RUNS = 3              # consecutive green runs before closing (hysteresis)
TIER2_SURFACE_RUNS = 3         # consecutive failing runs before a warning surfaces
REESCALATE_AFTER = [72 * 3600, 7 * 24 * 3600]   # 72h, 7d
STATUS_LABEL = "monitor-status"
STATE_LABELS = {"ok": "monitor:ok", "warning": "monitor:warning", "critical": "monitor:critical"}
STATE_RE = re.compile(r"<!-- monitor-state (\{.*?\}) -->", re.DOTALL)

SPOT_TZ = ZoneInfo("America/Los_Angeles")  # reference spot's timezone

HERE = Path(__file__).resolve().parent
JOURNEYS = json.loads((HERE / "journeys.json").read_text())


def log(msg: str) -> None:
    print(f"[probe] {msg}", flush=True)


# ---------------- HTTP ----------------

def fetch(url: str, headers: dict | None = None, timeout: int = LATENCY_BUDGET_S):
    """Return (status, elapsed_s, body_bytes). Raises on network errors."""
    req = urllib.request.Request(url, headers={"User-Agent": "shaka-synthetic-monitor/2", **(headers or {})})
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, time.time() - start, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, time.time() - start, e.read()


def fetch_with_retry(url: str, headers: dict | None = None, timeout: int = LATENCY_BUDGET_S):
    last_exc = None
    for attempt in range(PER_CHECK_RETRIES + 1):
        try:
            return fetch(url, headers, timeout)
        except Exception as e:  # connect timeout, DNS, refused...
            last_exc = e
            if attempt < PER_CHECK_RETRIES:
                time.sleep(RETRY_BACKOFF_S)
    raise last_exc


# ---------------- Journey evaluation ----------------

class CheckResult:
    def __init__(self, check_id: str, name: str, ok: bool, detail: str = "",
                 immediate: bool = False, suppressed: bool = False):
        self.id, self.name, self.ok, self.detail = check_id, name, ok, detail
        self.immediate = immediate      # bypasses onset grace (hard down)
        self.suppressed = suppressed    # vantage-blocked: never counts toward streaks

    def line(self) -> str:
        mark = "PASS" if self.ok else ("SUPPRESSED" if self.suppressed else "FAIL")
        return f"{mark} {self.id} {self.name}" + (f": {self.detail}" if self.detail else "")


def spot_today() -> str:
    return datetime.now(SPOT_TZ).date().isoformat()


def render_path(path: str) -> str:
    return path.replace("{spot}", JOURNEYS["referenceSpot"]).replace("{today}", spot_today())


def eval_tier1(journey: dict, base_url: str, local: bool, flags: dict, saved: dict) -> CheckResult:
    jid, name = journey["id"], journey["name"]
    flag = journey.get("flag")
    if flag and not local and not flags.get(flag):
        return CheckResult(jid, name, True, f"skipped ({flag} not enabled yet)")

    url = base_url + render_path(journey["path"])
    try:
        status, elapsed, body = fetch_with_retry(url, journey.get("headers"))
    except Exception as e:
        return CheckResult(jid, name, False, f"unreachable: {type(e).__name__} {e}",
                           immediate=journey.get("pageImmediately", False))
    if status != 200:
        # Local contract mode: some journeys legitimately return an
        # empty-data status against the seeded-minimal DB; a distinctive
        # error body still proves the route is registered (Ktor's
        # unknown-route 404 has an empty body).
        acc = journey.get("localAccepts")
        if local and acc and status == acc["status"] and acc["bodyContains"].encode() in body:
            return CheckResult(jid, name, True, f"HTTP {status} accepted in local mode (empty data, route exists)")
        # A 503 from /health with db unreachable is the hard-down signal.
        immediate = journey.get("pageImmediately", False)
        return CheckResult(jid, name, False, f"HTTP {status}", immediate=immediate)
    if elapsed > LATENCY_BUDGET_S:
        return CheckResult(jid, name, False, f"latency {elapsed:.1f}s > {LATENCY_BUDGET_S}s")

    try:
        doc = json.loads(body)
    except Exception:
        return CheckResult(jid, name, False, "response is not JSON")
    saved[jid] = doc

    for key in journey.get("requiredKeys", []):
        if key not in doc:
            return CheckResult(jid, name, False, f"missing key '{key}'")
    for key, want in journey.get("requiredValues", {}).items():
        if doc.get(key) != want:
            return CheckResult(jid, name, False, f"{key}={doc.get(key)!r}, want {want!r}")
    for key, bad in journey.get("forbiddenValues", {}).items():
        if doc.get(key) == bad:
            causes = [c for c in doc.get("causes", []) if c.get("severity") == bad]
            return CheckResult(jid, name, False, f"{key}={bad!r}: {json.dumps(causes)[:400]}")

    if not local:
        for key in journey.get("prodOnly", {}).get("nonEmptyArrays", []):
            if not doc.get(key):
                return CheckResult(jid, name, False, f"'{key}' empty")
    if "hourlyDays" in journey:
        spec = journey["hourlyDays"]
        today = datetime.now(SPOT_TZ).date()
        want_dates = {"today": today.isoformat(), "tomorrow": (today + timedelta(days=1)).isoformat()}
        by_date = {d.get("localDate"): d for d in doc.get("days", [])}
        for label in spec["requireLocalDates"]:
            d = by_date.get(want_dates[label])
            if d is None:
                return CheckResult(jid, name, False, f"missing {label} ({want_dates[label]}) in days")
            pts = max(len(d.get("swell", [])), len(d.get("wind", [])))
            if pts < spec["minPointsPerDay"]:
                return CheckResult(jid, name, False, f"{label} has {pts} points < {spec['minPointsPerDay']}")
        anchor = journey.get("recencyAnchor")
        if anchor and (local or flags.get(anchor["flag"])):
            gen = doc.get(anchor["field"])
            if gen is None:
                return CheckResult(jid, name, False, f"missing recency anchor field '{anchor['field']}'")
            age_h = (time.time() * 1000 - gen) / 3_600_000
            if age_h > anchor["maxAgeHours"]:
                return CheckResult(jid, name, False,
                                   f"{anchor['field']} is {age_h:.1f}h old > {anchor['maxAgeHours']}h (probe-owned anchor)")
    if "tideDays" in journey:
        spec = journey["tideDays"]
        days = doc.get("days", [])
        if len(days) < spec["minDayCurves"]:
            return CheckResult(jid, name, False, f"{len(days)} day-curves < {spec['minDayCurves']}")
        thin = [d.get("localDate") for d in days if len(d.get("points", [])) < spec["minPointsPerDay"]]
        if thin:
            return CheckResult(jid, name, False, f"day-curves with <{spec['minPointsPerDay']} points: {thin}")

    return CheckResult(jid, name, True, f"{elapsed:.1f}s")


def eval_tier2(journey: dict, base_url: str, skip_external: bool, flags: dict, saved: dict) -> CheckResult | None:
    jid, name = journey["id"], journey["name"]
    flag = journey.get("flag")
    if flag and not flags.get(flag):
        return CheckResult(jid, name, True, f"skipped ({flag} not enabled yet)")

    if journey.get("reuseResponse"):
        doc = saved.get(journey["reuseResponse"])
        if doc is None:
            return CheckResult(jid, name, True, "skipped (source response unavailable)")
        empty = [k for k in journey.get("nonEmptyArrays", []) if not doc.get(k)]
        if empty:
            return CheckResult(jid, name, False, f"empty: {empty}")
        return CheckResult(jid, name, True)

    if journey.get("external"):
        if skip_external:
            return None
        url = journey["urlTemplate"].replace(
            "{date-2d}", (datetime.now(timezone.utc).date() - timedelta(days=2)).isoformat())
        try:
            status, _, body = fetch_with_retry(url, timeout=20)
        except Exception as e:
            if journey.get("vantageBlockedSuppression"):
                return CheckResult(jid, name, True, f"vantage-blocked (suppressed): {type(e).__name__}", suppressed=True)
            return CheckResult(jid, name, False, f"unreachable: {type(e).__name__}")
        if status in (403, 429) and journey.get("vantageBlockedSuppression"):
            return CheckResult(jid, name, True, f"vantage-blocked (suppressed): HTTP {status}", suppressed=True)
        if status != 200:
            return CheckResult(jid, name, False, f"HTTP {status}")
        for key, want in journey.get("requiredValues", {}).items():
            try:
                got = json.loads(body).get(key)
            except Exception:
                got = None
            if got != want:
                tolerated = journey.get("tolerated", {}).get(key)
                if got == tolerated:
                    return CheckResult(jid, name, True, f"{key}={got!r} (tolerated: warm-up)")
                return CheckResult(jid, name, False, f"{key}={got!r}, want {want!r}")
        return CheckResult(jid, name, True)

    # Backend-sourced tier-2 checks
    url = base_url + render_path(journey["path"])
    try:
        status, _, body = fetch_with_retry(url)
        doc = json.loads(body)
    except Exception as e:
        return CheckResult(jid, name, False, f"unreachable: {type(e).__name__}")
    if journey.get("relayDegradedCauses"):
        causes = [c for c in doc.get("causes", []) if c.get("severity") == "degraded"]
        if causes:
            detail = "; ".join(f"{c['check']}: {c['observed']}" for c in causes[:6])
            return CheckResult(jid, name, False, f"backend degraded — {detail}")
        return CheckResult(jid, name, True)
    if journey.get("upstreamStatuses"):
        bad = {k: v.get("status") for k, v in doc.get("services", {}).items()
               if k in journey["upstreamStatuses"] and v.get("status") != "ok"}
        if bad:
            return CheckResult(jid, name, False, f"upstreams not ok (Railway vantage): {bad}")
        return CheckResult(jid, name, True)
    return CheckResult(jid, name, True)


# ---------------- GitHub status issue state machine ----------------

def gh(*args: str, check: bool = True) -> str:
    proc = subprocess.run(["gh", *args], capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])}... failed: {proc.stderr.strip()[:300]}")
    return proc.stdout


def ensure_labels() -> None:
    for label, color in [(STATUS_LABEL, "ededed"), ("monitor:ok", "0e8a16"),
                         ("monitor:warning", "fbca04"), ("monitor:critical", "b60205")]:
        subprocess.run(["gh", "label", "create", label, "--color", color, "--force"],
                       capture_output=True, text=True)


def default_state() -> dict:
    return {"tier1": {"state": "unknown", "since": None, "consec_fail": 0, "consec_ok": 0, "escalated": []},
            "tier2": {}}


def find_status_issue() -> tuple[int | None, dict]:
    """Returns (issue_number, state). Missing/unparsable -> (number_or_None, unknown-state)."""
    out = gh("issue", "list", "--label", STATUS_LABEL, "--state", "open",
             "--json", "number,body", "--limit", "10")
    issues = json.loads(out or "[]")
    if not issues:
        return None, default_state()
    issues.sort(key=lambda i: i["number"], reverse=True)
    newest = issues[0]
    for stale in issues[1:]:  # multiple matching issues: newest wins, close the rest
        log(f"closing duplicate status issue #{stale['number']}")
        gh("issue", "close", str(stale["number"]), "--comment",
           f"Duplicate monitor status issue — #{newest['number']} is authoritative.", check=False)
    m = STATE_RE.search(newest.get("body") or "")
    if not m:
        log("status issue state block missing/unparsable -> state unknown (won't page until grace re-accumulates)")
        return newest["number"], default_state()
    try:
        return newest["number"], json.loads(m.group(1))
    except Exception:
        return newest["number"], default_state()


def build_body(state: dict, t1: list[CheckResult], t2: list[CheckResult], now_iso: str) -> str:
    s1 = state["tier1"]
    badge = {"ok": "🟢 OK", "critical": "🔴 CRITICAL", "unknown": "⚪ UNKNOWN"}.get(s1["state"], s1["state"])
    warn_ids = [cid for cid, n in state["tier2"].items() if n >= TIER2_SURFACE_RUNS]
    if s1["state"] == "ok" and warn_ids:
        badge = "🟠 OK with warnings"
    lines = [
        "# Production monitor status",
        "",
        f"**State:** {badge}  \n**Last checked:** {now_iso}",
    ]
    if s1["state"] == "critical" and s1.get("since"):
        started = datetime.fromtimestamp(s1["since"], tz=timezone.utc)
        dur = datetime.now(timezone.utc) - started
        lines.append(f"**Incident since:** {started.isoformat()} ({dur.days}d {dur.seconds // 3600}h)")
    lines += ["", "## Tier 1 — user journeys (paging)", ""]
    lines += [f"- {'✅' if r.ok else '❌'} **{r.id}** {r.name}" + (f" — {r.detail}" if (r.detail and not r.ok) else "")
              for r in t1]
    lines += ["", "## Tier 2 — drift (warn-only)", ""]
    for r in t2:
        icon = "⚠️" if (not r.ok and state["tier2"].get(r.id, 0) >= TIER2_SURFACE_RUNS) else \
               ("👁️" if not r.ok else ("🔇" if r.suppressed else "✅"))
        streak = f" (x{state['tier2'].get(r.id, 0)})" if not r.ok else ""
        lines.append(f"- {icon} **{r.id}** {r.name}{streak}" + (f" — {r.detail}" if r.detail else ""))
    lines += [
        "",
        "_Managed by `monitoring/probe.py` (docs/synthetic-monitor-design.md). Body is regenerated every run;",
        "routine updates are body-edits (no notifications). Comments are deliberate: incident onset re-escalation",
        "at 72h/7d and recovery only._",
        "",
        f"<!-- monitor-state {json.dumps(state)} -->",
    ]
    return "\n".join(lines)


def set_labels(issue: int, state_key: str) -> None:
    remove = [v for k, v in STATE_LABELS.items() if k != state_key]
    args = ["issue", "edit", str(issue), "--add-label", STATE_LABELS.get(state_key, "monitor:ok")]
    for lbl in remove:
        args += ["--remove-label", lbl]
    gh(*args, check=False)


# ---------------- Sentry Cron check-in (dead-man's switch) ----------------

def sentry_checkin(ok: bool) -> None:
    import os
    url = os.environ.get("SENTRY_CRON_CHECKIN_URL", "").strip()
    if not url:
        log("SENTRY_CRON_CHECKIN_URL not set — skipping check-in (dead-man's switch inactive!)")
        return
    sep = "&" if "?" in url else "?"
    try:
        fetch(f"{url}{sep}status={'ok' if ok else 'error'}", timeout=10)
        log("sentry cron check-in sent")
    except Exception as e:
        log(f"sentry check-in failed (non-fatal): {e}")


# ---------------- Main ----------------

def main() -> int:
    import os
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", action="store_true", help="CI contract mode (seeded localhost, no GitHub/Sentry)")
    ap.add_argument("--base-url", default=JOURNEYS["baseUrlProd"])
    ap.add_argument("--skip-external", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="no GitHub writes")
    ap.add_argument("--force-notify", action="store_true", help="inject synthetic critical to test the paging path")
    args = ap.parse_args()

    flags = {
        "PROBE_ENABLE_T8": os.environ.get("PROBE_ENABLE_T8", "").lower() == "true",
        "PROBE_ENABLE_T4_ANCHOR": os.environ.get("PROBE_ENABLE_T4_ANCHOR", "").lower() == "true",
    }

    saved: dict = {}
    t1 = [eval_tier1(j, args.base_url, args.local, flags, saved) for j in JOURNEYS["tier1"]]
    t2 = [r for j in JOURNEYS["tier2"]
          if (r := eval_tier2(j, args.base_url, args.skip_external or args.local, flags, saved)) is not None]

    if args.force_notify:
        t1.append(CheckResult("T0", "forced paging-path test (--force-notify)", False,
                              "synthetic failure — recovery expected within ~3 runs", immediate=True))

    for r in t1 + t2:
        log(r.line())

    t1_failed = [r for r in t1 if not r.ok]
    ok_overall = not t1_failed

    # ----- CI contract mode: fail the PR directly, no state machine -----
    if args.local:
        if t1_failed:
            log(f"CONTRACT FAILURES: {[r.id for r in t1_failed]}")
            return 1
        log("all contract checks passed")
        return 0

    # ----- Production: state machine -----
    exit_code = 0
    if args.dry_run:
        log(f"dry-run: tier1_failed={[r.id for r in t1_failed]} "
            f"tier2_failed={[r.id for r in t2 if not r.ok and not r.suppressed]}")
        sentry_checkin(ok_overall)
        return 0

    try:
        ensure_labels()
        issue, state = find_status_issue()
        s1 = state["tier1"]
        now = datetime.now(timezone.utc)
        now_ts = int(now.timestamp())

        # Update counters
        if t1_failed:
            s1["consec_fail"] = s1.get("consec_fail", 0) + 1
            s1["consec_ok"] = 0
        else:
            s1["consec_ok"] = s1.get("consec_ok", 0) + 1
            s1["consec_fail"] = 0
        for r in t2:
            if r.suppressed:
                continue
            state["tier2"][r.id] = 0 if r.ok else state["tier2"].get(r.id, 0) + 1

        immediate = any(r.immediate for r in t1_failed)
        prev = s1.get("state", "unknown")
        comment: str | None = None

        if t1_failed and (s1["consec_fail"] >= TIER1_ONSET_RUNS or (immediate and prev != "unknown")):
            if prev != "critical":
                # NEW incident: the exit-1 workflow failure email is the notification.
                s1["state"] = "critical"
                s1["since"] = now_ts
                s1["escalated"] = []
                exit_code = 1
                log(f"NEW CRITICAL incident: {[r.id for r in t1_failed]} -> exit 1 (one email)")
            else:
                # Ongoing: body-edit only. Bounded re-escalation comments at 72h/7d.
                elapsed = now_ts - (s1.get("since") or now_ts)
                for i, after in enumerate(REESCALATE_AFTER):
                    tag = ["72h", "7d"][i]
                    if elapsed >= after and tag not in s1.get("escalated", []):
                        s1.setdefault("escalated", []).append(tag)
                        days = elapsed // 86400
                        comment = (f"⏰ **Still critical after {tag}** (day {days}). "
                                   f"Failing: {', '.join(r.id for r in t1_failed)}. "
                                   f"Latest: {t1_failed[0].detail[:200]}")
                        break
        elif prev == "critical" and s1["consec_ok"] >= RECOVERY_RUNS:
            dur = now_ts - (s1.get("since") or now_ts)
            comment = f"✅ **Recovered** after {dur // 3600}h {(dur % 3600) // 60}m ({RECOVERY_RUNS} consecutive green runs)."
            s1["state"] = "ok"
            s1["since"] = None
            s1["escalated"] = []
            log("recovery confirmed")
        elif prev in ("unknown",) and not t1_failed and s1["consec_ok"] >= 1:
            s1["state"] = "ok"
        elif prev == "ok" or (prev == "unknown" and not t1_failed):
            s1["state"] = "ok" if not t1_failed else prev
        # (failing but within onset grace: state unchanged — no page, counters accumulate)

        body = build_body(state, t1, t2, now.isoformat())
        if issue is None:
            out = gh("issue", "create", "--title", "Production monitor status",
                     "--label", STATUS_LABEL, "--body", body)
            m = re.search(r"/issues/(\d+)", out)
            issue = int(m.group(1)) if m else None
            log(f"created status issue #{issue}")
            if issue:
                subprocess.run(["gh", "issue", "pin", str(issue)], capture_output=True, text=True)
        else:
            gh("issue", "edit", str(issue), "--body", body)

        if issue:
            warn = any(n >= TIER2_SURFACE_RUNS for n in state["tier2"].values())
            set_labels(issue, "critical" if s1["state"] == "critical" else ("warning" if warn else "ok"))
            if comment:
                gh("issue", "comment", str(issue), "--body", comment)
    except Exception as e:
        # State-machine plumbing failing must not mask a healthy/unhealthy backend;
        # log loudly, still send the heartbeat, and never exit 1 for plumbing.
        log(f"STATE-MACHINE ERROR (plumbing, not production): {type(e).__name__}: {e}")

    sentry_checkin(ok_overall)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
