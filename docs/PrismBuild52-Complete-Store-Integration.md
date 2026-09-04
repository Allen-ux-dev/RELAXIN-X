# Prism Build 52 Complete Store Integration

The Complete Store source confirms that `prismd` already owns the Runtime Service routing layer through `RuntimeServiceBridgeCoordinator`.

RELAXIN-X therefore exposes its own dedicated Runtime Service endpoint at:

```text
/var/run/relaxinx-runtime.sock
```

Prism keeps `/var/run/prismd.sock` exclusively for the privileged daemon path. `prismd` discovers the RELAXIN-X endpoint, performs the versioned Runtime Service handshake, and registers only the typed capabilities that RELAXIN-X actually reports.

The Prism-side Complete Store snapshot was updated so `DefaultRuntimeServiceEndpointSource` always includes the RELAXIN-X endpoint while preserving `PRISM_RUNTIME_SERVICE_SOCKET` for additional development/migration endpoints.

The RELAXIN-X full app starts the Runtime Service Host during app initialization. Startup failure is logged as degraded/unavailable and does not abort the main RELAXIN-X flow. RelaxinLite excludes the bridge startup sources.

Execution capabilities remain fail-closed until their real adapters are wired.
