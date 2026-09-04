# Relaxin build automation

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# =============================================================================
# Configuration
# =============================================================================

ROOT_DIR        := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PROJECT         := $(ROOT_DIR)/Relaxin.xcodeproj
IOS_SCHEME      := Relaxin
LITE_SCHEME     := RelaxinLite
CONFIGURATION   := Debug
LITE_CONFIGURATION := Release
DERIVED_DATA    ?= /private/tmp/relaxin-deriveddata
VERSION_CONFIG  := $(ROOT_DIR)/Configuration/Version.xcconfig
APP_VERSION     := $(strip $(shell awk -F= '/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ { gsub(/^[[:space:]]+|[[:space:]]+$$/, "", $$2); print $$2; exit }' "$(VERSION_CONFIG)"))

IOS_DESTINATION := generic/platform=iOS
DEV_ENV         := $(ROOT_DIR)/.env.sh
APP_BUNDLE      := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/$(IOS_SCHEME).app
LITE_APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(LITE_CONFIGURATION)-iphoneos/$(LITE_SCHEME).app
IPA_OUTPUT      ?= $(ROOT_DIR)/build/Artifacts/$(IOS_SCHEME)-$(APP_VERSION).ipa
IPA_PACKAGER    := $(ROOT_DIR)/DevKit/Helpers/package-ipa.sh
TIPA_OUTPUT     ?= $(ROOT_DIR)/build/Artifacts/$(IOS_SCHEME)-$(APP_VERSION).tipa
TIPA_PACKAGER   := $(ROOT_DIR)/DevKit/Helpers/package-tipa.sh
TIPA_ENTITLEMENTS := $(ROOT_DIR)/DevKit/Packaging/Relaxin.tipa.entitlements
LITE_DEB_OUTPUT ?= $(ROOT_DIR)/build/Artifacts/relaxin-lite.deb
LITE_DEB_PACKAGER := $(ROOT_DIR)/DevKit/Packaging/RelaxinLite/package-deb.sh

ifeq ($(APP_VERSION),)
$(error MARKETING_VERSION is missing from $(VERSION_CONFIG))
endif

BOOTSTRAP_SOURCE_DIRECTORY := $(ROOT_DIR)/build/BootstrapSources
BOOTSTRAP_RESOURCE_DIRECTORY := $(ROOT_DIR)/build/BootstrapResources
BOOTSTRAP_SOURCE := $(BOOTSTRAP_SOURCE_DIRECTORY)/bootstrap_1900.tar.zst
BOOTSTRAP_RESOURCE := $(BOOTSTRAP_RESOURCE_DIRECTORY)/bootstrap_1900.tar.zst
BOOTSTRAP_DOWNLOAD_SCRIPT := $(ROOT_DIR)/DevKit/Helpers/download-bootstrap.sh
BOOTSTRAP_PREPARATION_SCRIPT := $(ROOT_DIR)/DevKit/Helpers/prepare-bootstrap.sh
BOOTSTRAP_UICACHE_POLICY := $(ROOT_DIR)/DevKit/Bootstrap/UICache.entitlements
ADHOC_SIGNATURE_VERIFIER_SOURCE := $(ROOT_DIR)/DevKit/Bootstrap/VerifyAdHocSignature.c
ADHOC_SIGNATURE_VERIFIER := $(ROOT_DIR)/build/Tools/VerifyAdHocSignature
BASEBIN_RESOURCE_DIRECTORY := $(ROOT_DIR)/build/BaseBinResources

# run-xcodebuild.sh keeps a complete persistent raw transcript while streaming
# a concise line-by-line terminal view. It also fails when the saved log contains
# compiler errors or "** ... FAILED **" markers even if xcodebuild returned 0.
XCODEBUILD_WRAPPER := $(ROOT_DIR)/DevKit/Helpers/run-xcodebuild.sh
TOOL_CHECKER       := $(ROOT_DIR)/DevKit/Helpers/check-tools.sh

XCODEBUILD := $(XCODEBUILD_WRAPPER) \
    -project "$(PROJECT)" \
    -derivedDataPath "$(DERIVED_DATA)" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

.PHONY: all help print-version \
        build build-ios lite-deb tipa ipa bootstrap-resources scan-license check test-host \
        kernel-offsets \
        format format-lint \
        clean \
        _check-bootstrap-tools _check-xcode-tools _check-tipa-tools _check-lite-tools \
        _check-format-tools

.SECONDARY: $(BOOTSTRAP_SOURCE)

# =============================================================================
# Meta
# =============================================================================

all: build

print-version:
	@echo "$(APP_VERSION)"

help:
	@echo "Build:"
	@echo "  build                 Build the iOS app (scheme: $(IOS_SCHEME))"
	@echo "  build-ios             Alias for build"
	@echo "  lite-deb              Build the Relaxin Lite RootHide package"
	@echo "  ipa                   Build and package an unsigned IPA"
	@echo "  tipa                  Build and package a no-sandbox TIPA"
	@echo "  bootstrap-resources   Download, ad-hoc sign, and stage the RootHide bootstrap"
	@echo "  kernel-offsets        Regenerate the bundled kernelcache offset table"
	@echo "  scan-license          Refresh Licenses.txt from Vendor"
	@echo "  check                 Validate kernel, BaseBin, and zstd contracts"
	@echo "  test-host             Run host-side runtime and kernel contract tests"
	@echo ""
	@echo "Formatting:"
	@echo "  format                Run Swift and C-family formatters (write)"
	@echo "  format-lint           Run Swift and C-family formatters in check mode"
	@echo ""
	@echo "Housekeeping:"
	@echo "  clean                 Remove derived data and generated BaseBin resources"

# =============================================================================
# Build
# =============================================================================

build: build-ios

scan-license:
	"$(ROOT_DIR)/DevKit/Helpers/scan-licenses.sh"

# Rebuilds Relaxin/Resources/KernelOffsets.plist from a local kernelcache
# corpus. Not part of `build`: the corpus is far larger than the repository and
# the table only changes when the supported build list does.
kernel-offsets:
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Helpers/KernelOffsets"
	"$(ROOT_DIR)/DevKit/Helpers/KernelOffsets/build-offset-table.py" \
	    $(KERNEL_OFFSET_FLAGS)
	"$(ROOT_DIR)/DevKit/Helpers/KernelOffsets/audit-offset-table.py"

check:
	"$(ROOT_DIR)/DevKit/Helpers/check-zstd-integration.sh"

test-host:
	python3 "$(ROOT_DIR)/DevKit/Tests/RelaxinXBranding/test_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RelaxinXBranding" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/Fix137UI/test_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/Fix137UI" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/Fix139UI/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/Fix1310UI/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPAStableWorkspace/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPAPrebuildBoundary/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/XcodePrebuiltResourceBoundary/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/XcodebuildConciseLogging/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPACommand/check.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPAHostTools/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPAPathSafety/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPABaseBinCacheIdentity/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPAPersistentCache/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/BuildIPABootstrapCache/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/LicenseScanSourceArchive/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/XcodebuildStreaming/test_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RuntimeAbstraction" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/PackageManagerSelection" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RuntimeBackendPolicy" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RuntimeExtensibility" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/RuntimeExtensibility/test_source_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/RuntimeManifestContract/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/RuntimeResolutionIntegration/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/RuntimeResolutionIntegration/test_ui_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RuntimeBackendExecution" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/RuntimeBackendExecution/test_integration_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/RuntimeBackendDispatch/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/JBRootIncludeContract/test_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/JailbreakTargetConfirmationError/test_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/JailbreakTargetConfirmationError" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/Fix13Acceptance/test_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RuntimeBaseline" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/UpstreamBaseline" test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/Fix14Integration" test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/Fix14Acceptance" test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RootHideSignaturePolicy" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RootHideExecutablePath" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/TrustCacheNoKcallModel" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/TrustCacheNoKcallController" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/TrustCacheNoKcallOwner" clean test
	"$(ROOT_DIR)/DevKit/Tests/TrustCacheNoKcallWord32/run.sh"
	"$(ROOT_DIR)/DevKit/Tests/TrustCacheNoKcallKernel/run.sh"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/CopyioWindow" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/PhysRWPTEWindow" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RocketRuntime" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/KernelAccessFailure" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/KernelOffsetTable" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RuntimeEnvironment" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/BootstrapFinalizer" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/PostJailbreakController" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/InterfaceMode" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/EnvironmentState" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/EnvironmentInspector" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/HomeEnvironmentRouting" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/EnvironmentRecoveryCoordinator" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/EnvironmentCheckpoint" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/EnvironmentGeneration" clean test
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/EnvironmentDiagnostics" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/EnvironmentDiagnostics/test_export_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/XcodeFix12TargetMembership/test_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/RepairPlanning" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/RepairPlanning/test_targeted_repair_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/TrustCacheTransactionBoundary" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/TrustCacheTransactionBoundary/test_integration_contract.py"
	$(MAKE) -C "$(ROOT_DIR)/DevKit/Tests/StealthCompatibility" clean test
	python3 "$(ROOT_DIR)/DevKit/Tests/StealthCompatibility/test_non_evasion_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/StealthCompatibility/test_integration_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/StealthCompatibility/test_localization_contract.py"
	python3 "$(ROOT_DIR)/DevKit/Tests/Fix12Acceptance/test_contract.py"

_check-bootstrap-tools:
	@$(TOOL_CHECKER) xcode ldid zstd gtar

_check-xcode-tools:
	@$(TOOL_CHECKER) xcode rg

_check-tipa-tools:
	@$(TOOL_CHECKER) ldid

_check-lite-tools:
	@$(TOOL_CHECKER) xcode dpkg-deb ldid

_check-format-tools:
	@$(TOOL_CHECKER) swiftformat clang-format

$(ADHOC_SIGNATURE_VERIFIER): \
        $(ADHOC_SIGNATURE_VERIFIER_SOURCE) \
        $(ROOT_DIR)/Makefile \
        $(DEV_ENV)
	@mkdir -p "$(dir $@)"
	source "$(DEV_ENV)" && xcrun --sdk macosx clang \
	    -target "$$(uname -m)-apple-macos$$(sw_vers -productVersion)" \
	    -isysroot "$$(xcrun --sdk macosx --show-sdk-path)" \
	    -Wall -Wextra -Werror -O2 "$<" -o "$@"
	/usr/bin/codesign --force --sign - --timestamp=none "$@"
	/usr/bin/codesign --verify --strict "$@"

$(BOOTSTRAP_SOURCE): $(BOOTSTRAP_DOWNLOAD_SCRIPT)
	@"$(BOOTSTRAP_DOWNLOAD_SCRIPT)" "$@"

$(BOOTSTRAP_RESOURCE): \
        $(BOOTSTRAP_SOURCE) \
        $(ROOT_DIR)/Makefile \
        $(BOOTSTRAP_PREPARATION_SCRIPT) \
        $(BOOTSTRAP_UICACHE_POLICY) \
        $(ADHOC_SIGNATURE_VERIFIER)
	@"$(BOOTSTRAP_PREPARATION_SCRIPT)" \
	    "$<" \
	    "$@" \
	    "$(ADHOC_SIGNATURE_VERIFIER)" \
	    "$(BOOTSTRAP_UICACHE_POLICY)"

# A prepared archive is published atomically only after complete verification,
# so the archive itself is the cache marker; current outputs require no unpack.
bootstrap-resources: _check-bootstrap-tools
	@if $(MAKE) -C "$(ROOT_DIR)" --no-print-directory --question "$(BOOTSTRAP_RESOURCE)" >/dev/null 2>&1; then \
	    echo "note: [Bootstrap] resources are up to date"; \
	else \
	    $(MAKE) -C "$(ROOT_DIR)" --no-print-directory "$(BOOTSTRAP_RESOURCE)"; \
	fi

build-ios: _check-xcode-tools
	source "$(DEV_ENV)" && \
	    relaxin_prepare_build_environment "$(DERIVED_DATA)" && \
	    XCBUILD_LABEL=build-ios $(XCODEBUILD) \
	    -configuration $(CONFIGURATION) \
	    -scheme $(IOS_SCHEME) \
	    -destination "$(IOS_DESTINATION)" \
	    build

lite-deb: _check-lite-tools
	@mkdir -p "$(dir $(LITE_DEB_OUTPUT))"
	source "$(DEV_ENV)" && \
	    relaxin_prepare_build_environment "$(DERIVED_DATA)" && \
	    XCBUILD_LABEL=relaxin-lite $(XCODEBUILD) \
	    -configuration $(LITE_CONFIGURATION) \
	    -scheme $(LITE_SCHEME) \
	    -destination "$(IOS_DESTINATION)" \
	    build
	"$(LITE_DEB_PACKAGER)" "$(LITE_APP_BUNDLE)" "$(LITE_DEB_OUTPUT)"

tipa: _check-tipa-tools build-ios
	"$(TIPA_PACKAGER)" \
	    "$(APP_BUNDLE)" \
	    "$(TIPA_ENTITLEMENTS)" \
	    "$(TIPA_OUTPUT)"

ipa: build-ios
	"$(IPA_PACKAGER)" "$(APP_BUNDLE)" "$(IPA_OUTPUT)"

# =============================================================================
# Formatting
# =============================================================================

format: _check-format-tools
	cd "$(ROOT_DIR)" && source "$(DEV_ENV)" && swiftformat .
	"$(ROOT_DIR)/DevKit/Helpers/format-c-family.sh" write

format-lint: _check-format-tools
	cd "$(ROOT_DIR)" && source "$(DEV_ENV)" && swiftformat . --lint
	"$(ROOT_DIR)/DevKit/Helpers/format-c-family.sh" lint

# =============================================================================
# Housekeeping
# =============================================================================

clean:
	rm -rf "$(DERIVED_DATA)"
	rm -rf "$(ROOT_DIR)/build/BaseBinWork" "$(ROOT_DIR)/build/BaseBinCaches" "$(BASEBIN_RESOURCE_DIRECTORY)"
