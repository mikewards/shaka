# Elevate the Best Thread Intel — Step-by-Step Plan

**For the executing agent:** Do every step in order. Use the exact file paths below. The repo root is `/Users/ed/Desktop/shaka`. If your repo is elsewhere, replace that prefix in every path.

---

# PART 1: FULL REQUIREMENTS (read once before starting)

## What we are building

- **One output per thread:** A short summary (TL;DR) per BD thread that says what was caught, where, and when/conditions. Stored once per thread on the thread-starter report only. Replies do not get their own TL;DR.
- **Relevance flag:** When AI runs, it also returns `is_catch_intel` (true = thread is mostly catch/conditions intel; false = mostly off-topic). We store it and use it when ranking so we do not elevate "tackle shop + aliens" type threads.
- **Ranking:** Score every thread by timeliness + interest + relevance. Sort by score descending. Show only the top 1–3 (elevated). Many threads are not elevated.
- **No "Yellowtail at Inshore":** Inshore/Offshore/Islands/Bay/Harbor are tags, not places. Headline and card location must use only real places (gazetteer) or species only when there is no place.
- **App:** Card shows TL;DR as the main content. When TL;DR is present, do not show the excerpt. "Original thread" is a small link, not a big button. Do not push the user to BD (remove or footnote "May require BD Outdoors login").

## Why AI is required (not optional for quality)

- We have had bugs where "bluefin as chum" or "used for bait" was parsed as "catching bluefin." Rule-based logic cannot reliably separate caught vs chum/bait/freezer/past trip.
- "Is this thread mostly catch intel or off-topic?" (e.g. tackle shop with no report, aliens) cannot be codified with keywords; AI returns `is_catch_intel` so we don’t elevate those.

## AI prompt requirements (thread-level)

- **Input:** Thread title (string) + combined content of all posts in the thread (single string, truncate to 4000 chars).
- **Output:** JSON only, no markdown, with exactly these keys:
  - `species_caught`: array of species actually caught on this trip (normalized with underscores, e.g. bluefin_tuna, yellowtail). Do NOT include species only mentioned as chum, bait, from the freezer, or from a past trip.
  - `tldr`: one or two sentences summarizing what was caught, where, and conditions if relevant. Standalone; no "read more" or links. Factual, angler-friendly tone.
  - `is_catch_intel`: boolean. true if the thread is mostly actual catch reports or conditions intel; false if mostly off-topic (e.g. general chat, tackle shop visit with no report, non-fishing).
- **Model:** gpt-4o-mini or equivalent. Same HTTP pattern as existing `analyzePost` (OPENAI_URL, Bearer token from OPENAI_API_KEY). Enabled only when FISHING_INTEL_AI_ENABLED=true and OPENAI_API_KEY is set.

## Scoring formula (for ranking)

- **Timeliness:** Use report.publishedAt or report.lastActivityAt vs now. Last 24h = 30 points, last 3 days = 15 points, last 7 days = 5 points. Older = 0.
- **Interest:** +10 for each trophy species in report.claims (SpeciesTier.TROPHY_SPECIES). +15 if SoCalGazetteer.findInText(report.rawExcerpt + report.title) is non-empty (specific place). +5 if tldr or rawExcerpt contains any of: "tonight", "tomorrow", "8pm", "at dawn", "this evening".
- **Relevance:** If report.isCatchIntel != null: if false, return total score 0 (do not elevate). If true, no change. If isCatchIntel == null (no AI), apply a simple penalty if tldr or rawExcerpt contains "alien" or "tackle shop" without "caught" or "limit" in the same text (e.g. subtract 50 or set to 0).
- **Final:** One number per thread. Sort threads by this score descending. Take top 3. Optional: drop threads with score below 5.

## Success criteria (all must be true when done)

- Running the BD scraper with `--clear-bd-first` returns HTTP 200 with `saved` > 0. In the database, thread-starter reports have `tldr` populated and (when AI is on) `is_catch_intel` set.
- GET /v1/intel/spot/{spotId} returns `narrativeInsights` sorted by score (best first). The `headline.message` never contains "at Inshore" (or any zone as the location); it is either "Species at Place" (real place) or "Species" only.
- In the Shaka app, the narrative card shows the TL;DR as the main text; when TL;DR is non-empty the excerpt is not shown. "Original thread" is a small, de-emphasized link. The line "May require BD Outdoors login" is removed or moved to a single footnote.

## Runbook (execute after all code steps)

1. **Railway env vars:** In Railway → your API service → Variables, set:
   - `DATABASE_URL` (required, usually auto-set)
   - `FISHING_INTEL_AI_ENABLED` = `true`
   - **Groq (recommended, free tier):** `FISHING_INTEL_AI_API_KEY` = your key from https://console.groq.com (API Keys). Optional: `FISHING_INTEL_AI_API_URL` = `https://api.groq.com/openai/v1/chat/completions`, `FISHING_INTEL_AI_MODEL` = `llama-3.3-70b-versatile` (these are the defaults when using FISHING_INTEL_AI_API_KEY).
   - **Or OpenAI:** `OPENAI_API_KEY` = your key from https://platform.openai.com (API keys). Optional: `FISHING_INTEL_AI_API_URL` = `https://api.openai.com/v1/chat/completions`, `FISHING_INTEL_AI_MODEL` = `gpt-4o-mini`.
2. **Build API:** In terminal run: `cd /Users/ed/Desktop/shaka/shaka-api && ./gradlew shadowJar`
3. **Deploy:** `cd /Users/ed/Desktop/shaka && git add -A && git commit -m "Elevate best thread intel" && git push origin main`. Railway will build from the repo root Dockerfile and deploy.
4. **Scraper:** `cd /Users/ed/Desktop/shaka/tools/bd-scraper && .venv/bin/python scraper.py --clear-bd-first`. Ensure BD cookies: either log in via Firefox and close it, or set BDO_COOKIES or put cookies in `/Users/ed/Desktop/shaka/tools/bd-scraper/.cookies`. API URL is hardcoded in scraper: https://shaka-production.up.railway.app/v1/intel/ingest
5. **App:** `cd /Users/ed/Desktop/shaka/shaka-app && flutter build ios --release && flutter install -d iPhone`
6. **Verify:** Open the app on the device, go to a SoCal spot, open the fishing/reports section. You must see 1–3 narrative cards with thread-level TL;DR, no excerpt when TL;DR is present, small "View original thread" link, and no "at Inshore" in the headline.

## Do not modify

- **Scraper:** Do not change `/Users/ed/Desktop/shaka/tools/bd-scraper/scraper.py`. It continues to send a flat list of posts; the API will group by thread.

---

# PART 2: STEP-BY-STEP IMPLEMENTATION

**Do these steps in order. Each step names the exact file (full path) and the exact change.**

---

## Step 1 — Add is_catch_intel column to table definition

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/db/FishingIntelTables.kt`

**Action:** In `FishingIntelReportsTable`, after the line that defines `val tldr = text("tldr").nullable()`, add exactly this line:

```kotlin
val isCatchIntel = bool("is_catch_intel").nullable()
```

---

## Step 2 — Add migration for is_catch_intel

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/db/FishingIntelDb.kt`

**Action:** In the function `addReportColumnsIfMissing`, find the list `val alters = listOf(...)`. Inside that list, after the string `"ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS tldr TEXT"`, add a new string:

```kotlin
"ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS is_catch_intel BOOLEAN"
```

---

## Step 3 — Add isCatchIntel to FishingReport model

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/models/FishingIntelModels.kt`

**Action:** In the data class `FishingReport`, add a new parameter after `val tldr: String? = null`:

```kotlin
val isCatchIntel: Boolean? = null
```

---

## Step 4 — Add isCatchIntel and lastActivityAt to ReportWithClaims

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/models/FishingIntelModels.kt`

**Action:** In the data class `ReportWithClaims`, add two new parameters after `val tldr: String? = null`:

```kotlin
val isCatchIntel: Boolean? = null,
val lastActivityAt: Instant? = null,
```

(Keep the comma before `val claims`.)

---

## Step 5 — Persist isCatchIntel in saveReport and read it in getReportsNearby

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/db/FishingIntelDb.kt`

**Action 5a:** In `saveReport`, inside the `FishingIntelReportsTable.insertAndGetId { ... }` block, after the line `report.tldr?.let { v -> it[tldr] = v }`, add:

```kotlin
report.isCatchIntel?.let { v -> it[isCatchIntel] = v }
```

**Action 5b:** In `getReportsNearby`, in the `.map { row -> ... }` block where `ReportWithClaims(...)` is constructed, add two arguments to the constructor: `isCatchIntel = row[FishingIntelReportsTable.isCatchIntel]` and `lastActivityAt = row[FishingIntelReportsTable.lastActivityAt]?.toInstant(ZoneOffset.UTC)`. Add them after `tldr = row[FishingIntelReportsTable.tldr]` and before `claims = claims`.

---

## Step 6 — Add analyzeThread to AI service

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/ai/FishingIntelAiService.kt`

**Action:** Add a new suspend function named `analyzeThread` with signature:

```kotlin
suspend fun analyzeThread(title: String, combinedContent: String): Triple<List<String>, String?, Boolean?>?
```

- If `!isEnabled()` return null.
- Truncate combinedContent to MAX_CONTENT_CHARS (4000).
- System prompt must require JSON with three keys: `species_caught` (array of species actually caught; exclude chum/bait/freezer/past trip), `tldr` (one or two sentences, standalone), `is_catch_intel` (boolean: true if thread is mostly catch/conditions intel, false if mostly off-topic).
- User message: "Title: $title\n\nContent: $contentTruncated"
- Parse response JSON: extract `species_caught` array, `tldr` string (trim, max 500 chars), `is_catch_intel` boolean. Return `Triple(speciesList, tldr, is_catch_intel)` or null on any failure. Use the same HTTP post pattern and timeout as `analyzePost`. Catch exceptions and return null; log warning.

---

## Step 7 — Ingest: two-pass flow and thread-level TL;DR

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/api/routes/SpotRoutes.kt`

**Action:** Replace the current single loop over `posts.withIndex()` with the following structure. Do not leave the old per-post AI call in place.

1. **Normalize thread URL:** Define a function or value that normalizes threadUrl: `posts.map { it.threadUrl.split("#").first().trimEnd('/').take(512) }.distinct()` or, for grouping, use `fun norm(u: String) = u.split("#").first().trimEnd('/').take(512)` and then `val byThread = posts.groupBy { norm(it.threadUrl) }`.

2. **Precompute per-thread data:** Create two maps: `threadTldr: Map<String, Pair<String?, Boolean?>>` and `threadSpecies: Map<String, List<String>>`. For each entry in `byThread` (threadUrl to list of posts):
   - Title = first post with `postRole == "thread_starter"` (or first post) `.title`
   - Combined content = thread posts sorted by date or order, map `content`, join with "\n\n", take 3000 chars.
   - If AI enabled: call `FishingIntelAiService.analyzeThread(title, combinedContent)` (use `runBlocking { }` or ensure the route runs in a coroutine scope). Result is Triple(species, tldr, isCatchIntel). Put `tldr` and `isCatchIntel` into threadTldr[threadUrl], and species into threadSpecies[threadUrl]. If AI returns null, use rule-based fallback.
   - If AI disabled: Build rule-based summary string (e.g. "Caught " + union of species from posts' speciesCaught + ". " + first 120 chars of combined content). Place from SoCalGazetteer.findInText(combinedContent).firstOrNull()?.name. Put (summary, null) in threadTldr and union of speciesCaught in threadSpecies.

3. **Loop over all posts:** For each post (same as before), parse date, compute fingerprint, skip if fingerprint exists. When building the `FishingReport`:
   - Set `tldr = threadTldr[norm(post.threadUrl)]?.first` and `isCatchIntel = threadTldr[norm(post.threadUrl)]?.second` only when `post.postRole == "thread_starter"`. For replies, leave both null.
   - For CATCH claims: when `post.postRole == "thread_starter"` use `threadSpecies[norm(post.threadUrl)]` (or emptyList if missing); for replies use `post.speciesCaught` (or leave empty for narrative purity).
   - Pass `isCatchIntel` into the `FishingReport` constructor (you added this parameter in Step 3).

---

## Step 8 — Create ThreadIntelScorer

**New file:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/processing/ThreadIntelScorer.kt`

**Action:** Create a new Kotlin file. Package: `package com.shaka.fishing_intel.processing`. Add an object `ThreadIntelScorer` with a function:

```kotlin
fun score(report: ReportWithClaims, tldrText: String?): Double
```

- Timeliness: from report.publishedAt or report.lastActivityAt (prefer lastActivityAt if non-null). If now - date < 24h add 30; else if < 3d add 15; else if < 7d add 5; else 0.
- Interest: for each claim in report.claims with claim.species in SpeciesTier.TROPHY_SPECIES add 10. If SoCalGazetteer.findInText((report.rawExcerpt ?: "") + (report.title ?: "")).isNotEmpty() add 15. If (tldrText ?: "") + (report.rawExcerpt ?: "") contains any of "tonight", "tomorrow", "8pm", "at dawn", "this evening" add 5.
- Relevance: if report.isCatchIntel == false return 0.0 immediately. If report.isCatchIntel == null and (tldrText or report.rawExcerpt) contains "alien" or "tackle shop" (without "caught" or "limit" in same string) return 0.0. Otherwise no penalty.
- Return the sum of timeliness + interest (and apply relevance as above). Import SpeciesTier, SoCalGazetteer, ReportWithClaims, and use java.time for "now" and duration.

---

## Step 9 — NarrativeInsight response: add threadZone (do this before Step 10)

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/api/FishingIntelResponses.kt`

**Action:** In the data class `NarrativeInsight`, add a new parameter after `tldr`:

```kotlin
val threadZone: String? = null
```

---

## Step 10 — buildNarrativeInsights: pick by tldr, score, sort, take top N

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/api/FishingIntelRoutes.kt`

**Action:** In the function `buildNarrativeInsights`:

1. **Location:** Do not use `report.threadZone` as location. Set `location` to: `SoCalGazetteer.findInText(report.rawExcerpt ?: "")?.firstOrNull()?.name ?: SoCalGazetteer.findInText(report.title ?: "")?.firstOrNull()?.name ?: ""`. Remove the requirement that location is non-blank (allow empty so we can show threads with no place).
2. **Eligibility:** Keep the filter that the report has at least one trophy CATCH claim. Keep building species, excerpt, tldr (prefer report.tldr, else fallback string).
3. **Representative per thread:** After building the list of eligible NarrativeInsight (one per report), group by threadUrl. For each group, pick the report that has `tldr != null` (thread-starter). If no report in the group has tldr, use `maxByOrNull { it.publishedAt }`. Build one NarrativeInsight per thread from that representative report. When constructing each NarrativeInsight, pass `threadZone = report.threadZone` (the parameter was added in Step 9).
4. **Scoring:** For each representative report, call `ThreadIntelScorer.score(report, report.tldr)`. Sort the representative reports by this score descending. Take the top 3. Build and return the NarrativeInsight list from these 3 reports.

---

## Step 11 — Headline: never "at Inshore"

**File:** `/Users/ed/Desktop/shaka/shaka-api/src/main/kotlin/com/shaka/fishing_intel/api/FishingIntelRoutes.kt`

**Action:** Where the headline is built from narrativeInsights (e.g. `message = "${narrativeInsights.first().species} at ${narrativeInsights.first().location}"`), change to: if `narrativeInsights.first().location.isNotBlank()` use `"${narrativeInsights.first().species} at ${narrativeInsights.first().location}"`, else use `narrativeInsights.first().species` only. So the message never uses a zone as the location (Inshore/Offshore/etc. must not appear as the "at X" part).

---

## Step 12 — App: show excerpt only when no TL;DR

**File:** `/Users/ed/Desktop/shaka/shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart`

**Action:** In `_buildNarrativeInsightCard`, change the condition for `showExcerpt` so that when `insight.tldr.isNotEmpty` we never show the excerpt. Set:

```dart
final showExcerpt = insight.tldr.isEmpty && insight.excerpt.isNotEmpty && insight.excerpt != displayTldr;
```

So: show excerpt only when there is no TL;DR and excerpt is non-empty and different from displayTldr.

---

## Step 13 — App: small "View original thread" link

**File:** `/Users/ed/Desktop/shaka/shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart`

**Action:** Replace the `TextButton` that says "Original thread" with a small text link. Use a `GestureDetector` or `InkWell` wrapping a `Text` with text "View original thread", fontSize 12, color grey (e.g. `Colors.grey[500]`). Keep the same `onPressed` behavior (launch threadUrl in external app). Remove the coral styling and button padding so it looks like a secondary link.

---

## Step 14 — App: remove "May require BD Outdoors login"

**File:** `/Users/ed/Desktop/shaka/shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart`

**Action:** Remove the `Text` widget that contains `'May require BD Outdoors login.'` (the one inside `_buildNarrativeInsightCard`). Optionally add a single footnote below all narrative cards elsewhere if you want to keep the disclaimer once.

---

## Step 15 — App model: add threadZone to NarrativeInsight

**File:** `/Users/ed/Desktop/shaka/shaka-app/lib/features/fishing_intel/models/fishing_intel_models.dart`

**Action:** In the class `NarrativeInsight`, add a field `final String? threadZone;`. Add it to the constructor as an optional parameter (e.g. `this.threadZone`). In `fromJson`, add `threadZone: json['threadZone']`. Ensure existing responses without threadZone still parse (nullable/optional).

---

# END OF STEPS

After completing all steps, run the **Runbook** in Part 1 (Railway vars, build, deploy, scraper, app install, verify). Confirm all **Success criteria** in Part 1 are met.
