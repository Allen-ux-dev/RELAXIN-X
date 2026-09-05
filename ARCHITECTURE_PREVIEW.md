# RELAXIN-X Architecture Preview

> [!WARNING]
> **Architecture preview only. No real-device verification has been performed for this Prism / Runtime integration.**
>
> This branch demonstrates an architectural direction and source-level integration. It must not be treated as a stable or production-ready jailbreak release until the complete flow has been verified on supported physical devices.
>
> **仅用于架构预览。当前 Prism / Runtime 集成尚未进行真机完整验证。** 本分支用于展示架构理念与源码级集成，在完成支持设备上的完整真机验证前，不应视为稳定或可用于日常设备的越狱发行版。

## Architectural direction

RELAXIN-X is moving away from a legacy-centered design toward a capability-driven Runtime model:

```text
Client / Prism
      ↓
Runtime Descriptor
      ↓
Capabilities
      ↓
Provider Registry
      ↓
Resolver / Policy
      ↓
Typed Runtime Services
```

The intent is **modern first, legacy compatible, but no longer legacy-centered**.

BaseBin / the existing bootstrap are currently retained for compatibility with the existing ecosystem, including Sileo/Zebra and current bootstrap assumptions. They are not intended to be permanent architectural requirements for every new Runtime client.

Prism is designed around typed capabilities rather than a hard dependency on BaseBin. In the current integration it can use the existing APT/dpkg compatibility path, while the Runtime architecture also permits future providers to satisfy the same package/application/background capabilities without requiring product-name-specific branches.

## Prism Store integration

The current architecture includes:

- Sileo / Zebra / Prism selectable package-manager intent
- a final package-manager confirmation boundary during the jailbreak flow
- `Prism.app` + `prismd` packaging and lifecycle integration
- typed Runtime Service communication
- provider registry / resolver policy
- transaction-level provider pinning
- provider health and reconnect generation tracking
- package transaction / journal / reconcile / recovery models
- environment inspection and targeted Prism repair states

## Verification status

Verified so far:

- source/host contract tests
- PrismCore test suite (221 tests in the successful Mac build log)
- Xcode compilation on the maintainer's Mac
- RELAXIN-X IPA build completion

Not yet verified:

- a complete jailbreak run on a physical supported iPhone
- real-device Prism installation and daemon lifecycle
- real repository refresh through the deployed environment
- real package install / upgrade / downgrade / removal
- reboot/reconnect/recovery behavior on a physical device

Until those device tests are complete, capability availability must remain fail-closed and this branch should be described as an **architecture preview**, not a completed device-ready implementation.

## Architecture Preview 1 build artifact

The maintainer produced the following unsigned IPA from the successful Mac build. Any GitHub Release asset published as Architecture Preview 1 should match this checksum exactly:

```text
Suggested release: RELAXIN-X Architecture Preview 1
Suggested tag:     v0.5.0-arch-preview.1
Suggested asset:   RELAXIN-X-v0.5.0-arch-preview.1.ipa
File size:         35,969,121 bytes
SHA-256:           93a72b833a89ca7d22df0972eb4d427c734a05898d1b68a93b312a03e4e4273c
Bundle ID:         com.aapl.relaxin
Display name:      RELAXIN-X
```

This checksum records the Mac-built preview artifact only. It does **not** indicate successful installation, jailbreak execution, or package-management behavior on a physical device.
