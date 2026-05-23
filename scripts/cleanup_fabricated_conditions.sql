-- Cleanup of fabricated weather/swell rows in spot_cache.
--
-- Background: until Jun 2026, OpenMeteoClient substituted hardcoded defaults
-- when the API failed (wind 10 km/h = 5.39957 kts east, swell 1ft @ 8s W,
-- wave 1.0m period 8s). During the Jun 3-11 outage these were persisted for
-- hundreds of spots. The fingerprint below matches only that exact synthetic
-- combination, which real conditions essentially never produce together.
--
-- Usage:
--   1. Run the SELECT first and review the count.
--   2. Then run the UPDATE inside a transaction.
--
-- The nulled columns repopulate on the next weather_prefetch cycle (3h).

-- Step 1: review what would be cleaned
SELECT COUNT(*) AS fabricated_rows
FROM spot_cache
WHERE ABS(wind_speed_knots - 5.39957) < 0.0001
  AND wind_direction = 'E'
  AND swell_period_sec = 8.0
  AND swell_direction = 'W';

-- Step 2: clear the fabricated values (run manually after review)
-- BEGIN;
-- UPDATE spot_cache
-- SET wind_speed_knots = NULL,
--     wind_direction = NULL,
--     swell_height_ft = NULL,
--     swell_corrected_height_ft = NULL,
--     swell_period_sec = NULL,
--     swell_direction = NULL,
--     weather_fetched_at = NULL
-- WHERE ABS(wind_speed_knots - 5.39957) < 0.0001
--   AND wind_direction = 'E'
--   AND swell_period_sec = 8.0
--   AND swell_direction = 'W';
-- COMMIT;
