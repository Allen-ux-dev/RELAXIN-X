# Prism Runtime Bridge

This module contains the RELAXIN-X side of the typed Prism Runtime Service compatibility bridge.

## Build 52 compatibility baseline

The wire contract in this directory was validated against the user-supplied `Prism 0.4.1 Build 52` client and Complete Store source tree.

Observed compatibility requirements:

- Runtime identity: `dev.relaxin.runtime`
- Runtime service ID: `dev.relaxin.service.runtime`
- Baseline protocol version: `1`
- Framing: four-byte big-endian UInt32 payload length followed by JSON
- Maximum payload: 1 MiB
- Typed request/response envelopes, including versioned handshake

RELAXIN-X must only publish capabilities that have a real execution provider behind them. The default Build 52 host is therefore handshake-only and degraded until execution adapters are wired.

## Runtime endpoint

RELAXIN-X owns a dedicated Runtime Service socket:

```text
/var/run/relaxinx-runtime.sock
```

The path may be overridden internally with `RELAXINX_PRISM_RUNTIME_SOCKET` for development or migration testing. Prism remains product-neutral: its `prismd` Runtime Service discovery layer owns endpoint discovery and may also consume `PRISM_RUNTIME_SERVICE_SOCKET` for additional endpoints.

## Socket ownership boundary

`/var/run/prismd.sock` remains owned by Prism's privileged daemon. RELAXIN-X must never bind, unlink, replace, or hijack it.

The integrated topology is:

```text
Prism App
  |
  +-- /var/run/prismd.sock
        |
      prismd
        |-- existing Transaction / Journal / Recovery traffic
        `-- RuntimeServiceBridgeCoordinator
              |
              +-- discovery
              +-- versioned handshake
              `-- /var/run/relaxinx-runtime.sock
                      |
                    RELAXIN-X Runtime Service Host
```

`PrismUnixSocketRuntimeServiceServer` therefore serves only the dedicated RELAXIN-X endpoint and refuses to overwrite an existing socket endpoint.

## Startup behavior

The full RELAXIN-X app starts the Runtime Service Host during application initialization. Startup failure is logged as degraded/unavailable and does not abort the normal RELAXIN-X flow. RelaxinLite explicitly excludes these Runtime Service Host sources.

This app-lifetime host provides the Build 52 connection path. A later persistent/background host may replace the startup implementation without changing Prism's typed service contract or endpoint discovery semantics.

## Security boundary

The Prism-facing bridge remains typed and allowlisted. It must not expose arbitrary shell execution, arbitrary privileged filesystem writes, raw process injection, raw kernel operations, exploit acquisition internals, bootstrap paths, or other implementation details.

## Current integration state

Implemented:

- Build 52 wire models
- length-prefixed JSON codec
- versioned handshake
- stable runtime/service identity
- fail-closed capability publication
- framed request processor
- dedicated Unix-domain Runtime Service endpoint
- RELAXIN-X startup bootstrap
- Prism `prismd` default endpoint discovery
- environment override / additional endpoint support
- wire, endpoint, source-contract, and Unix socket round-trip host tests

Still intentionally unavailable until backed by real RELAXIN-X execution adapters:

- app install / register / replace / remove / refresh
- background privileged session
- optional injection service

Those capabilities must remain unavailable/degraded rather than being fabricated as ready.
