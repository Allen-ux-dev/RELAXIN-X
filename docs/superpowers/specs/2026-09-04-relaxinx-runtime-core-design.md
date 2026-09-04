# RelaxinX Runtime Core Expansion Design

## Summary

This change advances RELAXIN-X without changing its existing UI shell. It introduces three internal architectural improvements:

1. Rename the main application product identity from `Relaxin` to `RelaxinX` while preserving the public brand `RELAXIN-X` / `RELAXIN - X`.
2. Introduce a jailbreak-root isolation layer so upper layers no longer depend on hard-coded jailbreak-root paths. The goal is ownership, permission hygiene, migration safety, and recovery correctness — not stealth, concealment, or bypassing jailbreak detection.
3. Extend Runtime Abstraction v2 with a lower-level hardware backend registry so A13/iPhone 11 can become the first dedicated hardware backend and future hardware families can be integrated through the same contract.

This work must preserve the existing Relaxin upstream attribution, Zebra/Sileo integration, Environment Recovery system, 0.5.0 upstream baseline data, and existing UI behavior.

## Goals

- Main Xcode application product becomes `RelaxinX.app` with executable/product name `RelaxinX`.
- Public IPA remains `RELAXIN-X.ipa`.
- Existing UI branding remains `RELAXIN - X`.
- Existing `RelaxinEngine.framework` and upstream framework naming remain unchanged unless an explicit compatibility reason requires otherwise.
- Introduce `JailbreakRootProvider` as the only application-layer source of the active jailbreak root.
- Reduce direct jailbreak-root path coupling in application/recovery code.
- Validate jailbreak-root ownership, symlink state, and permission expectations before mutation.
- Support migration/rollback between known root layouts without randomized paths or concealment behavior.
- Introduce a `LowLevelBackend` abstraction beneath the existing `RuntimeBackend` layer.
- Allow multiple hardware-specific lower-level implementations to coexist behind a single Runtime v2 admission path.
- Add an A13/iPhone 11 backend descriptor slot compatible with the current A13 hardware support descriptor.
- Preserve fail-closed behavior: recognized hardware without a verified backend is never treated as supported.

## Non-goals

- No UI redesign.
- No changes to the `RELAXIN - X` banner, Credits, package-manager UI, or Home flow.
- No hiding of jailbreak artifacts from third-party applications or detection systems.
- No randomized jailbreak-root names, path masquerading, directory camouflage, or jailbreak-detection bypass logic.
- No reverse-engineered reimplementation of unknown 0.5.0 engine behavior.
- No automatic support claim for A18/A19/future chips without a verified backend and matching baseline data.
- No renaming of upstream frameworks such as `RelaxinEngine.framework` merely for branding.

## Current Architecture Constraints

The main project currently uses:

- `PRODUCT_BUNDLE_IDENTIFIER = com.aapl.relaxin` from `Configuration/Base.xcconfig`.
- Xcode product reference `Relaxin.app` for the main app target.
- `RuntimeBackend` as a high-level runtime validation contract.
- `RuntimeBackendDescriptor` with backend ID, maturity, supported profiles, capabilities, hardware classes, environment schema floor, and backend generation.
- `HardwareSupportRegistry` with supported A12 through A17 hardware descriptors and generation-2 admission requirements.
- `EnvironmentRecovery` for checkpointing, repair planning, migration, and stale-state invalidation.
- A separate `StealthCompatibility` subsystem that is out of scope for jailbreak-root isolation and must not be expanded as part of this work.

## Product Identity Design

### Main product

The main application product name becomes:

- Product: `RelaxinX`
- Built application: `RelaxinX.app`
- Main executable: `RelaxinX`
- Distribution artifact: `RELAXIN-X.ipa`

The source directory may remain `Relaxin/` to avoid an unnecessary repository-wide rename. The primary target may retain its internal Xcode target identity if changing the target object name would add no functional value; the built product identity is the required change.

### Bundle identifier

This design does not require changing the bundle identifier as part of the product-name rename. Bundle identifier migration is a separate compatibility decision because it affects installation identity, preferences, keychain/application-container continuity, and update behavior.

The implementation should therefore:

- Rename product/executable/app output to `RelaxinX`.
- Keep the existing bundle identifier unless a later explicit migration decision changes it.
- Update packaging scripts/tests so they discover `RelaxinX.app` and still emit `RELAXIN-X.ipa`.

## Jailbreak Root Isolation

### Purpose

`JailbreakRootProvider` centralizes how RELAXIN-X resolves and reasons about the active jailbreak root. The provider exists to prevent unrelated application/recovery code from assuming a concrete path such as `/var/jb`.

It is not a stealth system.

### Core types

Create a focused module under `Relaxin/Backend/JailbreakRoot/` with these responsibilities:

```swift
enum JailbreakRootKind: String, Codable, Sendable {
    case rootHideCompatible
    case legacyKnown
    case unavailable
}

struct JailbreakRootDescriptor: Equatable, Sendable {
    let kind: JailbreakRootKind
    let rootURL: URL
    let canonicalURL: URL
    let ownership: JailbreakRootOwnership
    let permissions: JailbreakRootPermissions
}

protocol JailbreakRootProvider {
    func resolve() -> JailbreakRootResolution
}
```

`JailbreakRootResolution` must distinguish at minimum:

- resolved and healthy
- resolved but repairable
- conflicting candidates
- unavailable
- unsafe/invalid

### Validation

Resolution is read-only. It may inspect:

- known candidate roots
- canonicalized paths
- symlink destination consistency
- ownership metadata
- mode/permission metadata
- presence of RELAXIN-X-managed generation markers where applicable

Resolution must not mutate the filesystem.

Mutation belongs to Environment Recovery operations.

### Permission policy

The root isolation layer should minimize unnecessarily broad permissions while preserving the requirements of the existing RootHide/bootstrap architecture. The provider must not promise security properties that the underlying jailbreak requires it to violate.

Tests must verify that the application does not deliberately widen permissions beyond the expected baseline during migration/repair.

### Migration

Migration uses Environment Recovery and must be checkpointed.

A migration operation must:

1. Resolve current state.
2. Produce a deterministic migration plan.
3. Confirm source and destination identities.
4. Stage changes.
5. Verify postconditions.
6. Commit generation metadata only after verification.
7. Roll back to the previous known-good state on failure when rollback is feasible.

The provider must not generate randomized directory names and must not attempt to hide the jailbreak root from filesystem inspection.

## Low-Level Backend Architecture

### Layering

The runtime stack becomes:

```text
Upstream Baseline Pack
        ↓
HardwareSupportRegistry
        ↓
RuntimeProfileResolver
        ↓
RuntimeBackend
        ↓
LowLevelBackendRegistry
        ↓
LowLevelBackend
        ↓
Existing engine execution adapter
```

`RuntimeBackend` remains the high-level admission/runtime contract. `LowLevelBackend` represents a hardware-family-specific lower-level implementation selected only after Runtime v2 has already admitted the environment/profile.

### Low-level descriptor

```swift
struct LowLevelBackendDescriptor: Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let hardwareClassIDs: Set<String>
    let requiredRuntimeCapabilities: Set<RuntimeCapability>
    let minimumRuntimeBackendGeneration: Int
    let minimumBaselineID: String?
    let stability: LowLevelBackendStability
    let recoveryStrategy: LowLevelBackendRecoveryStrategy
}
```

`LowLevelBackendStability` should include at least:

- `verified`
- `experimental`
- `recognizedOnly`

`recognizedOnly` can never execute.

### Backend protocol

The first implementation phase should keep the protocol narrow:

```swift
protocol LowLevelBackend {
    var descriptor: LowLevelBackendDescriptor { get }

    func validate(
        environment: RuntimeEnvironment,
        profile: RuntimeProfile,
        hardware: HardwareSupportDescriptor
    ) -> LowLevelBackendValidation
}
```

Execution-specific hooks are added only where the existing engine adapter has a real integration point. Do not create speculative exploit APIs merely to make the interface look complete.

### Registry

`LowLevelBackendRegistry` owns deterministic selection. Selection must consider:

- hardware descriptor
- admitted RuntimeProfile
- backend generation
- required capabilities
- stability state
- baseline compatibility

Selection must be fail-closed and deterministic.

If two executable backends match equally, resolution must return a conflict rather than silently selecting by array order.

## A13 / iPhone 11 Backend Slot

The existing A13 descriptor uses CPU family `0x462504D2` and `HardwareExecutionClass.pplGFXA13`.

The new architecture adds a dedicated A13 lower-level backend descriptor slot associated with that hardware class. The first safe implementation milestone is structural:

- registry entry
- compatibility validation
- baseline requirement
- explicit stability state
- diagnostics
- recovery strategy declaration

It must not claim that an unimplemented or unverified low-level execution path is operational.

If a future A13 implementation is derived from a separately licensed/open source branch, its license and provenance must be audited and preserved before code integration.

## Future Hardware

Future hardware may be registered independently of executable support.

A future chip can be:

- recognized by `HardwareSupportRegistry`
- mapped to a low-level backend family
- marked `recognizedOnly`

but remains non-executable until all of these are true:

- matching baseline data exists
- Runtime v2 admits the environment
- a verified/explicitly experimental executable backend exists
- required capabilities are present
- integrity requirements pass

This preserves the Fix14 rule that “recognized” is not the same as “supported.”

## Environment Recovery Integration

Environment checkpoints should record enough identity to invalidate stale assumptions after this architecture change.

Add generation/identity for:

- jailbreak-root layout generation
- selected low-level backend ID
- selected low-level backend generation/revision if applicable

Stale-state invalidation should be targeted:

- root-layout change invalidates only root-layout-dependent recovery state
- low-level backend change invalidates hardware/backend execution state
- package-manager state is not invalidated merely because the low-level backend changed
- UI preferences are unaffected

## Diagnostics

Diagnostics should expose internal state without exposing sensitive credentials or pretending that unsupported hardware works.

Useful fields include:

- product identity: `RelaxinX`
- active RuntimeProfile ID
- high-level RuntimeBackend ID/generation
- HardwareSupportDescriptor ID/status
- selected LowLevelBackend ID/stability
- jailbreak-root resolution kind
- jailbreak-root health summary
- generation mismatch reasons

Diagnostics should avoid publishing unnecessary absolute filesystem details in user-shared reports when a symbolic root identifier is sufficient.

## Build and Packaging

`BuildIPA.command`, Makefile packaging helpers, and contract tests must be updated so the main output is `RelaxinX.app` while the distributed IPA remains `RELAXIN-X.ipa`.

The rename must not accidentally rename:

- `RelaxinEngine.framework`
- `RelaxinPostJailbreak.framework`
- upstream source attribution
- GitHub repository name
- UI brand text

## Testing Strategy

### Product identity

- Contract test that Xcode built-product reference is `RelaxinX.app`.
- Contract test that packaging looks for `RelaxinX.app`.
- Contract test that output artifact remains `RELAXIN-X.ipa`.
- Regression check that UI branding files remain unchanged.

### Jailbreak root

- Pure Swift tests for root-resolution state machine using synthetic filesystem metadata fixtures.
- Conflicting candidate roots fail closed.
- Invalid symlink chains are rejected.
- Permission drift is reported as repairable/invalid according to policy.
- Resolution performs no mutation.
- Migration planner is deterministic and checkpoint-friendly.
- No test or production API contains randomized-path or detection-evasion behavior.

### Low-level backend

- A13 hardware resolves to the dedicated A13 backend descriptor when all admission requirements match.
- Unknown/future hardware can be recognized without becoming executable.
- `recognizedOnly` backend never executes.
- Backend conflict fails closed.
- Baseline mismatch rejects selection.
- Runtime generation floor is enforced.
- Existing A12-A17 Runtime v2 admission tests remain green.

### Regression

- Fix13 acceptance tests remain green.
- Fix14 acceptance tests remain green.
- Zebra/Sileo selection tests remain green.
- Environment Recovery generation/migration tests remain green.
- UI hashes/contract remain unchanged unless a product-name-only plist/build setting necessarily changes generated metadata.

## Safety and Scope Boundary

This design deliberately separates root-path isolation from stealth/evasion.

Allowed implementation work:

- centralizing root-path resolution
- permission hygiene
- ownership checks
- deterministic migration
- rollback/recovery
- reducing hard-coded root paths
- diagnostics that minimize unnecessary path disclosure

Out of scope:

- hiding `/var/jb` or equivalent from third-party process inspection
- intercepting filesystem/process APIs to conceal jailbreak artifacts
- bypassing jailbreak-detection logic
- randomized or deceptive root paths whose purpose is evasion

## Success Criteria

The change is complete when:

1. The main built app is `RelaxinX.app` and packages as `RELAXIN-X.ipa`.
2. Existing UI behavior and branding are preserved.
3. Application/recovery code can obtain jailbreak-root information through `JailbreakRootProvider` rather than new direct path constants.
4. Root resolution is read-only and migration is recovery/checkpoint driven.
5. Runtime v2 selects a `LowLevelBackend` through a deterministic registry.
6. A13/iPhone 11 has a dedicated backend slot without falsely claiming unverified execution support.
7. Future hardware can be recognized independently from support.
8. Fix13/Fix14 acceptance and package-manager regressions remain green.
9. No new stealth/evasion behavior is introduced.
