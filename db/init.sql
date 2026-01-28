-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Spots table
CREATE TABLE spots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    region VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    access_type VARCHAR(50) NOT NULL, -- shore, boat, kayak
    depth_min_m DECIMAL(5,1),
    depth_max_m DECIMAL(5,1),
    difficulty VARCHAR(20), -- beginner, intermediate, advanced, expert
    parking BOOLEAN DEFAULT false,
    permits_required BOOLEAN DEFAULT false,
    permit_info TEXT,
    hazards TEXT[],
    target_species TEXT[],
    best_months INT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Spatial index for geo queries
CREATE INDEX spots_location_idx ON spots USING GIST (location);

-- Region index for filtering
CREATE INDEX spots_region_idx ON spots (region);
CREATE INDEX spots_country_idx ON spots (country);

-- Community reports table
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    spot_id UUID REFERENCES spots(id),
    source VARCHAR(100) NOT NULL, -- reddit, spearboard, local
    source_url TEXT,
    report_date DATE NOT NULL,
    visibility_m DECIMAL(4,1),
    water_temp_c DECIMAL(4,1),
    fish_sighted TEXT[],
    conditions_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX reports_spot_idx ON reports (spot_id);
CREATE INDEX reports_date_idx ON reports (report_date DESC);

-- Function to find spots within radius
CREATE OR REPLACE FUNCTION find_spots_within_radius(
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    radius_km DOUBLE PRECISION
)
RETURNS TABLE (
    id UUID,
    name VARCHAR,
    description TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,
    region VARCHAR,
    country VARCHAR,
    access_type VARCHAR,
    depth_min_m DECIMAL,
    depth_max_m DECIMAL,
    difficulty VARCHAR,
    target_species TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        s.name,
        s.description,
        ST_Y(s.location::geometry) AS latitude,
        ST_X(s.location::geometry) AS longitude,
        ST_Distance(s.location, ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) / 1000 AS distance_km,
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
        ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography,
        radius_km * 1000
    )
    ORDER BY distance_km;
END;
$$ LANGUAGE plpgsql;
