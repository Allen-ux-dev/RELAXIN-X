# Relaxin integration

Upstream: `dhinakg/partial`

Revision: `31667c15c069333400432fb0e367ac4787ec5ce0`

The source uses a namespaced public header and is compiled directly in
`RelaxinEngine`. Debug-only upstream `NSLog` calls are disabled because engine
logging is owned by `rlx_engine_log`; operational errors still propagate
through `NSError` to libgrabkernel2.
