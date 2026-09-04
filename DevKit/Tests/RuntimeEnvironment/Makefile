ROOT := $(abspath ../../..)
ENGINE := $(ROOT)/RelaxinEngine/Engine
POST_JAILBREAK := $(ROOT)/RelaxinPostJailbreak/Controller
BUILD := $(ROOT)/build/Tests/RuntimeEnvironment
TEST := $(BUILD)/runtime_environment_tests
FRAMEWORK_HEADERS := $(BUILD)/include/RelaxinEngine
POST_JAILBREAK_FRAMEWORK_HEADERS := $(BUILD)/include/RelaxinPostJailbreak

CC ?= cc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -g -fobjc-arc -fblocks \
	-Istubs \
	-I$(ENGINE) \
	-I$(BUILD)/include
LDFLAGS := -framework Foundation

.PHONY: all test clean

all: $(TEST)

$(FRAMEWORK_HEADERS)/RLXEngineTaskUpdate.h: $(ENGINE)/RLXEngineTaskUpdate.h
	@mkdir -p $(FRAMEWORK_HEADERS)
	ln -sf $< $@

$(FRAMEWORK_HEADERS)/RLXRuntimeEnvironment.h: $(ENGINE)/RLXRuntimeEnvironment.h
	@mkdir -p $(FRAMEWORK_HEADERS)
	ln -sf $< $@

$(POST_JAILBREAK_FRAMEWORK_HEADERS)/RLXPostJailbreakController.h: \
		$(POST_JAILBREAK)/RLXPostJailbreakController.h
	@mkdir -p $(POST_JAILBREAK_FRAMEWORK_HEADERS)
	ln -sf $< $@

$(TEST): runtime_environment_tests.m \
	$(ENGINE)/RLXEngine.m \
	$(ENGINE)/RLXEngine.h \
	$(ENGINE)/RLXRuntimeEnvironment.m \
	$(ENGINE)/RLXRuntimeEnvironment.h \
	$(FRAMEWORK_HEADERS)/RLXEngineTaskUpdate.h \
	$(FRAMEWORK_HEADERS)/RLXRuntimeEnvironment.h \
	$(POST_JAILBREAK_FRAMEWORK_HEADERS)/RLXPostJailbreakController.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) \
		runtime_environment_tests.m \
		$(ENGINE)/RLXEngine.m \
		$(ENGINE)/RLXRuntimeEnvironment.m \
		$(LDFLAGS) -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
