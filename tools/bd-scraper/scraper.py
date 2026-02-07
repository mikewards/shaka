#!/usr/bin/env python3
"""
BD Outdoors Forum Scraper for Shaka Fishing Intel

Runs locally on your Mac to bypass Cloudflare protection.
Reads Firefox cookies from your logged-in session.

Prerequisites:
1. Firefox installed
2. Logged into BD Outdoors in Firefox (check "Stay logged in")
3. Close Firefox before running (or cookies may be locked)

Usage:
    python scraper.py                    # Normal run
    python scraper.py --dry-run          # Parse but don't send to API
    python scraper.py --max-threads 5    # Limit threads per forum

If Firefox clears cookies on exit, use manual cookies instead:
    1. Log in at https://www.bdoutdoors.com/forums/ (keep Firefox open).
    2. DevTools → Application → Cookies → https://www.bdoutdoors.com
       Copy each cookie as name=value and paste into one line separated by "; "
       e.g. bdo_user=123; bdo_session=abc; cf_clearance=xyz
    3. Either:
       export BDO_COOKIES='bdo_user=...; bdo_session=...; ...'
       or put the same string in a file: tools/bd-scraper/.cookies
    4. Run: python scraper.py
"""

import argparse
import os
import re
import sys
import time
import json
import requests
from datetime import datetime, timezone
from typing import List, Dict, Optional, Set

try:
    import browser_cookie3
    from bs4 import BeautifulSoup
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)


# =============================================================================
# CONFIGURATION
# =============================================================================

API_URL = "https://shaka-production.up.railway.app/v1/intel/ingest"
BASE_URL = "https://www.bdoutdoors.com"

# SoCal fishing forums (paths updated for current BD Outdoors structure)
FORUMS = [
    "/forums/forum/southern-california-offshore-fishing-reports/",
    "/forums/forum/southern-california-sportboats/",
]

# Delays (be polite to servers)
REQUEST_DELAY = 2.0  # seconds between thread requests
FORUM_DELAY = 5.0    # seconds between forums

# Only ingest posts from the last N days
MAX_AGE_DAYS = 7


# =============================================================================
# SPECIES PATTERNS (regex -> normalized name)
# =============================================================================

SPECIES_PATTERNS = {
    # Tuna
    r'\b(bluefin)\s*(tuna)?\b': 'bluefin_tuna',
    r'\b(yellowfin)\s*(tuna)?\b': 'yellowfin_tuna',
    r'\b(bigeye)\s*(tuna)?\b': 'bigeye_tuna',
    r'\b(albacore)\b': 'albacore',
    r'\b(skipjack)\b': 'skipjack',
    
    # Pelagics
    r'\b(yellowtail)\b': 'yellowtail',
    r'\b(dorado|mahi[\s-]?mahi|mahi|dolphin\s*fish)\b': 'dorado',
    r'\b(wahoo)\b': 'wahoo',
    r'\b(bonito)\b': 'bonito',
    r'\b(barracuda|cuda)\b': 'barracuda',
    r'\b(marlin)\b': 'marlin',
    r'\b(swordfish)\b': 'swordfish',
    
    # White Seabass
    r'\b(white\s*sea\s*bass|wsb|seabass|sea\s*bass)\b': 'white_seabass',
    
    # Bass
    r'\b(calico|kelp\s*bass)\b': 'calico_bass',
    r'\b(sand\s*bass|barred\s*sand\s*bass)\b': 'sand_bass',
    r'\b(spotted\s*bay\s*bass)\b': 'spotted_bay_bass',
    
    # Bottom Fish
    r'\b(halibut)\b': 'halibut',
    r'\b(lingcod|ling\s*cod|ling)\b': 'lingcod',
    r'\b(rock\s*fish|rockfish|rok\s*fish|reds|vermilion|copper)\b': 'rockfish',
    r'\b(sheephead|sheep\s*head)\b': 'sheephead',
    r'\b(sculpin|scorpion\s*fish)\b': 'sculpin',
    r'\b(cabezon)\b': 'cabezon',
    r'\b(white\s*fish|whitefish)\b': 'whitefish',
    
    # Other
    r'\b(lobster)\b': 'lobster',
    r'\b(thresher)\s*(shark)?\b': 'thresher_shark',
    r'\b(opah)\b': 'opah',
}


# =============================================================================
# LOCATION PATTERNS (regex -> display name)
# =============================================================================

LOCATION_PATTERNS = {
    # San Diego
    r'\b(point\s*loma|pt\.?\s*loma)\b': 'Point Loma',
    r'\b(la\s*jolla)\b': 'La Jolla',
    r'\b(mission\s*bay)\b': 'Mission Bay',
    r'\b(coronado)\b': 'Coronado',
    r'\b(san\s*diego)\b': 'San Diego',
    r'\b(oceanside)\b': 'Oceanside',
    
    # Orange County
    r'\b(dana\s*point)\b': 'Dana Point',
    r'\b(newport|newport\s*beach)\b': 'Newport Beach',
    r'\b(huntington)\b': 'Huntington Beach',
    
    # LA
    r'\b(long\s*beach)\b': 'Long Beach',
    r'\b(san\s*pedro)\b': 'San Pedro',
    r'\b(redondo)\b': 'Redondo Beach',
    r'\b(marina\s*del\s*rey)\b': 'Marina del Rey',
    
    # Islands
    r'\b(catalina|santa\s*catalina)\b': 'Catalina Island',
    r'\b(san\s*clemente\s*island|sci)\b': 'San Clemente Island',
    r'\b(santa\s*barbara\s*island)\b': 'Santa Barbara Island',
    
    # Offshore
    r'\b(9[\s-]?mile|nine\s*mile)\b': '9-Mile Bank',
    r'\b(43[\s-]?fathom)\b': '43-Fathom Spot',
    r'\b(302|three\s*oh\s*two)\b': '302',
    r'\b(tanner\s*bank|tanner)\b': 'Tanner Bank',
    r'\b(cortes\s*bank|cortes)\b': 'Cortes Bank',
    r'\b(hidden\s*bank)\b': 'Hidden Bank',
    
    # Mexico
    r'\b(ensenada)\b': 'Ensenada',
    r'\b(colonet)\b': 'Colonet',
}


# =============================================================================
# FUNCTIONS
# =============================================================================

def _parse_cookie_string(s: str) -> dict:
    """Parse 'name=value; name2=value2' into a cookie dict."""
    out = {}
    for part in s.split(";"):
        part = part.strip()
        if not part:
            continue
        eq = part.find("=")
        if eq >= 0:
            out[part[:eq].strip()] = part[eq + 1 :].strip()
    return out


def get_manual_cookies() -> Optional[dict]:
    """Load cookies from BDO_COOKIES env or .cookies file (for when Firefox clears on exit)."""
    raw = os.environ.get("BDO_COOKIES", "").strip()
    if not raw:
        cookie_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cookies")
        if os.path.isfile(cookie_file):
            with open(cookie_file, "r") as f:
                raw = f.read().strip()
    if not raw:
        return None
    cookies = _parse_cookie_string(raw)
    if not cookies:
        return None
    print(f"[+] Loaded {len(cookies)} cookies from BDO_COOKIES / .cookies")
    required = ["bdo_user", "bdo_session"]
    missing = [c for c in required if c not in cookies]
    if missing:
        print(f"[!] Warning: Missing cookies: {missing}")
    return cookies


def get_firefox_cookies() -> dict:
    """Load cookies from Firefox for bdoutdoors.com"""
    try:
        cj = browser_cookie3.firefox(domain_name='.bdoutdoors.com')
        cookies = {c.name: c.value for c in cj}
        print(f"[+] Loaded {len(cookies)} cookies from Firefox")
        
        required = ['bdo_user', 'bdo_session']
        missing = [c for c in required if c not in cookies]
        if missing:
            print(f"[!] Warning: Missing cookies: {missing}")
            print("    Login to BD Outdoors in Firefox and check 'Stay logged in'")
        
        return cookies
    except browser_cookie3.BrowserCookieError as e:
        print(f"[-] Firefox cookie error: {e}")
        print("    Close Firefox completely and try again")
        return {}
    except Exception as e:
        print(f"[-] Error loading cookies: {e}")
        return {}


def parse_last_activity_from_struct_item(item) -> Optional[str]:
    """Extract last-activity ISO (UTC with Z) from a forum list structItem row, or None."""
    # XenForo: last post date is often in structItem-cell--latest
    latest_cell = item.select_one(".structItem-cell--latest")
    if latest_cell:
        time_el = latest_cell.select_one("time.u-dt") or latest_cell.select_one("time")
        if time_el:
            raw = parse_xenforo_date(time_el)
            if raw:
                dt = parse_date_to_utc(raw)
                if dt:
                    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    # Fallback: last time in the row (often last post)
    times = item.select("time.u-dt")
    if len(times) >= 2:
        raw = parse_xenforo_date(times[-1])
        if raw:
            dt = parse_date_to_utc(raw)
            if dt:
                return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    return None


def normalize_thread_url(href: str) -> str:
    """Strip query, fragment, /vote, /page-N so we request the main thread page."""
    url = href.split("?")[0].split("#")[0].rstrip("/")
    url = re.sub(r"/vote$", "", url)
    url = re.sub(r"/page-\d+.*$", "", url).rstrip("/")
    return url or href


def get_cookies() -> dict:
    """Get cookies: try manual (env/file) first, then Firefox."""
    cookies = get_manual_cookies()
    if cookies:
        return cookies
    return get_firefox_cookies()


def extract_species(text: str) -> List[str]:
    """Extract normalized species names from text"""
    text_lower = text.lower()
    found: Set[str] = set()
    for pattern, species in SPECIES_PATTERNS.items():
        if re.search(pattern, text_lower, re.IGNORECASE):
            found.add(species)
    return list(found)


def extract_location(text: str) -> Optional[str]:
    """Extract first matching location from text"""
    text_lower = text.lower()
    for pattern, location in LOCATION_PATTERNS.items():
        if re.search(pattern, text_lower, re.IGNORECASE):
            return location
    return None


def parse_xenforo_date(time_el) -> Optional[str]:
    """Parse date from XenForo time element. Returns None if no datetime/data-time (never return 'now')."""
    if time_el:
        dt = time_el.get('datetime')
        if dt:
            return dt
        data_time = time_el.get('data-time')
        if data_time:
            try:
                ts = int(data_time)
                return datetime.fromtimestamp(ts, tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
            except ValueError:
                pass
    return None


def parse_date_to_utc(s: str) -> Optional[datetime]:
    """Parse ISO or timestamp string to UTC datetime. Returns None if invalid."""
    if not s:
        return None
    try:
        if s.isdigit():
            return datetime.fromtimestamp(int(s), tz=timezone.utc)
        # Normalize offset to HH:MM so fromisoformat accepts -0800 or -08:00
        s = re.sub(r"([+-])(\d{2})(\d{2})$", r"\1\2:\3", s.strip())
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def is_older_than_days(date_str: str, days: int) -> bool:
    """True if the given date string is older than `days` from now."""
    dt = parse_date_to_utc(date_str)
    if dt is None:
        return False  # keep if we can't parse
    return (datetime.now(timezone.utc) - dt).days > days


def infer_content_type(title: str) -> str:
    """Infer contentType from thread title (region-agnostic)."""
    t = title.lower()
    if "?" in title or any(
        p in t for p in ("anyone know", "any one know", "are they still", "any reports", "any one")
    ):
        return "question"
    if re.search(r"\d{1,2}[/\-]\d{1,2}", title) or re.search(r"\d{4}-\d{2}-\d{2}", title):
        return "trip_report"
    return "discussion"


def _post_id_from_article(article_el) -> Optional[str]:
    """Get XenForo post id from article (id='post-12345', id='js-post-12345', or data-content='post-12345')."""
    aid = (article_el.get("id") or "").strip()
    if aid.startswith("js-post-"):
        return aid.replace("js-post-", "", 1)
    if aid.startswith("post-"):
        return aid.replace("post-", "", 1)
    dc = (article_el.get("data-content") or "").strip()
    if dc.startswith("post-"):
        return dc.replace("post-", "", 1)
    return None


def scrape_thread(
    session: requests.Session,
    url: str,
    forum_name: str,
    thread_zone: Optional[str] = None,
    max_age_days: Optional[int] = None,
    allow_no_species: bool = False,
    debug: bool = False,
    last_activity_iso: Optional[str] = None,
    max_replies_per_thread: int = 50,
) -> List[Dict]:
    """Scrape a thread: first post (thread starter) plus replies. Returns list of payloads."""
    def skip(reason: str) -> List[Dict]:
        if debug:
            print(f"        skip: {reason}")
        return []
    cutoff_days = max_age_days if max_age_days is not None else MAX_AGE_DAYS
    thread_url_base = url.split("#")[0].rstrip("/")
    try:
        resp = session.get(url, timeout=30)
        if resp.status_code != 200:
            return skip(f"HTTP {resp.status_code}")
        soup = BeautifulSoup(resp.text, "html.parser")
        title_el = soup.select_one("h1.p-title-value") or soup.select_one(".p-title-value")
        title = title_el.get_text(strip=True) if title_el else "Unknown"
        post_els = soup.select("article.message--post") or soup.select(".message--post")
        if not post_els:
            return skip("no post elements")
        out: List[Dict] = []
        # ---- Thread starter (first post) ----
        post_el = post_els[0]
        author_el = post_el.select_one("a.username") or post_el.select_one(".message-name a")
        author = author_el.get_text(strip=True) if author_el else "Unknown"
        time_el = post_el.select_one("time.u-dt") or post_el.select_one("time")
        date_str = parse_xenforo_date(time_el)
        if date_str is None:
            return skip("no date")
        dt_utc = parse_date_to_utc(date_str)
        if dt_utc is None:
            return skip("unparseable date")
        cutoff_date_str = last_activity_iso if last_activity_iso else date_str
        if is_older_than_days(cutoff_date_str, cutoff_days):
            return skip(f"older than {cutoff_days}d: {cutoff_date_str[:19]}")
        content_el = post_el.select_one(".message-body .bbWrapper") or post_el.select_one(".bbWrapper")
        content = content_el.get_text(separator=" ", strip=True) if content_el else ""
        if not content or len(content) < 20:
            return skip(f"content too short ({len(content) if content else 0} chars)")
        full_text = f"{title} {content}"
        species = extract_species(full_text)
        location = extract_location(full_text)
        if not species and not allow_no_species:
            return skip("no species")
        date_for_api = dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        out.append({
            "threadUrl": url,
            "title": title[:200],
            "author": author,
            "date": date_for_api,
            "content": content[:2000],
            "speciesMentioned": species,
            "locationMentioned": location,
            "forumName": forum_name,
            "threadZone": thread_zone,
            "postRole": "thread_starter",
            "contentType": infer_content_type(title),
            "lastActivityAt": last_activity_iso if last_activity_iso else date_for_api,
        })
        # ---- Replies (posts 2..n, capped) ----
        for post_el in post_els[1:max_replies_per_thread + 1]:
            post_id = _post_id_from_article(post_el)
            if not post_id:
                continue
            post_url = f"{thread_url_base}#post-{post_id}"
            author_el = post_el.select_one("a.username") or post_el.select_one(".message-name a")
            reply_author = author_el.get_text(strip=True) if author_el else "Unknown"
            time_el = post_el.select_one("time.u-dt") or post_el.select_one("time")
            reply_date_str = parse_xenforo_date(time_el)
            if reply_date_str is None:
                continue
            reply_dt = parse_date_to_utc(reply_date_str)
            if reply_dt is None or is_older_than_days(reply_date_str, cutoff_days):
                continue
            content_el = post_el.select_one(".message-body .bbWrapper") or post_el.select_one(".bbWrapper")
            reply_content = content_el.get_text(separator=" ", strip=True) if content_el else ""
            if not reply_content or len(reply_content) < 20:
                continue
            reply_full = f"{title} {reply_content}"
            reply_species = extract_species(reply_full)
            reply_location = extract_location(reply_full)
            if not reply_species and not allow_no_species:
                continue
            reply_date_api = reply_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
            out.append({
                "threadUrl": url,
                "title": title[:200],
                "author": reply_author,
                "date": reply_date_api,
                "content": reply_content[:2000],
                "speciesMentioned": reply_species,
                "locationMentioned": reply_location,
                "forumName": forum_name,
                "threadZone": thread_zone,
                "postRole": "reply",
                "postUrl": post_url,
                "contentType": "reply",
                "lastActivityAt": reply_date_api,
            })
        return out
    except requests.Timeout:
        if debug:
            print("        skip: timeout")
        return []
    except Exception as e:
        if debug:
            print(f"        skip: {e}")
        return []


def scrape_forum(
    session: requests.Session,
    forum_path: str,
    max_threads: int,
    max_age_days: Optional[int] = None,
    allow_no_species: bool = False,
    debug: bool = False,
    max_replies_per_thread: int = 50,
) -> List[Dict]:
    """Scrape threads from a forum"""
    posts = []
    url = BASE_URL + forum_path
    forum_name = "SoCal Sportboats" if "sportboat" in forum_path.lower() else "SoCal Fishing Reports"
    
    print(f"\n[*] Scraping: {forum_name}")
    print(f"    URL: {url}")
    
    try:
        resp = session.get(url, timeout=30)
        if resp.status_code == 403:
            print(f"    [-] HTTP 403 - Cloudflare blocking")
            print(f"        Refresh BD Outdoors in Firefox and try again")
            return posts
        if resp.status_code != 200:
            print(f"    [-] HTTP {resp.status_code}")
            return posts
        
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        # Check for Cloudflare challenge
        if 'cf-browser-verification' in resp.text or 'Just a moment' in soup.get_text():
            print(f"    [-] Cloudflare challenge detected")
            print(f"        Open BD Outdoors in Firefox, solve captcha, try again")
            return posts
        
        # Only actual thread pages (slug.id), not list pages like /threads/trending
        thread_page_pattern = re.compile(r"/threads/[^/]+\.\d+")
        seen_urls = set()
        thread_list: List[tuple] = []  # (url, zone, last_activity_iso)
        # Prefer structItem rows so we can get zone and last-activity per thread
        struct_items = soup.select("div.structItem")
        if struct_items:
            for item in struct_items:
                links = item.select('a[href*="/threads/"]')
                zone = None
                for a in item.select('a[href*="prefix_id"]'):
                    zone = a.get_text(strip=True)
                    break
                last_activity = parse_last_activity_from_struct_item(item)
                for link in links:
                    href = link.get('href', '')
                    if not href.startswith('http'):
                        href = BASE_URL + href
                    href = normalize_thread_url(href)
                    if thread_page_pattern.search(href) and href not in seen_urls:
                        seen_urls.add(href)
                        thread_list.append((href, zone, last_activity))
                        break
        if not thread_list:
            thread_links = soup.select('a[href*="/threads/"]')
            for link in thread_links:
                href = link.get('href', '')
                if '/threads/' not in href:
                    continue
                if not href.startswith('http'):
                    href = BASE_URL + href
                href = normalize_thread_url(href)
                if thread_page_pattern.search(href) and href not in seen_urls:
                    seen_urls.add(href)
                    thread_list.append((href, None, None))
        
        thread_list = thread_list[:max_threads]
        print(f"    [+] Found {len(thread_list)} threads")
        
        for i, (thread_url, thread_zone, last_activity_iso) in enumerate(thread_list, 1):
            time.sleep(REQUEST_DELAY)
            print(f"    [{i}/{len(thread_list)}] Scraping...")
            thread_posts = scrape_thread(
                session, thread_url, forum_name, thread_zone, max_age_days,
                allow_no_species, debug, last_activity_iso, max_replies_per_thread
            )
            for post in thread_posts:
                species_str = ", ".join(post["speciesMentioned"][:3]) if post["speciesMentioned"] else "(no species)"
                role = post.get("postRole", "thread_starter")
                print(f"        + [{role}] {post['title'][:36]}... [{species_str}]")
                posts.append(post)
    
    except requests.Timeout:
        print(f"    [-] Timeout loading forum")
    except Exception as e:
        print(f"    [-] Error: {e}")
    
    return posts


def clear_bd_outdoors() -> bool:
    """Ask API to delete all bd-outdoors reports (clean slate before re-ingest)."""
    try:
        resp = requests.post(
            API_URL + "?clearSource=bd-outdoors",
            json=[],
            headers={"Content-Type": "application/json"},
            timeout=30,
        )
        if resp.status_code == 200:
            print("[*] Cleared existing bd-outdoors data")
            return True
        print(f"    [-] Clear failed: {resp.status_code} {resp.text[:150]}")
        return False
    except Exception as e:
        print(f"    [-] Clear error: {e}")
        return False


def send_to_api(posts: List[Dict], dry_run: bool = False, clear_bd_first: bool = False) -> bool:
    """Send scraped posts to Shaka API"""
    if clear_bd_first and not dry_run:
        if not clear_bd_outdoors():
            return False
    if clear_bd_first and dry_run:
        print("[*] Would clear bd-outdoors data first")
    if not posts:
        print("\n[*] No posts to send")
        return True
    
    if dry_run:
        print(f"\n[*] DRY RUN: Would send {len(posts)} posts")
        print(f"    Species: {set(s for p in posts for s in p['speciesMentioned'])}")
        return True
    
    print(f"\n[*] Sending {len(posts)} posts to API...")
    
    try:
        resp = requests.post(
            API_URL,
            json=posts,
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        if resp.status_code == 200:
            result = resp.json()
            print(f"    [+] Success!")
            print(f"        Saved: {result.get('saved', 0)}")
            print(f"        Skipped: {result.get('skipped', 0)}")
            if result.get('errors'):
                print(f"        Errors: {len(result['errors'])}")
            return True
        else:
            print(f"    [-] API error: {resp.status_code}")
            print(f"        {resp.text[:200]}")
            return False
    except Exception as e:
        print(f"    [-] Error: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='BD Outdoors Scraper for Shaka')
    parser.add_argument('--dry-run', action='store_true', help='Parse only, no API calls')
    parser.add_argument('--max-threads', type=int, default=10, help='Max threads per forum')
    parser.add_argument('--max-age-days', type=int, default=7, help='Skip posts older than N days (default 7)')
    parser.add_argument('--max-replies-per-thread', type=int, default=50, help='Max reply posts to scrape per thread (default 50)')
    parser.add_argument('--allow-no-species', action='store_true', help='Include posts with no species match (for DB populate)')
    parser.add_argument('--clear-bd-first', action='store_true', help='Delete all bd-outdoors reports before ingesting (clean slate)')
    parser.add_argument('--debug', action='store_true', help='Print why threads are skipped')
    args = parser.parse_args()
    if args.max_age_days != 7:
        print(f"[*] Using max age: {args.max_age_days} days")
    if args.allow_no_species:
        print("[*] Including posts with no species match")
    
    print("=" * 60)
    print("BD Outdoors Scraper for Shaka")
    print("=" * 60)
    
    cookies = get_cookies()
    if not cookies:
        print("\n[-] No cookies.")
        print("    Use BDO_COOKIES or a .cookies file (see docstring), or log in with Firefox and try again.")
        sys.exit(1)
    
    session = requests.Session()
    session.cookies.update(cookies)
    session.headers.update({
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
    })
    
    all_posts = []
    for forum in FORUMS:
        posts = scrape_forum(session, forum, args.max_threads, args.max_age_days, args.allow_no_species, args.debug, args.max_replies_per_thread)
        all_posts.extend(posts)
        if forum != FORUMS[-1]:
            print(f"\n[*] Waiting {FORUM_DELAY}s...")
            time.sleep(FORUM_DELAY)
    
    print("\n" + "=" * 60)
    print(f"Total: {len(all_posts)} posts")
    if all_posts:
        species = set(s for p in all_posts for s in p['speciesMentioned'])
        print(f"Species: {', '.join(sorted(species))}")
    
    send_to_api(all_posts, dry_run=args.dry_run, clear_bd_first=args.clear_bd_first)
    print("\n[*] Done!")


if __name__ == "__main__":
    main()
