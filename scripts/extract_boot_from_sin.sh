#!/bin/bash
# Extract the kernel boot image from a Sony "SIN v6" (cms) partition file.
# New Sony SIN v6 files are plain tar archives.
# usage: extract_boot_from_sin.sh <boot_X-FLASH-ALL-*.sin> [outdir]
set -euo pipefail
SIN="${1:?usage: $0 <boot_*.sin> [outdir]}"
OUT="${2:-.}"

mkdir -p "$OUT"
tar tf "$SIN"            # expect: <name>.cms, <name>.000
tar xf "$SIN" -C "$OUT"
BASE=$(basename "$SIN" .sin)
mv "$OUT/${BASE%%_*}.000" "$OUT/boot.img" 2>/dev/null || true
file "$OUT/boot.img"
echo "kernel image: $OUT/boot.img"
