#!/usr/bin/env python3
"""
Fetch REAL chlorophyll data from Copernicus WMTS for batch 5 spots.
This is PRODUCTION data, not a test.

Based on: CopernicusWMTSClient.kt
Product: OCEANCOLOUR_GLO_BGC_L3_NRT_009_101 (L3 NRT - actual satellite measurements)
"""

import urllib.request
import urllib.error
import time
import math
import json
from datetime import datetime, timedelta
import sys
import ssl

# Copernicus WMTS configuration
WMTS_BASE = "https://wmts.marine.copernicus.eu/teroWmts"
CHL_LAYER = "OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/cmems_obs-oc_glo_bgc-plankton_nrt_l3-multi-4km_P1D_202411/CHL"

# Tile configuration for level 8
TILE_MATRIX_LEVEL = 8
TILES_X = 512
TILES_Y = 256
TILE_SIZE = 256

# Rate limiting
RATE_LIMIT_SECONDS = 1.0  # 1 request per second

def calculate_tile_coords(lat: float, lon: float):
    """Calculate WMTS tile coordinates and pixel position for a lat/lon."""
    tile_width = 360.0 / TILES_X
    tile_height = 180.0 / TILES_Y
    
    tile_col = int(math.floor((lon + 180.0) / tile_width))
    tile_col = max(0, min(tile_col, TILES_X - 1))
    
    tile_row = int(math.floor((90.0 - lat) / tile_height))
    tile_row = max(0, min(tile_row, TILES_Y - 1))
    
    tile_lon_min = -180.0 + (tile_col * tile_width)
    tile_lat_max = 90.0 - (tile_row * tile_height)
    
    pixel_x = int((lon - tile_lon_min) / tile_width * TILE_SIZE)
    pixel_x = max(0, min(pixel_x, TILE_SIZE - 1))
    
    pixel_y = int((tile_lat_max - lat) / tile_height * TILE_SIZE)
    pixel_y = max(0, min(pixel_y, TILE_SIZE - 1))
    
    return tile_col, tile_row, pixel_x, pixel_y

def build_wmts_url(lat: float, lon: float, date: str) -> str:
    """Build the WMTS GetFeatureInfo URL for chlorophyll."""
    tile_col, tile_row, pixel_x, pixel_y = calculate_tile_coords(lat, lon)
    
    url = (
        f"{WMTS_BASE}?"
        f"SERVICE=WMTS"
        f"&VERSION=1.0.0"
        f"&REQUEST=GetFeatureInfo"
        f"&LAYER={CHL_LAYER}"
        f"&STYLE=cmap:viridis"
        f"&FORMAT=image/png"
        f"&TILEMATRIXSET=EPSG:4326"
        f"&TILEMATRIX={TILE_MATRIX_LEVEL}"
        f"&TILEROW={tile_row}"
        f"&TILECOL={tile_col}"
        f"&I={pixel_x}"
        f"&J={pixel_y}"
        f"&INFOFORMAT=application/json"
        f"&TIME={date}T00:00:00Z"
    )
    return url

def parse_chlorophyll_response(response_text: str) -> float | None:
    """Parse chlorophyll value from WMTS GetFeatureInfo JSON response."""
    try:
        # Check for null value (cloud cover, no satellite data)
        if '"value":null' in response_text or '"value": null' in response_text:
            return None
        
        data = json.loads(response_text)
        
        # Navigate the GeoJSON structure
        if 'features' in data and len(data['features']) > 0:
            props = data['features'][0].get('properties', {})
            value = props.get('value')
            units = props.get('units', '')
            
            # Verify we got chlorophyll data (units should be "milligram m-3")
            if value is not None and isinstance(value, (int, float)) and value > 0:
                if 'milligram' in units or 'mg' in units.lower():
                    return float(value)
        
        return None
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        return None

def fetch_chlorophyll(lat: float, lon: float, max_days_back: int = 4) -> tuple[float | None, str]:
    """
    Fetch chlorophyll for a location, trying recent dates.
    Returns (chlorophyll_value, status) where status is 'ok', 'null', or 'error'.
    """
    # Create SSL context
    ctx = ssl.create_default_context()
    
    # Try yesterday first, then go back a few days
    for days_back in range(1, max_days_back + 1):
        date = (datetime.now() - timedelta(days=days_back)).strftime('%Y-%m-%d')
        url = build_wmts_url(lat, lon, date)
        
        try:
            req = urllib.request.Request(url, headers={
                'User-Agent': 'Shaka-API/1.0 (Marine Research)',
                'Accept': 'application/json'
            })
            
            with urllib.request.urlopen(req, timeout=30, context=ctx) as response:
                response_text = response.read().decode('utf-8')
                chl = parse_chlorophyll_response(response_text)
                if chl is not None:
                    return chl, 'ok'
                # Got response but value was null (cloud cover)
                # Continue to try older date
                
        except urllib.error.HTTPError as e:
            if e.code >= 500:
                # Server error, might recover with retry
                time.sleep(2)
                continue
            else:
                # Client error (4xx), unlikely to succeed
                return None, 'error'
        except urllib.error.URLError as e:
            time.sleep(2)
            continue
        except Exception as e:
            return None, 'error'
    
    # All dates returned null (cloud cover for all recent days)
    return None, 'null'

def main():
    print("=" * 60)
    print("COPERNICUS CHLOROPHYLL DATA FETCH - BATCH 5")
    print("=" * 60)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Read spot list - format is: name|lat|lon
    spots = []
    with open('/tmp/batch5.txt', 'r') as f:
        for idx, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            parts = line.split('|')
            if len(parts) >= 3:
                try:
                    name = parts[0].strip()
                    lat = float(parts[1].strip())
                    lon = float(parts[2].strip())
                    spot_id = str(idx)  # Use line number as ID
                    spots.append((spot_id, name, lat, lon))
                except (ValueError, IndexError):
                    continue
    
    print(f"Loaded {len(spots)} spots from batch5.txt")
    print()
    
    # Results tracking
    results = []
    success_count = 0
    null_count = 0
    fail_count = 0
    
    # Process each spot
    for i, (spot_id, name, lat, lon) in enumerate(spots, 1):
        print(f"[{i:3d}/{len(spots)}] {name[:40]:<40} ({lat:8.4f}, {lon:9.4f}) ... ", end='', flush=True)
        
        chl_value, status = fetch_chlorophyll(lat, lon)
        
        if status == 'ok' and chl_value is not None:
            result_str = f"{spot_id}|{lat}|{lon}|{chl_value:.4f}"
            print(f"CHL = {chl_value:.4f} mg/m³")
            success_count += 1
        elif status == 'null':
            result_str = f"{spot_id}|{lat}|{lon}|null"
            print("null (cloud cover)")
            null_count += 1
        else:
            result_str = f"{spot_id}|{lat}|{lon}|FAIL"
            print("FAIL")
            fail_count += 1
        
        results.append(result_str)
        
        # Rate limiting between requests
        if i < len(spots):
            time.sleep(RATE_LIMIT_SECONDS)
    
    # Write results
    output_file = '/tmp/chlorophyll_batch5_results.txt'
    with open(output_file, 'w') as f:
        f.write('\n'.join(results))
        f.write('\n')
    
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total spots processed:      {len(spots)}")
    print(f"Spots with chlorophyll:     {success_count}")
    print(f"Spots with null (clouds):   {null_count}")
    print(f"Failures (errors):          {fail_count}")
    print()
    print(f"Results saved to: {output_file}")
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == '__main__':
    main()
