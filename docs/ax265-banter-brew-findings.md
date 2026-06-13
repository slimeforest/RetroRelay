# AX265 Banter BREW Findings

Downloaded package inspected:

`/Users/jack/Downloads/AX265 (Banter)`

This package is useful research material, but it is not directly flashable to the
LG Rumor2 / LX265.

## Contents

- `AX265 (T265AV04)/T265AV04_01.bin`
  - Stock AX265 firmware image.
- `T265AV04 [BREW DRM patched]/T265AV04_01_patched.bin`
  - Patched AX265 firmware image.
- `AX265 (T265AV04)/Brew_Script/brew`
  - AX265 BREW filesystem payload with many real `.mif`, `.mod`, `.sig`, and
    `.bar` app bundles.
- `AX265.dll` and `LGNPST_GenericModel_Ver_1_0_12_0.dll`
  - LGNPST model/support DLLs for AX265 flashing workflows.

## Patch Meaning

The patched readme says:

> Patched firmware with BREW ESN and date checks removed.

Binary comparison found only 8 changed bytes between the stock and patched AX265
firmware:

```text
offset 8106653: f7 b5 06 1c -> 01 20 70 47
offset 8108117: 30 b5 05 1c -> 01 20 70 47
```

In ARM Thumb form, `01 20 70 47` is:

```text
movs r0, #1
bx   lr
```

So the patch appears to replace two check functions with "return success".
This is exactly the class of patch that could allow unsigned/expired BREW app
loading on the target firmware.

## Why It Does Not Directly Solve Rumor2

The Rumor2 is LX265. This package is AX265/T265AV04 firmware.

Do not flash the AX265 image to the Rumor2. Even if the devices are visually and
architecturally similar, firmware images are model/carrier/build specific.

The useful part is the method:

1. Find a Rumor2/LX265 firmware image.
2. Locate the equivalent BREW ESN/date check routines.
3. Patch the equivalent functions to return success.
4. Flash only after confirming a recovery path.

## App Layout Evidence

The AX265 BREW app layout matches the shape seen on the Rumor2:

```text
/brew/mif/<id>.mif
/brew/mod/<id>/<module>.mod
/brew/mod/<id>/<module>.sig
/brew/mod/<id>/*.bar
```

The AX265 package contains 26 `.mif` files, 26 `.mod` files, and 26 `.sig`
files, which makes it a good reference for native BREW app packaging.

## Current Takeaway

This is very useful for a BREW-native path, but not for Java MIDlet installation
yet. It suggests the realistic bypass is not generic custom firmware, but a
small BREW DRM/signature-check patch applied to the exact target firmware.

Next research target:

- Find a Sprint LG Rumor2 / LG-LX265 firmware dump or update image.
- Search it for code patterns analogous to the AX265 patched routines.
- Keep using BitPim for filesystem inspection; avoid firmware flashing until a
  model-correct image and recovery method are known.
