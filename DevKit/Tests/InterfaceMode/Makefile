ROOT := $(abspath ../../..)
MODE_SOURCE := $(ROOT)/Relaxin/Application/RelaxinInterfaceMode.swift
POST_JAILBREAK_ENVIRONMENT_SOURCE := $(ROOT)/Relaxin/Application/PostJailbreakEnvironment.swift
RUNTIME_SOURCE := $(ROOT)/Relaxin/Application/RelaxinRuntime.swift
BUILD := $(ROOT)/build/Tests/InterfaceMode
TEST := $(BUILD)/interface_mode_tests
ENGINE_MODULE := $(BUILD)/RelaxinEngine.swiftmodule
ENGINE_LIBRARY := $(BUILD)/libRelaxinEngine.a

.PHONY: all test clean

all: $(TEST)

$(ENGINE_LIBRARY): RelaxinEngineStub.swift
	@mkdir -p $(BUILD)
	xcrun --sdk macosx swiftc \
		-emit-library \
		-static \
		-emit-module \
		-module-name RelaxinEngine \
		RelaxinEngineStub.swift \
		-emit-module-path $(ENGINE_MODULE) \
		-o $@

$(TEST): main.swift $(MODE_SOURCE) $(POST_JAILBREAK_ENVIRONMENT_SOURCE) $(RUNTIME_SOURCE) $(ENGINE_LIBRARY)
	xcrun --sdk macosx swiftc \
		-I$(BUILD) \
		-L$(BUILD) \
		-lRelaxinEngine \
		$(MODE_SOURCE) \
		$(POST_JAILBREAK_ENVIRONMENT_SOURCE) \
		$(RUNTIME_SOURCE) \
		main.swift \
		-o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
