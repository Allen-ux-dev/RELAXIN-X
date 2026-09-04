ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/Tests/RuntimeBaseline/runtime_baseline_tests
SOURCES := \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityRequirement.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineManifest.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareExecutionClass.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeCapability.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeEnvironment.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfile.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackend.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/LegacyRelaxinRuntimeBackend.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolution.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/KernelProfileIntegrityMetadata.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityEvaluator.swift \
	main.swift

.PHONY: test clean

test: $(OUT)
	$(OUT)
	python3 test_resource_contract.py
	python3 test_kernel_offsets_contract.py

$(OUT): $(SOURCES)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES) -o $@

clean:
	rm -rf $(ROOT)/build/Tests/RuntimeBaseline
