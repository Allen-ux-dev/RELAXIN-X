# Vendored Interface Notices

This directory contains only the interface inputs used by Relaxin's direct
BaseBin build. The original RootHide repository-wide license manifests remain
beside the `include` and `lib` snapshots for provenance; this notice replaces
those broad inventories in the App's generated license report.

## Snapshot-specific licenses beside the inputs

- Apple-derived declarations retain their source notices. Depending on the
  file, those notices reference the Apple Public Source License, Apache
  License 2.0, or a BSD license. The APSL 2.0 text is also filed as
  `include/APSL-2.0/LICENSE`.
- `include/CoreSymbolication.h` retains Mountainstorm's MIT notice; the
  extracted text is `include/CoreSymbolication/LICENSE`.
- `include/libarchive/` retains Tim Kientzle's BSD-2-Clause notices; the
  extracted text is `include/libarchive/LICENSE`.
- `include/substrate.h` retains Jay Freeman's BSD-3-Clause notice; the
  extracted text is `include/substrate/LICENSE`.
- `include/libkrw/` is covered by `include/libkrw/LICENSE` (MIT, Siguza).
- `include/libgrabkernel2/` is covered by the top-level `libgrabkernel2`
  license.
- `include/roothide.h` and `lib/libroothide.tbd` come from the RootHide header
  and linker-interface repositories. Their repository license classifies
  otherwise unattributed files as public domain under the Unlicense, reproduced
  below.
- `lib/libellekit.tbd` is a link-only interface for the separately attributed
  ElleKit runtime.

## Unlicense

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org/>
