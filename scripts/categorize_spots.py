#!/usr/bin/env python3
"""Categorize land spots into NEAR (<500m from water) vs FAR (>500m)"""

import urllib.request
import json
import time
import sys

API_URL = "https://is-on-water.balbona.me/api/v1/get/{lat}/{lon}"

def is_water(lat, lon):
    """Check if coordinate is in water"""
    try:
        url = API_URL.format(lat=lat, lon=lon)
        with urllib.request.urlopen(url, timeout=10) as r:
            data = json.loads(r.read().decode())
            return data.get("isWater", False)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None

def find_water_direction(lat, lon):
    """Find which direction (N/S/E/W) leads to water at 500m"""
    offset = 0.005  # ~500m
    
    directions = [
        ("N", lat + offset, lon),
        ("S", lat - offset, lon),
        ("E", lat, lon + offset),
        ("W", lat, lon - offset),
    ]
    
    for dir_name, test_lat, test_lon in directions:
        if is_water(test_lat, test_lon):
            return dir_name
    return None

def main():
    near_spots = []
    far_spots = []
    
    # Read land spots
    with open("/tmp/land_spots.txt") as f:
        spots = [line.strip().split("|") for line in f if line.strip()]
    
    total = len(spots)
    print(f"Processing {total} land spots...", file=sys.stderr)
    
    for i, (spot_id, lat, lon) in enumerate(spots):
        lat, lon = float(lat), float(lon)
        
        direction = find_water_direction(lat, lon)
        
        if direction:
            near_spots.append((spot_id, lat, lon, direction))
            print(f"NEAR|{spot_id}|{lat}|{lon}|{direction}")
        else:
            far_spots.append((spot_id, lat, lon))
            print(f"FAR|{spot_id}|{lat}|{lon}")
        
        if (i + 1) % 25 == 0:
            print(f"Progress: {i+1}/{total}", file=sys.stderr)
        
        time.sleep(0.1)  # Rate limit
    
    print(f"\n=== COMPLETE ===", file=sys.stderr)
    print(f"NEAR: {len(near_spots)}", file=sys.stderr)
    print(f"FAR: {len(far_spots)}", file=sys.stderr)
    
    # Save results
    with open("/tmp/near_spots.txt", "w") as f:
        for spot_id, lat, lon, direction in near_spots:
            f.write(f"{spot_id}|{lat}|{lon}|{direction}\n")
    
    with open("/tmp/far_spots.txt", "w") as f:
        for spot_id, lat, lon in far_spots:
            f.write(f"{spot_id}|{lat}|{lon}\n")

if __name__ == "__main__":
    main()
