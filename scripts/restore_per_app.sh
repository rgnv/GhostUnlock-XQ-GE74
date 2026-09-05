#!/bin/bash
# Restore per-app backups (data.tar / userde.tar / extdata.tar + APKs) to a
# rooted device. See README "Data migration tooling" for the layout.
# usage: restore_per_app.sh <serial> <backup_root> <package...>
#   reads package names from stdin if none are given as arguments.
# Requires: KernelSU root (su), Play Protect ADB verification disabled:
#   adb shell su -c 'settings put global verifier_verify_adb_installs 0'
set -u
SERIAL="${1:?usage: $0 <serial> <backup_root> [package ...]}"
shift
BACKUP_SRC="${1:?usage: $0 <serial> <backup_root> [package ...]}"
shift
A="adb -s $SERIAL"
TMP=/data/local/tmp

if [ $# -gt 0 ]; then
  LIST=$(printf '%s\n' "$@")
else
  LIST=$(cat)
fi

# SELinux permissive while moving app data around; re-enforced at the end.
$A shell su -c setenforce 0

printf '%s\n' "$LIST" | while IFS= read -r pkg; do
  [ -z "$pkg" ] && continue
  echo "=== $(date +%T) RESTORE $pkg ==="
  if ! $A shell "pm path --user 0 $pkg" </dev/null 2>/dev/null | grep -q package:; then
    # push apks, install from device storage (fast, avoids streamed-install stalls)
    for a in "$BACKUP_SRC/$pkg/"*.apk; do
      [ -e "$a" ] || continue
      $A push "$a" "$TMP/r_$(basename "$a")" </dev/null >/dev/null
    done
    APKS_ONDEV=$($A shell "ls $TMP/r_*.apk 2>/dev/null" | tr -d '\r' | sort)
    CNT=$(echo "$APKS_ONDEV" | grep -c .)
    if [ "$CNT" -eq 1 ]; then
      $A shell "su -c 'pm install -r -g $(echo "$APKS_ONDEV" | head -1)'" </dev/null 2>&1 | tail -1
    elif [ "$CNT" -gt 1 ]; then
      SZ=$(du -cb $APKS_ONDEV | tail -1 | cut -f1)
      SID=$($A shell "su -c 'pm install-create -r -g -S $SZ'" </dev/null 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+')
      for a in $APKS_ONDEV; do
        BSZ=$($A shell "su -c 'stat -c%s $a'" </dev/null 2>/dev/null | tr -d '\r')
        $A shell "su -c 'pm install-write -S $BSZ $SID $(basename "$a") $a'" </dev/null 2>&1 | tail -1
      done
      $A shell "su -c 'pm install-commit $SID'" </dev/null 2>&1 | tail -1
    fi
    $A shell "su -c 'rm -f $TMP/r_*.apk'" </dev/null >/dev/null
  fi
  if ! $A shell "pm path --user 0 $pkg" </dev/null 2>/dev/null | grep -q package:; then
    echo "  ERROR: install failed for $pkg"; continue
  fi
  UID_NEW=$($A shell "dumpsys package $pkg" </dev/null 2>/dev/null | grep -m1 -E '^ *uid=[0-9]+ ' | sed 's/.*uid=\([0-9]*\).*/\1/' | tr -d '\r')
  [ -z "$UID_NEW" ] && { echo "  WARN: no uid for $pkg"; continue; }
  for t in data userde extdata; do
    [ -s "$BACKUP_SRC/$pkg/$t.tar" ] || continue
    case $t in data) DIR=/data/user/0;; userde) DIR=/data/user_de/0;; extdata) DIR=/data/media/0;; esac
    $A push "$BACKUP_SRC/$pkg/$t.tar" "$TMP/r.tar" </dev/null >/dev/null
    $A shell "su -c 'tar -C $DIR -xf $TMP/r.tar 2>/dev/null; chown -R $UID_NEW:$UID_NEW $DIR/$pkg; restorecon -R $DIR/$pkg'" </dev/null 2>/dev/null
  done
  $A shell "rm -f $TMP/r.tar" </dev/null >/dev/null
  echo "=== DONE $pkg uid=$UID_NEW ==="
done

$A shell su -c setenforce 1
$A shell su -c getenforce
