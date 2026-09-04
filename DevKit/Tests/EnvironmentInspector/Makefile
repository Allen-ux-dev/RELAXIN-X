ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Tests/EnvironmentInspector
TEST := $(BUILD)/environment_inspector_tests
BOOTSTRAP_IMPL := $(ROOT)/RelaxinEngine/Inspection/RLXBootstrapEnvironmentInspector.m
PACKAGE_IMPL := $(ROOT)/RelaxinPostJailbreak/Inspection/RLXPackageManagerHealthInspector.m

.PHONY: all test clean contract

contract:
	python3 test_read_only_contract.py
	python3 test_swift_bridge_contract.py
	python3 test_baseline_integrity_contract.py

ifeq ($(shell command -v xcrun >/dev/null 2>&1; echo $$?),0)
all: $(TEST)

$(TEST): environment_inspector_tests.m $(BOOTSTRAP_IMPL) $(PACKAGE_IMPL)
	@mkdir -p $(BUILD)
	xcrun --sdk macosx clang -fobjc-arc -framework Foundation \
		environment_inspector_tests.m $(BOOTSTRAP_IMPL) $(PACKAGE_IMPL) -o $@

test: contract $(TEST)
	$(TEST)
else
all: contract

test: contract
	@echo "note: Objective-C functional inspector test requires macOS/xcrun; source contract passed"
endif

clean:
	rm -rf $(BUILD)
