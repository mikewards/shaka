#!/usr/bin/env python3
"""
Test chlorophyll data retrieval for directional island spots.
Queries the Copernicus Marine WMTS service for CHL (chlorophyll-a) data.
"""

import urllib.request
import urllib.error
import json
import math
from datetime import datetime, timedelta

# WMTS configuration (from CopernicusWMTSClient.kt)
WMTS_BASE = "https://wmts.marine.copernicus.eu/teroWmts"
CHL_LAYER = "OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/cmems_obs-oc_glo_bgc-plankton_nrt_l3-multi-4km_P1D_202411/CHL"
TILE_MATRIX_LEVEL = 8
TILES_X = 512
TILES_Y = 256
TILE_SIZE = 256

# Spots to test (name, lat, lon)
SPOTS = [
    ("Santa Rosa Island N", 34.035, -120.1),
    ("Santa Rosa Island S", 33.895, -120.1),
    ("San Miguel Island N", 34.0883, -120.3667),
    ("Poor Knights N", -35.4417, 174.7333),
    ("Fiji Beqa N", -18.3683, 177.9833),
    ("Tubbataha N", 8.9483, 119.9),
    ("Cocos Island N", 5.54, -87.0583),
    ("Sipadan N", 4.13, 118.6283),
    ("Guadalupe N", 29.135, -118.2833),
    ("Galapagos Santa Cruz N", -0.445, -90.3),
]

def calculate_tile_coords(lat, lon):
    """Calculate WMTS tile and pixel coordinates for EPSG:4326."""
    tile_width = 360.0 / TILES_X
    tile_height = 180.0 / TILES_Y
    
    tile_col = int(math.floor((lon + 180.0) / tile_width))
    tile_col = max(0, min(TILES_X - 1, tile_col))
    
    tile_row = int(math.floor((90.0 - lat) / tile_height))
    tile_row = max(0, min(TILES_Y - 1, tile_row))
    
    # Calculate pixel position within tile
    tile_lon_min = -180.0 + (tile_col * tile_width)
    tile_lat_max = 90.0 - (tile_row * tile_height)
    
    pixel_x = int((lon - tile_lon_min) / tile_width * TILE_SIZE)
    pixel_x = max(0, min(TILE_SIZE - 1, pixel_x))
    
    pixel_y = int((tile_lat_max - lat) / tile_height * TILE_SIZE)
    pixel_y = max(0, min(TILE_SIZE - 1, pixel_y))
    
    return tile_col, tile_row, pixel_x, pixel_y

def get_chlorophyll(lat, lon, date_str):
    """
    Get chlorophyll-a concentration from Copernicus WMTS.
    Returns value in mg/m³ or None if unavailable.
    """
    tile_col, tile_row, pixel_x, pixel_y = calculate_tile_coords(lat, lon)
    
    url = (
        f"{WMTS_BASE}"
        f"?SERVICE=WMTS"
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
        f"&TIME={date_str}T00:00:00Z"
    )
    
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Shaka-Test/1.0')
        
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode('utf-8'))
        
        # Parse the response
        if 'features' in data and len(data['features']) > 0:
            props = data['features'][0].get('properties', {})
            value = props.get('value')
            units = props.get('units')
            
            if value is not None and units == 'milligram m-3':
                return float(value)
        
        return None
        
    except urllib.error.HTTPError as e:
        return f"HTTP Error: {e.code}"
    except urllib.error.URLError as e:
        return f"URL Error: {e.reason}"
    except Exception as e:
        return f"Error: {e}"

def main():
    print("=" * 80)
    print("Chlorophyll Data Retrieval Test for Directional Island Spots")
    print("=" * 80)
    print()
    
    # Try yesterday and up to 4 days back
    dates_to_try = []
    for days_back in range(1, 5):
        date = datetime.now() - timedelta(days=days_back)
        dates_to_try.append(date.strftime("%Y-%m-%d"))
    
    print(f"Testing dates: {', '.join(dates_to_try)}")
    print()
    
    # Header
    print(f"{'Spot Name':<25} | {'Coordinates':<22} | {'Chlorophyll (mg/m³)':<25}")
    print("-" * 80)
    
    results = []
    for name, lat, lon in SPOTS:
        # Try each date until we get data
        chl_value = None
        data_date = None
        
        for date_str in dates_to_try:
            result = get_chlorophyll(lat, lon, date_str)
            if result is not None and not isinstance(result, str):
                chl_value = result
                data_date = date_str
                break
            elif isinstance(result, str) and "Error" in result:
                chl_value = result
                break
        
        coords = f"({lat}, {lon})"
        
        if chl_value is None:
            chl_str = "null/cloud cover"
        elif isinstance(chl_value, str):
            chl_str = chl_value
        else:
            chl_str = f"{chl_value:.4f} ({data_date})"
        
        print(f"{name:<25} | {coords:<22} | {chl_str:<25}")
        results.append((name, lat, lon, chl_value, data_date))
    
    print("-" * 80)
    print()
    
    # Summary
    valid_count = sum(1 for _, _, _, v, _ in results if v is not None and not isinstance(v, str))
    print(f"Summary: {valid_count}/{len(results)} spots returned valid chlorophyll data")
    
    return results

if __name__ == "__main__":
    main()
