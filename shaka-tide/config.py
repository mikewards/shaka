import os

PORT = int(os.environ.get("PORT", "8000"))
FES_DATA_DIR = os.environ.get("FES_DATA_DIR", "/data/fes2022")
AVISO_USER = os.environ.get("AVISO_USER", "")
AVISO_PASS = os.environ.get("AVISO_PASS", "")

METERS_TO_FEET = 3.28084

# FES2022 model type to download (extrapolated fills coastal gaps)
FES_MODEL_TYPE = "FES2022"
FES_PRODUCT = "ocean_tide_extrapolated"

# LRU cache: round coordinates to this precision for cache key
COORD_PRECISION = 3  # ~111m resolution
