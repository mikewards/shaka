"""
First-boot FES2022 data downloader.

Checks if constituent files exist on the Railway volume.
If missing, downloads ocean_tide_extrapolated from AVISO FTP.
This only runs once -- subsequent deployments find data already present.
"""

import logging
import os
import pathlib
import time

logger = logging.getLogger("startup")


def fes_data_ready(data_dir: str) -> bool:
    """Check if FES2022 extrapolated constituent NetCDF files are present."""
    p = pathlib.Path(data_dir)
    extrapolated = p / "fes2022b" / "ocean_tide_extrapolated"
    if not extrapolated.exists():
        return False
    nc_files = list(extrapolated.glob("*.nc"))
    return len(nc_files) >= 34


def download_fes2022(data_dir: str, user: str, password: str) -> None:
    """Download FES2022 ocean_tide + ocean_tide_extrapolated from AVISO FTP via pyTMD."""
    import pyTMD.datasets

    logger.info("Starting FES2022 download to %s (this may take 15-30 minutes)...", data_dir)
    os.makedirs(data_dir, exist_ok=True)

    start = time.time()
    try:
        pyTMD.datasets.fetch_aviso_fes(
            "FES2022",
            directory=data_dir,
            user=user,
            password=password,
            extrapolated=True,
            compressed=False,
            timeout=360,
        )
        elapsed = time.time() - start
        logger.info("FES2022 download complete in %.0f seconds", elapsed)
    except Exception:
        logger.exception("FES2022 download failed")
        raise


def ensure_fes_data(data_dir: str, user: str, password: str) -> None:
    """Ensure FES2022 data is available, downloading if necessary."""
    if fes_data_ready(data_dir):
        logger.info("FES2022 data found at %s", data_dir)
        return

    if not user or not password:
        raise RuntimeError(
            "FES2022 data not found and AVISO_USER/AVISO_PASS not set. "
            "Cannot download constituent files."
        )

    download_fes2022(data_dir, user, password)

    if not fes_data_ready(data_dir):
        raise RuntimeError("FES2022 download completed but data validation failed")
