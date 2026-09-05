#!/usr/bin/env python3
"""Carve the xbl_config image out of a Qualcomm X_BOOT container.

The bootloader "cms" SIN extracts to a tar containing bootloader.000 — a
Qualcomm XBL loader container (magic 0xCE1AD63C) holding several images
concatenated after a directory table. Each directory entry is:

    u32 size, u32 pad, u8 name[16]  (name NUL-terminated)

Entries of interest: "xbl_config" (contains the FDT used to derive the
kernel physical load address for the ghostlock extractor).

usage: carve_xbl_config.py <bootloader.000> <outdir>
"""
import re
import struct
import sys
from pathlib import Path


def carve(container: bytes, want: bytes, outdir: Path) -> Path | None:
    m = re.search(re.escape(want) + rb"\x00", container)
    if not m:
        return None
    name_off = m.start()
    # entry: [u32 pad][u32 size][u64?] then name; walk back to find size field
    # observed layout: ... <u32 size> <name[16]>  -> size occupies 4 bytes
    # immediately before the name field's padding.
    for back in range(4, 24, 4):
        off, size = struct.unpack_from("<II", container, name_off - back)
        if 0 < off < len(container) and 0 < size < len(container) and off + size <= len(container):
            blob = container[off:off + size]
            if blob[:4] == b"\x7fELF" or blob[:4] == b"\xd0\x0d\xfe\xed":
                out = outdir / f"{want.decode()}.img"
                out.write_bytes(blob)
                return out
    return None


def main() -> None:
    src = Path(sys.argv[1])
    outdir = Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)
    data = src.read_bytes()

    carved = 0
    for name in (b"xbl_config", b"xbl_ramdump", b"xbl_ac_config"):
        out = carve(data, name, outdir)
        if out:
            print(f"carved {out} ({out.stat().st_size} bytes)")
            carved += 1
    if not carved:
        sys.exit("no xbl_config-like entries found")


if __name__ == "__main__":
    main()
