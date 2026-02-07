-- One-off: add any missing columns to fishing_intel_reports (production may lack them if migration aborted).
-- Run once in Railway Postgres → Query (or psql), then re-run the BD scraper.
ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS thread_zone VARCHAR(50);
ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS content_type VARCHAR(30);
ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMP;
ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS thread_url VARCHAR(512);
ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS tldr TEXT;
CREATE INDEX IF NOT EXISTS fishing_intel_reports_thread_url_idx ON fishing_intel_reports(thread_url);
