# RELAXIN-X Architecture Preview 1

> [!WARNING]
> **Architecture preview / source-level experiment. No complete real-device verification has been performed.**
>
> **架构预览 / 源码级实验版本。当前尚未完成真机完整验证。**

## What this preview demonstrates

This preview explores a capability/provider/runtime-service direction for RELAXIN-X while preserving compatibility with the existing bootstrap ecosystem.

Key architectural work includes:

- capability-driven Runtime descriptors instead of product-name-specific branching
- Provider Registry + resolver policy
- transaction-level provider pinning
- provider health, protocol negotiation, reconnect generation tracking
- typed Runtime Service communication
- Sileo / Zebra / Prism package-manager selection
- a final package-manager confirmation boundary during the jailbreak flow
- Prism Store integration with `Prism.app` + `prismd`
- package transaction / journal / reconcile / recovery architecture
- environment inspection and targeted Prism repair states
- BaseBin retained as a compatibility path rather than a required architectural center for every new Runtime client

The architectural principle is:

> **Modern first, legacy compatible, but no longer legacy-centered.**

## Build verification

Verified on the maintainer's Mac:

- Xcode compilation completed
- PrismCore: 221 tests passed in the successful build log
- RELAXIN-X IPA packaging completed

Not yet verified on a physical supported iPhone:

- complete jailbreak execution
- Prism installation and `prismd` lifecycle
- deployed Runtime handshake/reconnect
- real repository refresh
- real package install / upgrade / downgrade / removal
- reboot/recovery behavior

This release must therefore remain marked as a **pre-release / architecture preview**.

## Preview IPA

```text
Suggested tag:   v0.5.0-arch-preview.1
Suggested asset: RELAXIN-X-v0.5.0-arch-preview.1.ipa
File size:       35,969,121 bytes
SHA-256:         93a72b833a89ca7d22df0972eb4d427c734a05898d1b68a93b312a03e4e4273c
Bundle ID:       com.aapl.relaxin
Display name:    RELAXIN-X
```

The SHA-256 identifies the exact Mac-built preview IPA. It is not evidence that the build has successfully completed a jailbreak or package transaction on real hardware.
