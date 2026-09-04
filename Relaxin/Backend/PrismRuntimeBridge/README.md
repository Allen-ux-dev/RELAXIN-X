# Prism Runtime Bridge

This module contains the RELAXIN-X side of the typed Prism Runtime Service compatibility bridge.

## Build 52 compatibility baseline

The wire contract in this directory was validated against the user-supplied `Prism 0.4.1 Build 52` unsigned IPA.

Observed compatibility requirements:

- Runtime identity: `dev.relaxin.runtime`
- Runtime service ID: `dev.relaxin.service.runtime`
- Baseline protocol version: `1`
- Framing: four-byte big-endian UInt32 payload length followed by JSON
- Maximum payload: 1 MiB
- Typed request/response envelopes, including versioned handshake

RELAXIN-X must only publish capabilities that have a real execution provider behind them. The default Build 52 host is therefore handshake-only and degraded until execution adapters are wired.

## Socket ownership boundary

Prism Build 52 uses `/var/run/prismd.sock` for its privileged daemon transport and also constructs its runtime-service transport against that same endpoint.

RELAXIN-X **must not** blindly bind, unlink, replace, or hijack `/var/run/prismd.sock`. Doing so would intercept Prism privileged traffic and break the existing Transaction / Journal / Recovery boundary.

The expected topology is:

```text
Prism App
  |
  +-- /var/run/prismd.sock
        |
      prismd
        |-- existing privileged request routing
        `-- Runtime Service routing
              |
            RELAXIN-X Runtime Service Host
```

`PrismUnixSocketRuntimeServiceServer` therefore accepts an explicit endpoint path and refuses to start when that endpoint already exists. It is suitable as a routed/private endpoint behind `prismd`, or for integration tests, but is not permission to take ownership of the Prism daemon socket.

## Security boundary

The Prism-facing bridge remains typed and allowlisted. It must not expose arbitrary shell execution, arbitrary privileged filesystem writes, raw process injection, raw kernel operations, exploit acquisition internals, bootstrap paths, or other implementation details.

## Current integration state

Implemented on the RELAXIN-X side:

- Build 52 wire models
- length-prefixed JSON codec
- versioned handshake
- stable runtime/service identity
- fail-closed capability publication
- framed request processor
- Unix-domain socket runtime-service endpoint
- wire and socket round-trip host tests

Still required for a complete Prism-app-to-RELAXIN-X route:

- the Build 52 `prismd` / privileged-protocol server-side router must forward Runtime Service requests to the RELAXIN-X runtime endpoint while preserving its existing privileged request handling.

That routing component is not contained in the supplied Prism IPA and must be integrated from the Prism server/daemon source rather than guessed or replaced by RELAXIN-X.
