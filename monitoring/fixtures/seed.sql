-- Seed fixture for the probe-contract CI job (docs/synthetic-monitor-design.md §c).
--
-- Without this seed the contract test is VACUOUS: against an empty DB the
-- tide/hourly endpoints 404 and search returns [], so no shape assertion ever
-- executes and the job degenerates to "routes are registered". This seeds one
-- reference spot (cali-la-jolla-cove) with hourly swell/wind series, tide
-- series + day curves, and one AI region-insights row so every Tier-1 journey
-- exercises a populated response.
--
-- Runs BEFORE the API boots (CREATE TABLE IF NOT EXISTS mirrors the backend
-- DDL in SpotDataCache.createTableIfNotExists / FishingIntelTables.kt; if the
-- backend DDL drifts incompatibly, this fixture failing IS the contract test
-- doing its job). All dates are relative to CURRENT_DATE so the fixture never
-- goes stale. Idempotent via ON CONFLICT.

-- ---------- Tables (mirror of backend DDL) ----------

CREATE TABLE IF NOT EXISTS spot_swell_hourly (
    id SERIAL PRIMARY KEY,
    spot_id VARCHAR(100) NOT NULL,
    local_date DATE NOT NULL,
    timezone_id VARCHAR(50),
    source VARCHAR(40),
    points_json TEXT,
    fetched_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (spot_id, local_date)
);

CREATE TABLE IF NOT EXISTS spot_wind_hourly (
    id SERIAL PRIMARY KEY,
    spot_id VARCHAR(100) NOT NULL,
    local_date DATE NOT NULL,
    timezone_id VARCHAR(50),
    points_json TEXT,
    fetched_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (spot_id, local_date)
);

CREATE TABLE IF NOT EXISTS spot_tide_days (
    id SERIAL PRIMARY KEY,
    spot_id VARCHAR(100) NOT NULL,
    local_date DATE NOT NULL,
    provider VARCHAR(20) NOT NULL DEFAULT 'noaa',
    station_id VARCHAR(20),
    station_name VARCHAR(200),
    station_distance_mi DOUBLE PRECISION,
    timezone_id VARCHAR(50),
    datum VARCHAR(20) DEFAULT 'MLLW',
    points_json TEXT,
    extremes_json TEXT,
    fetched_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (spot_id, local_date, provider)
);

CREATE TABLE IF NOT EXISTS spot_tide_series (
    spot_id VARCHAR(100) NOT NULL,
    provider VARCHAR(20) NOT NULL DEFAULT 'fes2022',
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    timezone_id VARCHAR(50),
    datum VARCHAR(20) DEFAULT 'MLLW',
    station_id VARCHAR(20),
    station_name VARCHAR(200),
    station_distance_mi DOUBLE PRECISION,
    model_version VARCHAR(20) NOT NULL DEFAULT 'FES2022',
    step_minutes SMALLINT NOT NULL DEFAULT 30,
    generated_from DATE,
    generated_through DATE,
    generated_at TIMESTAMP,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    PRIMARY KEY (spot_id, provider)
);

CREATE TABLE IF NOT EXISTS fishing_intel_region_insights (
    region_id VARCHAR(50) NOT NULL,
    slot_key VARCHAR(30) NOT NULL,
    insights_json TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (region_id, slot_key)
);

-- ---------- Hourly swell + wind (T4 + generatedAt anchor) ----------
-- Seed CURRENT_DATE-1 .. CURRENT_DATE+2 so "today"/"tomorrow" exist regardless
-- of the UTC-vs-spot-local date offset (America/Los_Angeles). 24 points/day,
-- epochs anchored at LA-local midnight.

INSERT INTO spot_swell_hourly (spot_id, local_date, timezone_id, source, points_json, fetched_at)
SELECT 'cali-la-jolla-cove', d::date, 'America/Los_Angeles', 'ci-seed',
    (SELECT json_agg(json_build_object(
        'epochMs', (extract(epoch FROM (d::timestamp + make_interval(hours => h)) AT TIME ZONE 'America/Los_Angeles') * 1000)::bigint,
        'heightFt', 2.5, 'periodSec', 12.0, 'directionDeg', 275,
        'correctedHeightFt', 1.8))::text
     FROM generate_series(0, 23) h),
    NOW()
FROM generate_series(CURRENT_DATE - 1, CURRENT_DATE + 2, interval '1 day') d
ON CONFLICT (spot_id, local_date) DO UPDATE
    SET points_json = EXCLUDED.points_json, fetched_at = NOW();

INSERT INTO spot_wind_hourly (spot_id, local_date, timezone_id, points_json, fetched_at)
SELECT 'cali-la-jolla-cove', d::date, 'America/Los_Angeles',
    (SELECT json_agg(json_build_object(
        'epochMs', (extract(epoch FROM (d::timestamp + make_interval(hours => h)) AT TIME ZONE 'America/Los_Angeles') * 1000)::bigint,
        'speedKts', 7.2, 'directionDeg', 290, 'gustKts', 10.1))::text
     FROM generate_series(0, 23) h),
    NOW()
FROM generate_series(CURRENT_DATE - 1, CURRENT_DATE + 2, interval '1 day') d
ON CONFLICT (spot_id, local_date) DO UPDATE
    SET points_json = EXCLUDED.points_json, fetched_at = NOW();

-- ---------- Tide series + day curves (T5) ----------
-- Seed under BOTH providers: CI does not set TIDE_SOURCE (default 'noaa') but
-- production uses fes2022; the journey must work either way.

INSERT INTO spot_tide_series (spot_id, provider, lat, lon, timezone_id, datum,
                              generated_from, generated_through, generated_at, status)
SELECT 'cali-la-jolla-cove', p, 32.85, -117.27, 'America/Los_Angeles', 'MLLW',
       CURRENT_DATE - 1, CURRENT_DATE + 365, NOW(), 'ready'
FROM unnest(ARRAY['noaa', 'fes2022']) p
ON CONFLICT (spot_id, provider) DO UPDATE
    SET generated_from = EXCLUDED.generated_from,
        generated_through = EXCLUDED.generated_through,
        generated_at = NOW(), status = 'ready';

INSERT INTO spot_tide_days (spot_id, local_date, provider, timezone_id, datum, points_json, extremes_json, fetched_at)
SELECT 'cali-la-jolla-cove', d::date, p, 'America/Los_Angeles', 'MLLW',
    (SELECT json_agg(json_build_object(
        'epochMs', (extract(epoch FROM (d::timestamp + make_interval(mins => m)) AT TIME ZONE 'America/Los_Angeles') * 1000)::bigint,
        'heightFt', round((2.0 + 1.8 * sin(2 * pi() * m / 745.0))::numeric, 2)))::text
     FROM generate_series(0, 1410, 30) m),
    '[]',
    NOW()
FROM generate_series(CURRENT_DATE - 1, CURRENT_DATE + 8, interval '1 day') d,
     unnest(ARRAY['noaa', 'fes2022']) p
ON CONFLICT (spot_id, local_date, provider) DO UPDATE
    SET points_json = EXCLUDED.points_json, fetched_at = NOW();

-- ---------- AI region insights (W7 / ai_region_insights) ----------
-- Slot key mirrors FishingIntelRoutes.insightSlotKey: local date at fixed
-- UTC-8. Seed the adjacent slots too so date-boundary timing can't flake CI.

INSERT INTO fishing_intel_region_insights (region_id, slot_key, insights_json)
SELECT 'all_regions', to_char((NOW() - interval '8 hours')::date + offs, 'YYYY-MM-DD'),
       '["Seed insight: yellowtail up at the seeded landing.","Seed insight: calm seas through tomorrow.","Seed insight: bluefin holding outside."]'
FROM generate_series(-1, 1) offs
ON CONFLICT (region_id, slot_key) DO NOTHING;
