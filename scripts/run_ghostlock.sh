#!/bin/bash
# Push and run GhostLock on the device, then sanity-check root state.
# usage: run_ghostlock.sh [serial]   (serial = adb device id, optional)
set -euo pipefail
SERIAL="${1:-}"
A="adb"
[ -n "$SERIAL" ] && A="adb -s $SERIAL"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

$A push "$REPO_DIR/prebuilt/ghostlock" /data/local/tmp/ghostlock >/dev/null
$A shell chmod 755 /data/local/tmp/ghostlock
$A shell sha256sum /data/local/tmp/ghostlock
echo "--- kernel ---"
$A shell uname -r
echo "--- running exploit (one attempt per boot after the stack-writer stage) ---"
$A shell /data/local/tmp/ghostlock
echo "--- post state ---"
$A shell 'cat /data/local/tmp/.ghostlock_ksu.log 2>/dev/null; grep -q kernelsu /proc/modules && echo "KernelSU: loaded" || echo "KernelSU: not loaded"'
echo "--- su check (needs KernelSU manager installed with a libksud.so) ---"
$A shell 'su -c id' 2>&1 || true
