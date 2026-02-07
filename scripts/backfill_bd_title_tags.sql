-- One-time backfill: set thread_zone and clean title for BD reports where title
-- starts with a general location tag (Inshore, Offshore, Islands, Bay, Harbor).
-- Run this after deploying the ingest changes so existing "Inshore45 lb..." rows are fixed.
--
-- Usage: psql $DATABASE_URL -f scripts/backfill_bd_title_tags.sql

UPDATE fishing_intel_reports
SET
  thread_zone = INITCAP((REGEXP_MATCH(title, '^(Inshore|Offshore|Islands|Bay|Harbor)', 'i'))[1]),
  title = TRIM(REGEXP_REPLACE(title, '^(Inshore|Offshore|Islands|Bay|Harbor)\s*', '', 'i'))
WHERE source_id = 'bd-outdoors'
  AND thread_zone IS NULL
  AND title ~* '^(Inshore|Offshore|Islands|Bay|Harbor)';
