"""
Streaming FES2022 downloader.

Replaces pyTMD.datasets.fetch_aviso_fes for the production bootstrap.
pyTMD buffers each ~1GB .xz constituent file in memory while decompressing,
which OOMs the Railway container (root cause of the Apr/Jun 2026 crash
loops). This module streams FTP -> lzma -> disk in fixed-size chunks so
peak memory stays constant regardless of file size.
"""

import ftplib
import logging
import lzma
import pathlib

logger = logging.getLogger("downloader")

CHUNK_SIZE = 1 << 20  # 1 MiB read chunks

AVISO_HOST = "ftp-access.aviso.altimetry.fr"
REMOTE_DIR = "/auxiliary/tide_model/fes2022b/ocean_tide_extrapolated"
EXPECTED_FILE_COUNT = 34


class StreamingXzWriter:
    """Incrementally decompress .xz bytes to a file without buffering.

    Feed compressed chunks via write(); decompressed output is flushed to
    dest_path as it is produced. Memory use is bounded by CHUNK_SIZE plus
    lzma's internal dictionary (~64MB for FES files), not the file size.
    """

    def __init__(self, dest_path: pathlib.Path):
        self.dest_path = dest_path
        self._decompressor = lzma.LZMADecompressor()
        self._out = open(dest_path, "wb")
        self.bytes_in = 0
        self.bytes_out = 0

    def write(self, chunk: bytes) -> None:
        self.bytes_in += len(chunk)
        decompressed = self._decompressor.decompress(chunk)
        if decompressed:
            self._out.write(decompressed)
            self.bytes_out += len(decompressed)

    def close(self) -> None:
        self._out.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        if exc_type is not None:
            # Partial output is useless; remove so resume logic re-fetches.
            self.dest_path.unlink(missing_ok=True)


def _connect(user: str, password: str) -> ftplib.FTP:
    ftp = ftplib.FTP(AVISO_HOST, timeout=120)
    ftp.login(user, password)
    return ftp


def _list_remote_files(ftp: ftplib.FTP) -> list[str]:
    names = ftp.nlst(REMOTE_DIR)
    return sorted(n.rsplit("/", 1)[-1] for n in names if n.endswith(".nc.xz"))


def _fetch_one(ftp: ftplib.FTP, remote_name: str, dest_dir: pathlib.Path) -> None:
    """Stream one .nc.xz file from FTP, decompressing to <name>.nc on disk.

    Writes to a .part temp file and renames on success, so any file that
    exists under its final name is known-complete (file-level resume).
    """
    final_path = dest_dir / remote_name.removesuffix(".xz")
    if final_path.exists() and final_path.stat().st_size > 0:
        logger.info("Skipping %s (already present)", final_path.name)
        return

    tmp_path = final_path.with_suffix(final_path.suffix + ".part")
    with StreamingXzWriter(tmp_path) as writer:
        ftp.retrbinary(
            f"RETR {REMOTE_DIR}/{remote_name}", writer.write, blocksize=CHUNK_SIZE
        )
    tmp_path.rename(final_path)
    logger.info(
        "Downloaded %s (%.0f MB compressed -> %.0f MB)",
        final_path.name, writer.bytes_in / 1e6, writer.bytes_out / 1e6,
    )


def download_all(data_dir: str, user: str, password: str) -> None:
    """Download every FES2022 extrapolated constituent, skipping complete files."""
    dest_dir = pathlib.Path(data_dir) / "fes2022b" / "ocean_tide_extrapolated"
    dest_dir.mkdir(parents=True, exist_ok=True)
    # Clean up partials from a previous crashed run
    for stale in dest_dir.glob("*.part"):
        stale.unlink()

    ftp = _connect(user, password)
    try:
        remote_files = _list_remote_files(ftp)
        logger.info("AVISO lists %d constituent files", len(remote_files))
        for name in remote_files:
            _fetch_one(ftp, name, dest_dir)
    finally:
        try:
            ftp.quit()
        except Exception:
            ftp.close()
