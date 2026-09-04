ROOT := $(abspath ../../..)
BUILD_DIR := $(ROOT)/build/Tests/RuntimeExtensibility
BINARY := $(BUILD_DIR)/runtime_extensibility_tests
SWIFTC ?= swiftc

SOURCES := \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareExecutionClass.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeCapability.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityRequirement.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineManifest.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/HardwareSupportRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/KernelProfileIntegrityMetadata.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityEvaluator.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeEnvironment.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfile.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendDescriptor.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolution.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeOperationRequirements.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeExecutionAdmission.swift \
	$(ROOT)/DevKit/Tests/RuntimeExtensibility/main.swift

.PHONY: test clean

test: $(BINARY)
	$(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) -O -o "$@" $(SOURCES)

clean:
	rm -rf "$(BUILD_DIR)"
