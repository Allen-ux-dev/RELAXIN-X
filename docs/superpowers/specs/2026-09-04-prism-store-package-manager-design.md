# RELAXIN-X Prism Selectable Store Integration Design

Date: 2026-09-04
Branch: `feature/prism-store-package-manager`
Base: `feature/prism-runtime-service-host`
Status: Design approved in chat; written spec awaiting final user review before implementation.

## 1. Goal

Integrate Prism 0.4.1 Build 52 Complete Store into RELAXIN-X as a third selectable package manager/store alongside Sileo and Zebra.

The user-facing model becomes:

```text
Advanced Options / 高级选项
└── Package Managers / 软件包管理器
    ├── Sileo: ON/OFF
    ├── Zebra: ON/OFF
    └── Prism: ON/OFF
```

Selections may be combined freely, but at least one package manager/store must remain selected. The existing default remains Sileo.

Selecting Prism means RELAXIN-X prepares and deploys the complete Prism Store runtime set, not merely `Prism.app`.

## 2. Non-goals

This change does not:

- replace Sileo or Zebra;
- rewrite RelaxinEngine package-manager installation paths;
- move Prism Transaction / Journal / Reconcile / Recovery ownership into RELAXIN-X;
- merge Prism Store UI or PrismCore source into RELAXIN-X application source;
- expose arbitrary shell, arbitrary privileged paths, raw kernel operations, or raw process-control APIs;
- implement jailbreak-detection evasion or hidden-path behavior;
- automatically remove an already-installed Prism Store merely because the checkbox is later disabled.

## 3. Architecture decision

Use a versioned **Prism Store Bundle** consumed by RELAXIN-X.

```text
PackageManagerSelection
  ├── Sileo
  │    └── existing RelaxinEngine manifest path
  ├── Zebra
  │    └── existing verified RootHide DEB path
  └── Prism
       └── PrismStoreInstaller
            ├── verify Prism Store Bundle
            ├── deploy Prism.app
            ├── deploy prismd
            ├── register/refresh Prism.app
            ├── establish daemon lifecycle
            └── use existing RELAXIN-X Runtime Bridge
                 /var/run/relaxinx-runtime.sock
```

Prism remains a separate product and codebase. RELAXIN-X consumes a build artifact and typed metadata rather than copying Prism implementation into its own Core.

## 4. Package-manager selection model

Extend:

```swift
enum PackageManager: String, CaseIterable, Hashable {
    case sileo
    case zebra
    case prism
}
```

Rules:

1. Existing persisted values such as `sileo`, `zebra`, or `sileo,zebra` continue to decode unchanged.
2. `prism` is a new stable raw value.
3. Empty/invalid stored selections still fall back to Sileo.
4. Toggling off the final selected manager remains rejected.
5. Default remains Sileo only.
6. All combinations are supported:
   - Sileo
   - Zebra
   - Prism
   - Sileo + Zebra
   - Sileo + Prism
   - Zebra + Prism
   - Sileo + Zebra + Prism

## 5. UI behavior

The existing Package Managers screen continues to derive rows from `PackageManager.allCases`.

Labels:

- Sileo — Recommended / 推荐
- Zebra — Experimental / 实验性
- Prism — Integrated Store / 集成商店

The selected package-manager summary must include Prism, e.g.:

```text
packages  Prism
packages  Sileo + Prism
packages  Sileo + Zebra + Prism
```

No additional root tab or separate RELAXIN-X page is required for Prism.

## 6. Separation from RelaxinEngine manifest

Sileo and Zebra keep their existing engine manifest keys:

```text
installSileoEnabledKey
installZebraEnabledKey
```

Prism is intentionally **not** added as another low-level RelaxinEngine package-manager manifest flag.

Reason: Prism is a compound application/service bundle (`Prism.app + prismd + Runtime Bridge`) and belongs to RELAXIN-X app-owned post-jailbreak orchestration rather than the existing engine package-manager bootstrap contract.

`JailbreakConfiguration.packageManagers` remains the source of truth. The post-jailbreak coordinator reads whether `.prism` is selected and invokes `PrismStoreInstaller` only after the jailbreak/bootstrap environment reaches the safe package/application deployment stage.

## 7. Prism Store Bundle format

Introduce a deterministic store artifact, conceptually:

```text
PrismStore.bundle/
├── Manifest.json
├── Prism.app/
└── prismd
```

The bundle may be represented as a directory during local builds and as a deterministic archive for distribution/cache transport.

### 7.1 Manifest

Recommended `PrismStoreBundleManifest` fields:

```text
schemaVersion
storeIdentifier
storeVersion
storeBuild
prismBundleIdentifier
prismExecutableName
prismdIdentifier
runtimeProtocolVersions
runtimeIdentity
runtimeServiceID
artifacts:
  Prism.app  -> SHA-256 + size
  prismd     -> SHA-256 + size
```

Stable identities:

```text
runtimeIdentity = dev.relaxin.runtime
runtimeServiceID = dev.relaxin.service.runtime
runtimeEndpoint = /var/run/relaxinx-runtime.sock
```

The manifest must not contain device-specific secrets or private session material.

### 7.2 Integrity

Before deployment, RELAXIN-X verifies:

- supported manifest schema;
- expected store identifier;
- required files exist;
- declared sizes match;
- SHA-256 digests match;
- `Prism.app` has a readable Info.plist and expected bundle identity;
- `prismd` artifact is present and non-empty;
- no unexpected parent-path traversal or symlink escape exists in the staged bundle.

Integrity failure means Prism is not deployed and the error is reported as a Prism Store failure; it must never silently fall back to an unverified artifact.

## 8. Prism build output

The Prism Complete Store build tooling should gain a dedicated Store Bundle output in addition to its current IPA.

Expected build products:

```text
Prism-0.4.1-Build52-Complete-Store.ipa
PrismStore.bundle/   (or deterministic PrismStore archive)
```

The Store Bundle builder:

1. builds Prism.app;
2. builds the `prismd` SwiftPM executable target;
3. stages both into the Store Bundle;
4. writes `Manifest.json`;
5. calculates SHA-256/size metadata;
6. validates the final bundle before publishing it.

This keeps Prism source ownership in the Prism project while exposing a stable deployment artifact to RELAXIN-X.

## 9. RELAXIN-X build integration

RELAXIN-X must support one-click `BuildIPA.command` without requiring manual copying after every build.

Use a staged resource/cache model:

```text
build/PrismStoreSources/
build/PrismStoreResources/
```

The RELAXIN-X build helper resolves a version-pinned Prism Store Bundle from one of these allowed sources, in priority order:

1. an explicitly supplied local Prism Store Bundle path for development;
2. a valid existing local cache matching the pinned manifest identity;
3. an approved pinned distribution source if configured by the project.

The final RELAXIN-X app contains the validated Prism Store deployment resource required for offline post-jailbreak installation. Build-time acquisition and runtime installation remain separate responsibilities.

A partially downloaded or invalid bundle must never replace a known-good cache.

## 10. Runtime installation timing

Prism deployment occurs only after the core jailbreak/bootstrap environment is ready enough to perform application/service deployment safely.

High-level flow:

```text
Start Jailbreak
→ RelaxinEngine completes core bootstrap
→ existing post-jailbreak finalization
→ inspect selected PackageManagerSelection
→ if Prism selected:
     PrismStoreInstaller.inspect()
     → already current: no-op/repair registration if required
     → missing/stale: verify staged bundle
                    → deploy Prism.app
                    → deploy prismd
                    → register/refresh Prism.app
                    → start/confirm service state
                    → verify installed state
→ continue final environment verification
```

The installer must be idempotent.

Repeated jailbreak/finalization with the same Prism version must not duplicate files, registrations, daemon entries, or runtime endpoints.

## 11. Installed-state model

Introduce a normalized Prism Store state, for example:

```text
notRequested
notInstalled
installing
installed
needsRepair
versionMismatch
daemonUnavailable
registrationMissing
bundleInvalid
failed
```

Inspection should distinguish at least:

- Prism.app presence/version;
- application registration state;
- prismd presence/version/health;
- Runtime Bridge compatibility identity;
- selected/not-selected intent.

Environment diagnostics should describe these states without exposing sensitive backend paths or credentials.

## 12. Failure semantics

Prism is optional relative to RELAXIN-X core jailbreak completion.

If Prism is selected and deployment fails:

- do not report Prism as installed;
- do not claim complete Prism capability readiness;
- preserve Sileo/Zebra if they were also selected;
- preserve the successfully completed core jailbreak/bootstrap state;
- mark the environment degraded / Prism repair required;
- surface a targeted repair action rather than automatically undoing unrelated successful work.

If Prism is the only selected package manager and Prism deployment fails, the environment must explicitly report that no selected package manager is currently usable.

## 13. Repair semantics

Repair is targeted and idempotent.

Possible repair operations:

```text
re-verify bundled artifact
redeploy missing Prism.app component
redeploy missing prismd component
refresh app registration
restart/reconnect Prism service
re-run installed-state verification
```

Repair does not rewrite Prism Transaction / Journal / Recovery databases and does not reset Sileo/Zebra.

## 14. Disable/removal semantics

Disabling `Prism` in `PackageManagerSelection` changes **future desired installation behavior**, but does not automatically delete an already-installed Prism Store.

Reason: silently deleting an application/service because a checkbox was toggled is destructive and makes rollback/recovery harder to reason about.

For this version:

- Prism OFF + not installed → do nothing.
- Prism OFF + already installed → leave it installed and unmanaged by the current installation request.
- Prism removal is reserved for an explicit Maintenance action in a later/adjacent task.

If explicit Prism removal is implemented later, it must be separately confirmed by the user and must remove only RELAXIN-X-managed Prism components.

## 15. Update semantics

When the bundled Prism version/build changes:

```text
inspect installed state
→ compare installed identity with bundled identity
→ if current: no-op
→ if older/different and Prism selected:
     verify new bundle
     → replace application/service components using staged swap
     → refresh registration/service
     → verify actual state
```

A failed update must retain or recover to a known usable state when possible; it must not delete the old installation before the replacement artifact passes integrity checks.

## 16. Runtime Bridge integration

The selectable-store feature reuses the existing branch implementation:

```text
Prism/prismd
  → RuntimeServiceBridgeCoordinator
  → /var/run/relaxinx-runtime.sock
  → RELAXIN-X Runtime Service Host
```

`/var/run/prismd.sock` remains Prism-owned. RELAXIN-X must never bind, replace, unlink, or hijack it.

Runtime execution capabilities remain fail-closed until their real adapters are wired and verified. Installing Prism Store does not automatically mean every Runtime capability is available.

## 17. Application/service deployment boundary

`PrismStoreInstaller` is an app-owned orchestration layer. It may call existing narrowly-scoped RELAXIN-X post-jailbreak deployment/registration helpers, but it must not introduce a Prism-facing arbitrary file-write or arbitrary shell API.

The implementation should prefer typed operations such as:

```text
deploy validated application artifact
register known bundle identifier
install known service artifact
start/inspect known service identifier
```

Only the fixed, validated Prism Store bundle is in scope.

## 18. Localization and credits

Add localized user-facing strings for at least English and Simplified Chinese:

```text
Prism
Integrated Store / 集成商店
Prism Store
Prism Store Ready / Prism 商店已就绪
Prism Store Needs Repair / Prism 商店需要修复
Prism Store Installation Failed / Prism 商店安装失败
```

Preserve upstream and third-party attribution. Prism licensing/provenance must be recorded in third-party notices/provenance documentation before public distribution.

## 19. RelaxinLite boundary

Prism Store deployment belongs to the full RELAXIN-X app/runtime only.

Any new `PrismStoreInstaller`, bundle verification, or full-app orchestration sources added under synchronized Xcode groups must be explicitly excluded from the RelaxinLite target when required.

## 20. Tests

Implementation uses TDD. Minimum coverage:

### 20.1 Selection

```text
DefaultSelectionIsSileo
PrismSelectionRoundTrips
AllThreeManagersCanCoexist
CannotDisableFinalManager
LegacySelectionValuesRemainCompatible
```

### 20.2 Configuration/engine boundary

```text
SileoManifestBehaviorUnchanged
ZebraManifestBehaviorUnchanged
PrismSelectionDoesNotInventRelaxinEngineManifestKey
```

### 20.3 Bundle

```text
ValidPrismStoreBundleAccepted
DigestMismatchRejected
MissingPrismAppRejected
MissingPrismdRejected
UnexpectedTraversalRejected
VersionIdentityRoundTrips
```

### 20.4 Installation

```text
UnselectedPrismIsNoOp
SelectedMissingPrismInstalls
AlreadyCurrentPrismIsIdempotent
RegistrationMissingTriggersRepair
DaemonMissingTriggersRepair
FailedPrismDoesNotRemoveOtherManagers
PrismOnlyFailureReportsNoUsableSelectedManager
```

### 20.5 Update/recovery

```text
NewerBundleTriggersReplace
InvalidNewBundlePreservesExistingInstall
StateVerificationRequiredBeforeReady
FailedOperationReportsRepairRequired
```

### 20.6 UI/localization

```text
PackageManagerScreenShowsPrism
PrismBadgeIsIntegratedStore
PackageSummaryIncludesPrism
EnglishAndChineseStringsPresent
```

### 20.7 Build/target boundaries

```text
BuildIPAStagesPinnedPrismStoreBundle
InvalidBundleCannotEnterFinalResources
RelaxinLiteExcludesPrismStoreInstaller
ExistingFix13Fix14AcceptanceStillPasses
PrismRuntimeBridgeTestsStillPass
```

## 21. Verification gates

Before merge:

1. host unit/contract tests pass;
2. existing Sileo/Zebra regression tests pass;
3. Fix13/Fix14 acceptance remains green;
4. Runtime Bridge tests remain green;
5. Prism Store source build emits a validated Store Bundle;
6. RELAXIN-X Xcode build succeeds on the user's Mac;
7. real-device verification confirms:
   - Prism selection is honored;
   - Prism.app is installed and launchable;
   - prismd lifecycle is healthy;
   - Prism can discover the RELAXIN-X Runtime Service;
   - Sileo/Zebra coexistence is unaffected.

No Xcode or real-device success claim is allowed before steps 6–7 are actually observed.

## 22. Delivery sequence

Implementation order:

```text
1 PackageManagerSelection + UI/localization
2 Prism Store Bundle manifest/verifier
3 Prism project Store Bundle builder (Prism.app + prismd)
4 RELAXIN-X BuildIPA staging/cache
5 PrismStoreInstaller state model
6 post-jailbreak integration
7 registration/service lifecycle adapter
8 environment inspection/repair reporting
9 regression + acceptance gates
10 Mac Xcode build
11 real-device verification
```

## 23. Definition of Done

The feature is complete only when a user can select Prism alongside Sileo/Zebra before jailbreak, run the normal RELAXIN-X flow, and receive a verified, registered, usable Prism Store installation with its required daemon/runtime bridge components, without manually sideloading Prism afterward.

The selection must remain optional, combinable, backward-compatible, idempotent, and failure-isolated.

**Prism is a selectable integrated store, not merely a Runtime Bridge client.**
