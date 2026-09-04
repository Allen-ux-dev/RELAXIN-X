# zstd

This directory contains the `common` and `decompress` sources from
[facebook/zstd](https://github.com/facebook/zstd) revision
`5c7b7bad26808e6b40ac3b3d0075466e27738a9d`, the revision resolved by the
Dopamine2-roothide Xcode project.

Relaxin compiles this decompression-only subset directly into `RelaxinEngine`
instead of adding the upstream Swift package dependency. The sources are
unmodified and distributed under the BSD license in `LICENSE`.
