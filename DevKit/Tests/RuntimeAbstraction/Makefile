ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/Tests/RuntimeAbstraction/runtime_abstraction_tests
OUT_052 := $(ROOT)/build/Tests/RuntimeAbstraction/relaxin_052_compatibility_tests
OUT_052_COORDINATOR := $(ROOT)/build/Tests/RuntimeAbstraction/relaxin_052_coordinator_tests
RUNTIME_SOURCES := \
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
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeCompatibilityAdmission.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeCompatibilityCoordinator.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolution.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeOperationRequirements.swift
SOURCES := $(RUNTIME_SOURCES) main.swift
SOURCES_052 := $(RUNTIME_SOURCES) Relaxin052/main.swift
SOURCES_052_COORDINATOR := $(RUNTIME_SOURCES) Relaxin052Coordinator/main.swift

.PHONY: test clean

test: $(OUT) $(OUT_052) $(OUT_052_COORDINATOR)
	$(OUT)
	$(OUT_052)
	$(OUT_052_COORDINATOR)

$(OUT): $(SOURCES)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES) -o $@

$(OUT_052): $(SOURCES_052)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES_052) -o $@

$(OUT_052_COORDINATOR): $(SOURCES_052_COORDINATOR)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES_052_COORDINATOR) -o $@

clean:
	rm -rf $(ROOT)/build/Tests/RuntimeAbstraction
