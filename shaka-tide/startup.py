"""
First-boot FES2022 data downloader.

Checks if constituent files exist on the Railway volume.
If missing, downloads ocean_tide_extrapolated from AVISO FTP.
This only runs once -- subsequent deployments find data already present.
"""

import gzip
import logging
import os
import pathlib
import shutil
import time

logger = logging.getLogger("startup")


def _compress_existing_nc_files(data_dir: str) -> int:
    """Gzip any uncompressed .nc files left from a previous compressed=False download."""
    count = 0
    for nc_file in pathlib.Path(data_dir).rglob("*.nc"):
        gz_file = nc_file.with_suffix(".nc.gz")
        if gz_file.exists():
            continue
        logger.info("Compressing %s -> %s", nc_file.name, gz_file.name)
        with open(nc_file, "rb") as f_in, gzip.open(gz_file, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        nc_file.unlink()
        count += 1
    return count


def fes_data_ready(data_dir: str) -> bool:
    """Check if FES2022 extrapolated constituent NetCDF files are present."""
    p = pathlib.Path(data_dir)
    extrapolated = p / "fes2022b" / "ocean_tide_extrapolated"
    if not extrapolated.exists():
        return False
    nc_files = list(extrapolated.glob("*.nc.gz"))
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
            compressed=True,
            timeout=360,
        )
        elapsed = time.time() - start
        logger.info("FES2022 download complete in %.0f seconds", elapsed)
    except Exception:
        logger.exception("FES2022 download failed")
        raise


def ensure_fes_data(data_dir: str, user: str, password: str) -> None:
    """Ensure FES2022 data is available, downloading if necessary."""
    compressed = _compress_existing_nc_files(data_dir)
    if compressed:
        logger.info("Compressed %d existing .nc files to .nc.gz", compressed)

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
