ROOT := ../../..
BUILD := .build
TEST_BIN := $(BUILD)/PrismBuild52WireTests
SOURCES := \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52WireModels.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismLengthPrefixedJSONCodec.swift \
	$(ROOT)/Relaxin/Backend/PrismRuntimeBridge/PrismBuild52RuntimeServiceHost.swift \
	PrismBuild52WireTests.swift

.PHONY: test clean

test: $(TEST_BIN)
	./$(TEST_BIN)

$(TEST_BIN): $(SOURCES)
	@mkdir -p $(BUILD)
	swiftc -parse-as-library $(SOURCES) -o $(TEST_BIN)

clean:
	rm -rf $(BUILD)
