ROOT := ../../..
BUILD := .build
WIRE_TEST_BIN := $(BUILD)/PrismBuild52WireTests
SOCKET_TEST_BIN := $(BUILD)/PrismBuild52SocketTests
CORE_SOURCES := \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52WireModels.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismLengthPrefixedJSONCodec.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52RuntimeServiceHost.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismRuntimeServiceFrameProcessor.swift
SOCKET_SOURCES := \
	$(CORE_SOURCES) \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismUnixSocketRuntimeServiceServer.swift

.PHONY: test clean

test: $(WIRE_TEST_BIN) $(SOCKET_TEST_BIN)
	./$(WIRE_TEST_BIN)
	./$(SOCKET_TEST_BIN)

$(WIRE_TEST_BIN): $(CORE_SOURCES) PrismBuild52WireTests.swift
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(CORE_SOURCES) PrismBuild52WireTests.swift -o $(WIRE_TEST_BIN)

$(SOCKET_TEST_BIN): $(SOCKET_SOURCES) PrismBuild52SocketTests.swift
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(SOCKET_SOURCES) PrismBuild52SocketTests.swift -o $(SOCKET_TEST_BIN)

clean:
	rm -rf $(BUILD)
