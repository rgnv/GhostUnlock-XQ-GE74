#!/bin/bash
# Verify a per-app restore: installed? and data file counts on device.
# usage: verify_restore.sh <serial> <package...>   (stdin list if no args)
set -u
SERIAL="${1:?usage: $0 <serial> [package ...]}"
shift
A="adb -s $SERIAL"
TMP=/data/local/tmp

if [ $# -gt 0 ]; then
  LIST=$(printf '%s\n' "$@")
else
  LIST=$(cat)
fi

printf '%s\n' "$LIST" | while IFS= read -r pkg; do
  [ -z "$pkg" ] && continue
  P=$($A shell "pm path --user 0 $pkg" </dev/null 2>/dev/null | grep -c package:)
  F=$($A shell "su -c 'find /data/user/0/$pkg -type f -o -type l 2>/dev/null | wc -l'" </dev/null 2>/dev/null | tr -d '\r')
  S=$($A shell "su -c 'du -sk /data/user/0/$pkg 2>/dev/null | cut -f1'" </dev/null 2>/dev/null | tr -d '\r')
  echo "$pkg|installed=$P|files=$F|kB=$S"
done
