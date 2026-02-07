# Fishing Tab: Quality Fix + Amazing TL;DRs

A practical plan to fix misleading fishing insights and deliver TL;DRs that stand on their own—no BD Outdoors login required. Written for whoever implements it: enough detail to execute, and clear enough to read in one sitting.

---

## The problem in plain English

Someone posts on BD Outdoors: *"Fished various spots around the Horseshoe. Flat calm, zero current. Rock hopped for catch-and-release calicos, sand bass, and sheepshead. I had a bunch of bluefin tuna from summer in my freezer and used about 25 lbs of it to chum. We got a few bass to play."*

**What we show today:** A narrative card titled **"Bluefin Tuna at Inshore"** with a clipped excerpt that sounds like bluefin are being caught.

**What actually happened:** They caught calicos and sand bass. The bluefin was **frozen chum from a past season**—not caught on this trip.

So we’re **miscategorizing** data: we treat “mentioned” as “caught” and write wrong CATCH claims into the database. And we’re **under-serving** users: the only way to get the real story is to click through to BD, where many people don’t have accounts.

This plan fixes both: correct categorization (no more chum/bait/freezer as “caught”) and TL;DRs that contain the real takeaway in the app.

---

## What “done” looks like

- **No false trophy headlines.** If a post only mentions a species as chum, bait, or “from the freezer,” we never show “Species at Location” for that species.
- **TL;DRs that stand alone.** Each narrative card has a 1–2 sentence summary: what was caught, where, and (when relevant) conditions. Users don’t need to open BD to understand the report.
- **Low, predictable cost.** We use a cheap model (gpt-4o-mini or Claude Haiku), call it only when useful, and aim for ~$0.01–0.05 per ingest run. If that grows, we can turn AI off and still have correct rules.
- **BD link is optional.** The card leads with the TL;DR; “Original thread” is a secondary link with a clear “may require BD Outdoors login” note.

---

## Two kinds of ingestion: numeric vs narrative

Not all fishing intel is the same. The plan treats them differently.

**Numeric / structured reports** (fish counts, dock totals, landing pages, 976-TUNA counts, etc.) are **already solid.** They come from parsers that extract numbers and species from known formats. We **do not** use AI to rewrite, “improve,” or generate these. We don’t want AI making things up for numbers we know are true. If we ever use AI around numeric data at all, it would only be for **anomaly detection** (e.g. flagging a possible typo or outlier for human review)—not for changing or inventing counts.

**Narrative content** (BD Outdoors threads and replies—free-form text from anglers) is where AI really helps. Here we need to distinguish “caught” from “mentioned” (chum, bait, freezer) and generate a short TL;DR. So:

- **AI applies only to narrative sources** (e.g. `bd-outdoors` posts that go through the ingest endpoint with title + content + speciesMentioned/speciesCaught).
- **AI never runs on** dock totals, 976-TUNA counts, landing scrapes, or any other numeric/structured pipeline. Those stay rule-based and unchanged.

The rest of this plan keeps that boundary explicit wherever AI is mentioned.

---

## General location tags (Inshore / Offshore / Islands)

BD Outdoors uses **general location tags** such as **Inshore**, **Offshore**, **Islands**, and sometimes **Bay** / **Harbor**. These are not specific spots—they’re categories that help with geo and filtering. Today they can show up in two ways:

1. **Forum listing:** When we scrape the forum index, we try to read a “prefix” link (e.g. `a[href*="prefix_id"]`) and pass that as `thread_zone` into each post. When that works, we already have structured zone data.
2. **Thread title:** When the prefix isn’t available (or the forum embeds the tag in the title), the **title** in the DB looks like:  
   `"OffshoreFirst trip to Catalina of 2026..."` or `"Inshore45 lb yellowtail Dana Point 2/1/26"`  
   i.e. the tag is concatenated at the start with **no space**, so we never get a clean `thread_zone` and the stored title looks broken.

We need to **parse the title** for these tags and treat them as general location data: set `thread_zone` when it’s missing, and optionally **clean the title** for display so we don’t show “Inshore45 lb yellowtail” but “45 lb yellowtail Dana Point 2/1/26”.

**What’s needed**

- **Recognized tags:** Inshore, Offshore, Islands, Bay, Harbor (match `GeoResolver`’s SoCal zone list so geo resolution keeps working).
- **Parse:** Detect a leading tag at the start of the title (with or without a space). Regex-style: e.g. `^(Inshore|Offshore|Islands|Bay|Harbor)\s*(.*)$` (case-insensitive), then normalize the tag (e.g. capitalize) and use the rest as the cleaned title.
- **When:** Either when we **ingest** (API) or when we **scrape** (Python), or both:
  - **Ingest:** When we receive a BD post, if `post.threadZone` is null or blank, parse `post.title`. If a leading tag is found, set `report.threadZone` to that tag (e.g. “Inshore”) and optionally set `report.title` to the cleaned remainder (so we store “45 lb yellowtail Dana Point 2/1/26”). If `post.threadZone` is already set (from the forum), keep it and optionally still clean the title if it starts with the same tag.
  - **Scraper (optional):** When building the payload, parse the thread title the same way; send `threadZone` (from forum prefix or from title) and send a cleaned `title` so the API receives correct data even if the forum doesn’t expose the prefix.
- **Existing data:** Reports already in the DB with titles like “Inshore45 lb…” but `thread_zone` null need to be fixed. Either:
  - Run a **one-time migration** (or script) that updates `fishing_intel_reports`: for rows where `source_id = 'bd-outdoors'` and `thread_zone` is null, parse `title`, set `thread_zone` and replace `title` with the cleaned string; or
  - **On read:** When building narrative insights (or any response that shows title), if `thread_zone` is null and title starts with a known tag, strip the tag for display and derive zone for that request. Storing the cleaned data is better so geo and filters work everywhere.

**Note:** The Kotlin **prefetch job** (FishingIntelPrefetchJob) handles 976-TUNA, dock totals, landings, etc.—not BD. BD data comes from the **Python scraper** and the **ingest endpoint** (`POST /v1/intel/ingest`). So the change belongs in the **scraper** and/or the **ingest handler** in `SpotRoutes.kt`, not in the prefetch job. A one-time backfill can be a small script or a dedicated migration that runs once.

---

## Why the data gets miscategorized (and why ingest must change)

Data flows like this:

1. **Scraper** (Python) reads the post and produces:
   - `speciesMentioned`: any species name that appears (e.g. “bluefin” in “used bluefin to chum”).
   - `speciesCaught`: species that appear **near** phrases like “caught,” “landed,” “got,” “in the box.” For the chum post, that’s typically empty for bluefin.

2. **Ingest API** (`POST /v1/intel/ingest`, in `SpotRoutes.kt`) receives each post and does:
   ```kotlin
   val speciesForCatch = post.speciesCaught.ifEmpty { post.speciesMentioned }
   for (species in speciesForCatch) {
       // saves ClaimType.CATCH for each
   }
   ```
   So when `speciesCaught` is empty, **every `speciesMentioned` is written to the database as a CATCH.** That’s the bug: “mentioned” becomes “caught” in our DB.

3. **Fishing Intel API** builds “narrative insights” from reports that have a **trophy CATCH** claim. Because we’ve incorrectly stored bluefin as CATCH, we surface “Bluefin Tuna at Inshore.”

So the **ingest endpoint is where miscategorization happens.** It has to be updated: CATCH claims must be created **only** from species the system considers actually caught (first from scraper’s `speciesCaught`, later optionally from an AI “caught” list). Never from `speciesMentioned` alone.

The plan does three things: (1) fix ingest so we only write CATCH from real caught signals, (2) tighten the scraper so chum/bait/freezer don’t count as caught, and (3) add optional AI to both refine “caught” and generate a proper TL;DR we store and show.

---

## Implementation plan

Work in this order. Each phase is testable on its own.

---

### Phase A: Rule-based fixes (no AI, no schema change)

These changes stop the bad data at the source and improve the fallback text. No new dependencies or DB columns.

#### A1. Ingest: CATCH only from `speciesCaught`

**Why:** This is the fix that stops BD data from being miscategorized. Today, the API turns every mention into a CATCH when `speciesCaught` is empty.

**Where:** `shaka-api/src/main/kotlin/com/shaka/api/routes/SpotRoutes.kt`, inside the `post("/intel/ingest")` block, around **line 1086**.

**Current code:**
```kotlin
val speciesForCatch = post.speciesCaught.ifEmpty { post.speciesMentioned }
for (species in speciesForCatch) {
    val normalizedSpecies = SpeciesNormalizer.normalize(species)
    val claim = FishingClaim(
        claimType = ClaimType.CATCH,
        ...
    )
    FishingIntelDb.saveClaim(reportId, claim)
}
```

**Change:** Use **only** `post.speciesCaught` for CATCH. Do not fall back to `speciesMentioned`.

- Replace the logic so that the loop runs only over `post.speciesCaught` (e.g. `val speciesForCatch = post.speciesCaught`).
- After this change, when the scraper sends `speciesCaught = []` and `speciesMentioned = ["bluefin_tuna"]`, **no** CATCH claim is created for bluefin. Narrative insights will no longer show “Bluefin Tuna at Inshore” for that post.

**Optional:** If you want to keep “mentioned” for future features, add a separate loop that creates claims with a different type (e.g. `ClaimType.TARGETING` or a custom `MENTIONED`) from `post.speciesMentioned`. Narrative insights and trending must continue to use only `ClaimType.CATCH`.

---

#### A2. Scraper: Don’t count chum/bait/freezer as “caught”

**Why:** Even when ingest only uses `speciesCaught`, we should avoid putting species into `speciesCaught` when they’re clearly used as chum, bait, or from the freezer. That keeps the data clean at the source.

**Where:** `tools/bd-scraper/scraper.py`, function `extract_species_caught()` (and optionally helpers).

**Idea:** When we find a species in the “caught” window (near “caught,” “landed,” “got,” “in the box”), check a **larger context** around that mention. If that context includes “chum,” “freezer,” “used … to chum,” “for bait,” etc., do **not** add that species to `speciesCaught`.

**Concrete steps:**

1. **Define negative phrases** (case-insensitive, word boundaries where it helps):  
   e.g. `chum`, `chumming`, `freezer`, `from summer`, `used .* to chum`, `for chum`, `as chum`, `bait`, `for bait`, `to chum`, `had .* in my freezer`, `stored`, `saved`, `from last year`, `leftover`.

2. **In `extract_species_caught()`:** For each species you’re about to add, look at a window of text around the species mention (e.g. ±80–100 characters). If any negative phrase appears in that window, skip adding this species to `speciesCaught`.

3. **Optional extra check:** Detect patterns like “used [species] to chum” or “had [species] in my freezer” (e.g. regex or substring) and exclude those species from `speciesCaught` even if they appear near a “caught” phrase.

**Test:** Run the scraper on a thread containing the “bluefin as chum” post. For that post, `speciesCaught` must not include bluefin; `speciesMentioned` may still include it.

---

#### A3. API: Better fallback TL;DR when no stored TL;DR exists

**Why:** Until we have AI-generated (or otherwise stored) TL;DRs, the narrative card is built from “Species at Location” plus a short excerpt. Making that excerpt longer and keeping the formula clear improves readability.

**Where:** `shaka-api/src/main/kotlin/com/shaka/fishing_intel/api/FishingIntelRoutes.kt`, function `buildNarrativeInsights()` (around lines 183–210).

**Change:**

- Keep building narrative insights only from reports that have a **trophy CATCH** claim (no change there).
- When building the fallback `tldr` string (used when the report has no stored `tldr`), use a **longer** excerpt (e.g. 120–180 characters instead of 60) so context like “chum” or “catch-and-release” is visible. Keep the format readable, e.g. `"$species at $location. ${excerpt.trim()}"` then normalize whitespace and cap length if needed.
- Do not add new response fields yet; this is only improving the computed string. Once we have a stored `tldr` (Phase B + C), that will override this fallback.

---

#### A4. General location tags: parse title for Inshore / Offshore / Islands

**Why:** Titles in the DB can look like "Inshore45 lb yellowtail Dana Point 2/1/26" or "OffshoreFirst trip to Catalina..." because the general location tag is concatenated at the start with no space. We need these captured as `thread_zone` (for geo and narrative “location”) and the title cleaned for display.

**Where:** Best in **ingest** (`SpotRoutes.kt`) so one place owns the logic and we can backfill existing rows; optionally also in the **scraper** for cleaner payloads.

**Ingest (recommended):**

- Before building `FishingReport`, derive `(threadZone, cleanedTitle)` from `post.title` when the title starts with a known general-location tag (Inshore, Offshore, Islands, Bay, Harbor). Use a case-insensitive match (e.g. regex `^(Inshore|Offshore|Islands|Bay|Harbor)\s*(.*)$`); normalize the tag (e.g. "Inshore") for `thread_zone`.
- If `post.threadZone` is already non-blank (from forum prefix), keep it; still run the title parser and use the **cleaned** remainder as the stored title if a tag was stripped.
- If `post.threadZone` is null/blank and the title parser finds a tag, set `report.threadZone` to that tag and `report.title` to the cleaned remainder. Otherwise keep `post.title` as-is.
- Store `report.threadZone` and `report.title` as usual. `GeoResolver` already understands "inshore", "offshore", "islands", "bay", "harbor" for geo.

**Scraper (optional):**

- In `scraper.py`, when building each post payload, if the raw title starts with one of the tags (no space), set `threadZone` to that tag (if not already set from the forum’s prefix link) and set `title` in the payload to the remainder so the API receives a clean title.

**Backfill existing data:**

- One-time script or SQL + Kotlin migration: for `fishing_intel_reports` where `source_id = 'bd-outdoors'` and `thread_zone` is null, parse `title`; if it starts with a known tag, update `thread_zone` and set `title` to the cleaned string. Run after deploy so existing “Inshore45…” rows get fixed.

---

### Phase B: Database and models for stored TL;DR

We need a place to store a precomputed TL;DR per report (from AI or future logic). Nullable so existing rows and non-AI sources stay valid.

#### B1. Add `tldr` column and wire it through

**Schema**

- **File:** `db/init.sql`
- **Table:** `fishing_intel_reports`
- **Change:** Add `tldr TEXT NULL` (e.g. after `raw_excerpt`).  
  If you use separate migrations, add something like:  
  `ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS tldr TEXT;`

**Exposed (Kotlin)**

- **File:** `shaka-api/src/main/kotlin/com/shaka/fishing_intel/db/FishingIntelTables.kt`
- **Change:** On `FishingIntelReportsTable`, add:  
  `val tldr = text("tldr").nullable()`

**Domain models**

- **File:** `shaka-api/src/main/kotlin/com/shaka/fishing_intel/models/FishingIntelModels.kt`
- **Change:**  
  - On `FishingReport`, add: `val tldr: String? = null`  
  - On `ReportWithClaims`, add: `val tldr: String? = null`

**Persistence**

- **File:** `shaka-api/src/main/kotlin/com/shaka/fishing_intel/db/FishingIntelDb.kt`
- **Changes:**  
  - In `saveReport()`: when inserting into `FishingIntelReportsTable`, set `it[tldr] = report.tldr`.  
  - Where you map DB rows to `ReportWithClaims` (e.g. in `getReportsNearby` or equivalent), set `tldr = row[FishingIntelReportsTable.tldr]`.

---

#### B2. Optional: Let ingest accept a precomputed TL;DR

If you ever want the **scraper** (or another client) to send a TL;DR in the ingest payload:

- In `FishingIntelResponses.kt`, add an optional field to `IngestPostRequest`, e.g. `val tldr: String? = null`.
- In `SpotRoutes.kt`, when building `FishingReport` for that post, set `report.tldr = post.tldr` when present.

For the “AI in the API” path below, the API generates and stores the TL;DR, so this is optional.

---

### Phase C: AI integration (cheap model, cost-controlled)

Use a single cheap model and call it **only for narrative content** (BD Outdoors threads/replies). Goal: correct “caught” list + one strong TL;DR per post, at ~$0.01–0.05 per ingest run.

**Important:** AI is **not** used for numeric or structured reports (fish counts, dock totals, 976-TUNA, landings). Those remain rule-based; we don’t want AI altering or inventing numbers we already know are true. AI is strictly for narrative text where interpretation and summarization add value.

#### C1. Model and configuration

- **Model:** **gpt-4o-mini** (OpenAI) or **Claude Haiku** (Anthropic). Pick one and use it consistently.
- **Client:** The project already has the Ktor HTTP client; use it to call the provider’s REST API. No need for a heavy SDK unless you prefer it.
- **Configuration (env):**
  - `FISHING_INTEL_AI_ENABLED` — `true` / `false`. If `false` or unset, skip all AI calls.
  - `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` — required when AI is enabled.
  - Optionally: `FISHING_INTEL_AI_MODEL` (e.g. `gpt-4o-mini` or the Haiku model id).

If AI is disabled or the key is missing, ingest should behave as in Phase A: CATCH only from `speciesCaught`, no TL;DR generation.

---

#### C2. When to call the model

- **Only for BD Outdoors narrative posts.** The ingest endpoint that receives scraper payloads (threadUrl, title, content, speciesMentioned, speciesCaught) is the only place we consider AI. Do **not** invoke the model for:
  - 976-TUNA counts or dock totals
  - Landing-page scrapes
  - Any other numeric or structured ingestion
  Those pipelines stay as-is; their numbers are trusted.
- **Recommended:** Call AI only for BD posts where `speciesMentioned` contains at least one **trophy species** (use `SpeciesTier.TROPHY_SPECIES`). That keeps call volume down (~20–40% of BD posts) and avoids spending on posts that can’t drive a narrative insight anyway.
- **Optional:** Skip when the same post was already processed (e.g. cache by hash of `title + content`, TTL 7 days). That avoids re-calling on re-ingest.

---

#### C3. Where to call the model

- **Recommended:** Inside the ingest flow in `SpotRoutes.kt`, **per post**, before `FishingIntelDb.saveReport`:
  - If the post qualifies (BD + optional trophy-in-mentioned), call the AI service.
  - Use the AI’s **species_caught** list as the **only** source of CATCH claims for that post (normalize with `SpeciesNormalizer`).
  - Set `report.tldr` to the AI’s **tldr** string.
- If the call is skipped or fails, fall back to Phase A behavior: CATCH only from `post.speciesCaught`, `report.tldr = null`.

---

#### C4. Prompt and response shape

**Input to the model:** Post `title` and `content`. Truncate `content` to something like 600–800 words to control context size and cost. Optionally pass `speciesMentioned` as a hint.

**System prompt (concise):**  
You are a fishing report analyst. For the given forum post, output **only** valid JSON with two keys:  
(1) `species_caught`: array of species **actually caught on this trip**, normalized (e.g. `bluefin_tuna`, `yellowtail`, `calico_bass`). Do **not** include species that are only mentioned as chum, bait, from the freezer, or from a past trip.  
(2) `tldr`: one or two sentences summarizing what was caught, where, and conditions if relevant. Standalone; no “read more” or links. Factual, angler-friendly tone.

**User prompt:** e.g.  
`Title: <post title>\n\nContent: <truncated content>`

**Expected output (example):**
```json
{
  "species_caught": ["calico_bass", "sand_bass"],
  "tldr": "Calicos and sand bass, catch-and-release at Horseshoe. Chummed with frozen bluefin; light current."
}
```

**Error handling:** If the response isn’t valid JSON or the request fails, do not create CATCH from the AI; use only `post.speciesCaught` and leave `report.tldr` null so the API uses the Phase A3 fallback.

---

#### C5. Wire the AI into ingest

**New component:** A small service, e.g. `FishingIntelAiService`, that:

- Reads env (AI enabled, API key, model).
- Exposes something like:  
  `suspend fun analyzePost(title: String, content: String, speciesMentioned: List<String>): Pair<List<String>, String?>?`  
  returning `(species_caught, tldr)` or `null` when skipped or on failure.

**In `SpotRoutes.kt` (post("/intel/ingest")):**

- Before the per-post loop, obtain a reference to this service (e.g. from config or a lazy singleton).
- For each post:
  - If AI is enabled and the post is BD (and optionally has a trophy in `speciesMentioned`), call the service.
  - If the result is non-null: create CATCH claims **only** from `result.first` (normalized); set `report.tldr = result.second`.
  - If the result is null: create CATCH only from `post.speciesCaught`; set `report.tldr = null`.
- Ensure `FishingReport` and `FishingIntelDb.saveReport` accept and persist `tldr` (Phase B1).

---

### Phase D: Use stored TL;DR in API and app

#### D1. Narrative insights: prefer stored TL;DR

**Where:** `shaka-api/src/main/kotlin/com/shaka/fishing_intel/api/FishingIntelRoutes.kt`, `buildNarrativeInsights()`.

- When building each `NarrativeInsight`:
  - If `report.tldr` is non-null and non-blank, use it as the primary text (e.g. `tldr = report.tldr`). Optionally still pass `report.rawExcerpt` as secondary or omit if the TL;DR is enough.
  - If `report.tldr` is null or blank, use the improved fallback from Phase A3: `"$species at $location. ${excerpt.take(120)}"` (or your chosen length).
- Response shape stays the same: `tldr` and `excerpt` on the insight so the app can show 2–3 lines of context.

---

#### D2. App: TL;DR first; BD link secondary

**Where:** `shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart`, `_buildNarrativeInsightCard`.

- **Primary content:** Use `insight.tldr` as the main copy. Allow 2–3 lines (e.g. `maxLines: 3`) so the full takeaway is visible without tapping.
- **Secondary:** If `insight.excerpt` is present and adds context, show it below in smaller, muted style.
- **Link:** Change “Read report” to something like “Original thread” and keep or add “May require BD Outdoors login.” Style the link as secondary (e.g. text link, not a primary button) so it’s clear the value is in the TL;DR, not the external page.

---

## File checklist

| Phase | Task | File(s) |
|-------|------|--------|
| A1 | Ingest: CATCH only from speciesCaught | `shaka-api/src/main/kotlin/com/shaka/api/routes/SpotRoutes.kt` |
| A2 | Scraper: negative context for “caught” | `tools/bd-scraper/scraper.py` |
| A3 | Better fallback TL;DR in buildNarrativeInsights | `shaka-api/src/main/kotlin/com/shaka/fishing_intel/api/FishingIntelRoutes.kt` |
| A4 | General location tags: parse title → thread_zone + cleaned title | `SpotRoutes.kt` (ingest); optional: `scraper.py`. Backfill script for existing rows. |
| B1 | DB column + Exposed + models + save/load | `db/init.sql`, `FishingIntelTables.kt`, `FishingIntelModels.kt`, `FishingIntelDb.kt` |
| B2 | Optional: ingest request tldr field | `FishingIntelResponses.kt`, `SpotRoutes.kt` |
| C1–C5 | AI service, prompt, ingest wiring | New e.g. `fishing_intel/ai/FishingIntelAiService.kt`; `SpotRoutes.kt`; env |
| D1 | Use report.tldr in narrative insights | `FishingIntelRoutes.kt` |
| D2 | App card: TL;DR first, link secondary | `shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart` |

---

## Cost and rollback

- **Target:** ~$0.01–0.05 per ingest run (cheap model, only when useful, optional cache).
- **If cost grows:** Set `FISHING_INTEL_AI_ENABLED=false`. Ingest still uses only `speciesCaught` (Phase A), and narrative insights use the improved fallback TL;DR. No DB rollback; `tldr` stays nullable.
- **Downgrade path:** Phases A and B stay; AI is optional. Existing stored TL;DRs continue to be used where present.

---

## How to test

- **Scraper:** Run `extract_species_caught()` on the exact “bluefin from freezer to chum” excerpt; assert bluefin is not in the result.
- **Ingest:** Send a payload with `speciesCaught = []` and `speciesMentioned = ["bluefin_tuna"]`; assert no CATCH claim is created for that post.
- **E2E:** Run scraper and ingest, then open a spot that had the chum post; confirm there is no “Bluefin Tuna at Inshore” narrative. With AI on, confirm the card shows a clear, standalone TL;DR and the BD link is secondary.
- **Cost:** After a few ingest runs, check provider usage; if it’s above ~$0.10/run, narrow “when to call AI” or add caching.

---

## Summary

1. **Ingest** is the place that today turns “mentioned” into “caught.” Fix it so CATCH claims are created **only** from `speciesCaught` (and, when AI runs, from the AI’s “caught” list). That stops BD data from being miscategorized.
2. **Scraper:** Exclude chum/bait/freezer context from `speciesCaught` so we don’t send false caught signals.
3. **General location tags:** Parse BD thread titles for leading tags (Inshore, Offshore, Islands, Bay, Harbor); set `thread_zone` when missing and store a cleaned title. Backfill existing rows. (Ingest and/or scraper; not the prefetch job.)
4. **DB:** Add nullable `tldr` and wire it through so we can store and serve a real summary per report.
5. **AI:** Use a cheap model **only for narrative content** (BD Outdoors threads/replies)—never for fish counts, dock totals, or other numeric reports. For narrative posts: get a correct “caught” list and a TL;DR; store both and use them in narrative insights. Solid numbers stay rule-based; we don’t let AI change or invent them.
6. **App:** Lead with the TL;DR; make “Original thread” secondary and clearly “may require login.”

Result: no more false “Bluefin at Inshore” from chum posts; TL;DRs that give the full story in the app without sending users to BD; general location tags (Inshore/Offshore/Islands) captured and titles cleaned; numeric ingestion unchanged and trusted.
