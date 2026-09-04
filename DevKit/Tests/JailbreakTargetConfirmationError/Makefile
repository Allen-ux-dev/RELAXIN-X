ROOT := $(abspath ../../..)
OUT_DIR := $(ROOT)/build/Tests/JailbreakTargetConfirmationError
MODULE_DIR := $(OUT_DIR)/Modules
ENGINE_MODULE := $(MODULE_DIR)/RelaxinEngine.swiftmodule
ENGINE_LIB := $(OUT_DIR)/libRelaxinEngine.so
BIN := $(OUT_DIR)/jailbreak_target_confirmation_error_tests
TEST_DIR := $(ROOT)/DevKit/Tests/JailbreakTargetConfirmationError

.PHONY: test clean

test: $(BIN)
	LD_LIBRARY_PATH="$(OUT_DIR):$$LD_LIBRARY_PATH" $(BIN)

$(ENGINE_MODULE) $(ENGINE_LIB): $(TEST_DIR)/RelaxinEngineStub.swift
	@mkdir -p $(MODULE_DIR)
	swiftc -emit-library -emit-module -module-name RelaxinEngine $< \
		-emit-module-path $(ENGINE_MODULE) -o $(ENGINE_LIB)

$(BIN): $(ENGINE_MODULE) $(ENGINE_LIB) $(ROOT)/Relaxin/Backend/JailbreakConfiguration/JailbreakTarget.swift $(TEST_DIR)/Support.swift $(TEST_DIR)/main.swift
	@mkdir -p $(OUT_DIR)
	swiftc -I $(MODULE_DIR) -L $(OUT_DIR) -lRelaxinEngine \
		$(ROOT)/Relaxin/Backend/JailbreakConfiguration/JailbreakTarget.swift \
		$(TEST_DIR)/Support.swift \
		$(TEST_DIR)/main.swift \
		-o $@

clean:
	rm -rf $(OUT_DIR)
