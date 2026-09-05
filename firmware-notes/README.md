# Firmware — not distributed here

Sony firmware is copyrighted and is **not** included in this repository.
Everything exploit-related that is *ours* (offsets, binaries, scripts) is
included; the one input you must obtain yourself is the boot image matching
your build.

## Getting your own boot image

1. Download the firmware set for **your** exact model/build with XperiFirm
   (or reuse a copy of your own firmware you already have).
   Target build for the bundled offsets: `73.0.A.2.53`.
2. The partition file you need is `boot_X-FLASH-ALL-DCBF.sin` (or the
   region-specific equivalent). Extract it:

   ```sh
   scripts/extract_boot_from_sin.sh boot_X-FLASH-ALL-DCBF.sin .
   ```

   Sony's current SIN v6 ("cms") files are plain tar archives; the script
   just unpacks and renames `boot.000` → `boot.img`.

3. Optionally carve `xbl_config` from `bootloader_X-FLASH-ALL-DCBF.sin`
   (`bootloader.000` inside is a Qualcomm X_BOOT container):

   ```sh
   tar xf bootloader_X-FLASH-ALL-DCBF.sin
   python3 scripts/carve_xbl_config.py bootloader.000 .
   ```

4. Run the extractor (see README §"How the offsets were extracted").

Verify the kernel release you extracted matches the device:

```sh
adb shell uname -r
# 6.12.38-android16-5-gcaefa63e005e-ab14676683-4k  ← bundled offsets match this
```
