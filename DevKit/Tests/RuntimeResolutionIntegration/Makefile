ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/Tests/RuntimeResolutionIntegration/runtime_resolution_state_tests
RUNTIME := \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityRequirement.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineManifest.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/KernelProfileIntegrityMetadata.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityEvaluator.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeEnvironment.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareExecutionClass.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeCapability.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfile.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolution.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeOperationRequirements.swift
RECOVERY := \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentSnapshot.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/CompatibilityGate.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/JailbreakEnvironmentState.swift
SOURCES := $(RUNTIME) $(RECOVERY) main.swift
.PHONY: test clean
test: $(OUT)
	$(OUT)
$(OUT): $(SOURCES)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES) -o $@
clean:
	rm -rf $(ROOT)/build/Tests/RuntimeResolutionIntegration
