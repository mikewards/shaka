-- One-off: add tldr to fishing_intel_reports (production may have been created before this column existed).
-- Run against your Railway Postgres (or any env) then re-run the BD scraper.
ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS tldr TEXT;
