ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/Tests/PrismRuntimeHandshake/prism_runtime_handshake_tests
SOURCES := \
	$(wildcard $(ROOT)/Relaxin/Backend/RuntimeServiceHost/Contracts/*.swift) \
	$(ROOT)/Relaxin/Backend/RuntimeServiceHost/CapabilityRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeServiceHost/LegacyCapabilityAliasRegistry.swift \
	$(ROOT)/Relaxin/Backend/RuntimeServiceHost/RuntimeDescriptorFactory.swift \
	$(ROOT)/Relaxin/Backend/RuntimeServiceHost/RuntimeHealthSnapshot.swift \
	$(ROOT)/Relaxin/Backend/RuntimeServiceHost/RuntimeHealthComposer.swift \
	$(wildcard $(ROOT)/Relaxin/Backend/RuntimeServiceHost/Handshake/*.swift) \
	$(wildcard $(ROOT)/Relaxin/Backend/RuntimeServiceHost/ProviderRegistry/*.swift) \
	$(ROOT)/Relaxin/Backend/RuntimeServiceHost/BackgroundService/BackgroundSessionState.swift \
	$(wildcard $(ROOT)/Relaxin/Backend/RuntimeServiceHost/RuntimeServiceError.swift) \
	main.swift

.PHONY: test clean

test: $(OUT)
	$(OUT)

$(OUT): $(SOURCES)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES) -o $@

clean:
	rm -rf $(ROOT)/build/Tests/PrismRuntimeHandshake
