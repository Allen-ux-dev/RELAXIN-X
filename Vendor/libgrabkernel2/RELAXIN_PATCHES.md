# Relaxin integration

Upstream: `alfiecg24/libgrabkernel2`

Revision: `95c5f89a06c2fb5d0f53bbac55cf86ad85cbbc07`

The Dopamine-lbr77 Xcode 27 and robust-download changes are applied directly
to this source copy; Relaxin does not keep or apply a separate patch queue.

Relaxin additionally uses namespaced public headers and target-scoped header
search paths so the sources compile directly in `RelaxinEngine`, and routes
library diagnostics through `rlx_engine_log`. AppleDB's `prerequisiteBuild`
value is logged through its JSON description because the API may encode it as
either a string or an array, and inactive links are excluded using their
boolean value. Relaxin also adds an error-reporting kernelcache entry point so
AppleDB, range-download, and file-write failures can cross the engine boundary
instead of remaining log-only diagnostics. Recoverable range-attempt failures
are warnings, while failure across every candidate is terminal. The
full-firmware download fallback from the robust-download patch is intentionally
removed; Relaxin never downloads a complete IPSW or OTA archive.

Relaxin verifies each downloaded kernelcache against the digest in the selected
BuildManifest identity. The engine prefers the current system kernelcache for
TrollStore installations, then searches the app bundle and Documents directory
for a nonempty regular file named `kernelcache` or prefixed with `kernelcache`,
before falling back to a verified network download.
