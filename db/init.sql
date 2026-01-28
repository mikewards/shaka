-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Spots table (compatible with Exposed ORM)
CREATE TABLE IF NOT EXISTS spots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    region VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    access_type VARCHAR(50) NOT NULL, -- shore, boat, kayak
    depth_min_m DOUBLE PRECISION,
    depth_max_m DOUBLE PRECISION,
    difficulty VARCHAR(20), -- beginner, intermediate, advanced, expert
    parking BOOLEAN DEFAULT false,
    parking_info TEXT,
    permits_required BOOLEAN DEFAULT false,
    permit_info TEXT,
    directions TEXT,
    hazards TEXT, -- Comma-separated for Exposed compatibility
    target_species TEXT, -- Comma-separated for Exposed compatibility
    best_months VARCHAR(50), -- Comma-separated for Exposed compatibility
    image_url TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create PostGIS geography column for spatial queries
ALTER TABLE spots ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- Update location from lat/lon (trigger on insert/update)
CREATE OR REPLACE FUNCTION update_spot_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS spots_location_trigger ON spots;
CREATE TRIGGER spots_location_trigger
    BEFORE INSERT OR UPDATE ON spots
    FOR EACH ROW
    EXECUTE FUNCTION update_spot_location();

-- Spatial index for geo queries
CREATE INDEX IF NOT EXISTS spots_location_idx ON spots USING GIST (location);

-- Region and country indexes for filtering
CREATE INDEX IF NOT EXISTS spots_region_idx ON spots (region);
CREATE INDEX IF NOT EXISTS spots_country_idx ON spots (country);
CREATE INDEX IF NOT EXISTS spots_coords_idx ON spots (latitude, longitude);

-- Community reports table
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    spot_id UUID REFERENCES spots(id) ON DELETE SET NULL,
    source VARCHAR(100) NOT NULL, -- reddit, spearboard, local
    source_url TEXT,
    report_date TIMESTAMP NOT NULL,
    visibility_m DOUBLE PRECISION,
    water_temp_c DOUBLE PRECISION,
    fish_sighted TEXT, -- Comma-separated
    conditions_notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS reports_spot_idx ON reports (spot_id);
CREATE INDEX IF NOT EXISTS reports_date_idx ON reports (report_date DESC);

-- Function to find spots within radius using PostGIS
CREATE OR REPLACE FUNCTION find_spots_within_radius(
    search_lat DOUBLE PRECISION,
    search_lon DOUBLE PRECISION,
    radius_km DOUBLE PRECISION
)
RETURNS TABLE (
    spot_id UUID,
    spot_name VARCHAR,
    spot_description TEXT,
    spot_latitude DOUBLE PRECISION,
    spot_longitude DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,
    spot_region VARCHAR,
    spot_country VARCHAR,
    spot_access_type VARCHAR,
    spot_depth_min_m DOUBLE PRECISION,
    spot_depth_max_m DOUBLE PRECISION,
    spot_difficulty VARCHAR,
    spot_target_species TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        s.name,
        s.description,
        s.latitude,
        s.longitude,
        ST_Distance(
            s.location, 
            ST_SetSRID(ST_MakePoint(search_lon, search_lat), 4326)::geography
        ) / 1000.0 AS dist_km,
        s.region,
        s.country,
        s.access_type,
        s.depth_min_m,
        s.depth_max_m,
        s.difficulty,
        s.target_species
    FROM spots s
    WHERE ST_DWithin(
        s.location,
        ST_SetSRID(ST_MakePoint(search_lon, search_lat), 4326)::geography,
        radius_km * 1000
    )
    ORDER BY dist_km;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate Haversine distance (fallback if PostGIS unavailable)
CREATE OR REPLACE FUNCTION haversine_distance(
    lat1 DOUBLE PRECISION, lon1 DOUBLE PRECISION,
    lat2 DOUBLE PRECISION, lon2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    R DOUBLE PRECISION := 6371.0; -- Earth radius in km
    dLat DOUBLE PRECISION;
    dLon DOUBLE PRECISION;
    a DOUBLE PRECISION;
    c DOUBLE PRECISION;
BEGIN
    dLat := RADIANS(lat2 - lat1);
    dLon := RADIANS(lon2 - lon1);
    a := SIN(dLat/2) * SIN(dLat/2) + COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * SIN(dLon/2) * SIN(dLon/2);
    c := 2 * ATAN2(SQRT(a), SQRT(1-a));
    RETURN R * c;
END;
$$ LANGUAGE plpgsql;
