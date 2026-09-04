ROOT := $(abspath ../../..)
BOOTSTRAP := $(ROOT)/RelaxinEngine/Bootstrap
ENGINE := $(ROOT)/RelaxinEngine/Engine
DIAGNOSTIC := $(ROOT)/RelaxinEngine/Diagnostic
POST_JAILBREAK := $(ROOT)/RelaxinPostJailbreak/Controller
BUILD := $(ROOT)/build/Tests/BootstrapFinalizer
TEST := $(BUILD)/bootstrap_finalizer_tests
FRAMEWORK_HEADERS := $(BUILD)/include/RelaxinEngine
POST_JAILBREAK_FRAMEWORK_HEADERS := $(BUILD)/include/RelaxinPostJailbreak

CC ?= cc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -g -fobjc-arc -fblocks \
	-Dgetuid=rlx_test_getuid \
	-Istubs \
	-I$(BOOTSTRAP) \
	-I$(ENGINE) \
	-I$(DIAGNOSTIC) \
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

$(TEST): bootstrap_finalizer_tests.m \
	$(BOOTSTRAP)/RLXBootstrapFinalizer.m \
	$(BOOTSTRAP)/RLXBootstrapFinalizer.h \
	$(ENGINE)/RLXEngineError.m \
	$(ENGINE)/RLXEngineError.h \
	$(DIAGNOSTIC)/RLXEngineDiagnostic.m \
	$(DIAGNOSTIC)/RLXEngineDiagnostic.h \
	$(FRAMEWORK_HEADERS)/RLXEngineTaskUpdate.h \
	$(FRAMEWORK_HEADERS)/RLXRuntimeEnvironment.h \
	$(POST_JAILBREAK_FRAMEWORK_HEADERS)/RLXPostJailbreakController.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) \
		bootstrap_finalizer_tests.m \
		$(BOOTSTRAP)/RLXBootstrapFinalizer.m \
		$(ENGINE)/RLXEngineError.m \
		$(DIAGNOSTIC)/RLXEngineDiagnostic.m \
		$(LDFLAGS) -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
