ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Tests/RepairPlanning
TEST := $(BUILD)/repair_planning_tests
SOURCES := \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareExecutionClass.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityRequirement.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineManifest.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/KernelProfileIntegrityMetadata.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityEvaluator.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeEnvironment.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeCapability.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfile.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolution.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeOperationRequirements.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackend.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/LegacyRelaxinRuntimeBackend.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendRegistry.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentSnapshot.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/RepairPlan.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/CompatibilityGate.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/JailbreakEnvironmentState.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/RecoveryOperation.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/RecoveryStage.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/PostConditionVerifier.swift

ifeq ($(shell command -v xcrun >/dev/null 2>&1; echo $$?),0)
SWIFTC := xcrun --sdk macosx swiftc
else
SWIFTC := swiftc
endif

.PHONY: all test clean
all: $(TEST)

$(TEST): main.swift $(SOURCES)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(SOURCES) main.swift -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
