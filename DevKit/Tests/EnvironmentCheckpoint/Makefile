ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Tests/EnvironmentCheckpoint
TEST := $(BUILD)/environment_checkpoint_tests
SOURCES := \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/StaleStateInvalidator.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/RecoveryOperation.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/RecoveryStage.swift \
	$(ROOT)/Relaxin/Backend/EnvironmentRecovery/EnvironmentCheckpointStore.swift

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
	python3 test_runtime_checkpoint_contract.py
	$(TEST)

clean:
	rm -rf $(BUILD)
