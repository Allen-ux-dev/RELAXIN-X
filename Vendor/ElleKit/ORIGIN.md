# ElleKit

`CydiaSubstrate.framework` follows the fixed ElleKit fallback shipped by
Dopamine-lbr77:

- Repository: <https://github.com/Lakr233/dopamine-3.git>
- Revision: `7bceb857d224ba23c8b3b15905f0e7521cb1db2d`
- Source path:
  `BaseBin/_external/basebin/fallback/CydiaSubstrate.framework`
- Binary Git blob: `080365f5ffd5e58b4e543e257342623db830e8c0`
- Source SHA-256: `dc671cf69b64fcb267f9b38270479fc702cd3b1c60a15cf3d30a30e05441dbee`

Dopamine first imported this binary in commit
`b53a2253600a60e597c615915264ddb80dabe62a` on 2024-01-08. Its history does
not record the exact ElleKit source revision, so Relaxin does not attribute it
to a newer ElleKit release.

Dopamine copies the framework into `BaseBin/.build` and explicitly ad-hoc
signs its binary. Applying the same signing step produces the byte-identical
vendored binary:

- Architectures: `arm64`, `arm64e`
- Signed SHA-256: `ba353e3fdc21f46d141a56ab18e9cb5ba0039d7df3564a9084e6df27b76e9720`

`LICENSE` is copied byte-for-byte from ElleKit. It is also identical to
Dopamine-lbr77's `Application/Dopamine/Resources/LICENSE_ElleKit.md`.
