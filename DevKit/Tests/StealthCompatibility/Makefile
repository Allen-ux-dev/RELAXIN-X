ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Tests/StealthCompatibility
TEST := $(BUILD)/stealth_compatibility_tests
SOURCES := \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift \
	$(ROOT)/Relaxin/Backend/StealthCompatibility/AppStealthProfile.swift \
	$(ROOT)/Relaxin/Backend/StealthCompatibility/StealthProfileResolver.swift \
	$(ROOT)/Relaxin/Backend/StealthCompatibility/StealthProfileRevalidator.swift \
	$(ROOT)/Relaxin/Backend/StealthCompatibility/StealthHealthInspector.swift \
	$(ROOT)/Relaxin/Backend/StealthCompatibility/StealthProfileStore.swift

ifeq ($(shell command -v xcrun >/dev/null 2>&1; echo $$?),0)
SWIFTC := xcrun --sdk macosx swiftc
else
SWIFTC := swiftc
endif

.PHONY: all test clean
all: $(TEST)

$(TEST): main.swift $(SOURCES)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(SOURCES) main.swift -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
