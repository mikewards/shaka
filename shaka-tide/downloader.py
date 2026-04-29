"""
Streaming FES2022 downloader.

Replaces pyTMD.datasets.fetch_aviso_fes for the production bootstrap.
pyTMD buffers each ~1GB .xz constituent file in memory while decompressing,
which OOMs the Railway container (root cause of the Apr/Jun 2026 crash
loops). This module streams FTP -> lzma -> disk in fixed-size chunks so
peak memory stays constant regardless of file size.
"""

import logging
import lzma
import pathlib

logger = logging.getLogger("downloader")

CHUNK_SIZE = 1 << 20  # 1 MiB read chunks


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
