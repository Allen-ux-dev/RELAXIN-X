ROOT := ../../..
BUILD := .build
WIRE_TEST_BIN := $(BUILD)/PrismBuild52WireTests
SOCKET_TEST_BIN := $(BUILD)/PrismBuild52SocketTests
DEFAULTS_TEST_BIN := $(BUILD)/PrismBuild52DefaultsTests
ENDPOINT_TEST_BIN := $(BUILD)/PrismBuild52EndpointTests

CORE_SOURCES := \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52WireModels.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismLengthPrefixedJSONCodec.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52RuntimeServiceHost.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismRuntimeServiceFrameProcessor.swift

SOCKET_SOURCES := \
	$(CORE_SOURCES) \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismUnixSocketRuntimeServiceServer.swift

DEFAULTS_SOURCES := \
	$(CORE_SOURCES) \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52RuntimeDefaults.swift

ENDPOINT_SOURCES := \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52RuntimeEndpoint.swift \
	$(ROOT)/DevKit/Tests/PrismBuild52Startup/EndpointTests.swift

.PHONY: test clean

test: $(WIRE_TEST_BIN) $(SOCKET_TEST_BIN) $(DEFAULTS_TEST_BIN) $(ENDPOINT_TEST_BIN)
	./$(WIRE_TEST_BIN)
	./$(SOCKET_TEST_BIN)
	./$(DEFAULTS_TEST_BIN)
	./$(ENDPOINT_TEST_BIN)
	python3 $(ROOT)/DevKit/Tests/PrismBuild52Startup/test_contract.py

$(WIRE_TEST_BIN): $(CORE_SOURCES) PrismBuild52WireTests.swift
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(CORE_SOURCES) PrismBuild52WireTests.swift -o $(WIRE_TEST_BIN)

$(SOCKET_TEST_BIN): $(SOCKET_SOURCES) PrismBuild52SocketTests.swift
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(SOCKET_SOURCES) PrismBuild52SocketTests.swift -o $(SOCKET_TEST_BIN)

$(DEFAULTS_TEST_BIN): $(DEFAULTS_SOURCES) PrismBuild52DefaultsTests.swift
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(DEFAULTS_SOURCES) PrismBuild52DefaultsTests.swift -o $(DEFAULTS_TEST_BIN)

$(ENDPOINT_TEST_BIN): $(ENDPOINT_SOURCES)
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(ENDPOINT_SOURCES) -o $(ENDPOINT_TEST_BIN)

clean:
	rm -rf $(BUILD)
