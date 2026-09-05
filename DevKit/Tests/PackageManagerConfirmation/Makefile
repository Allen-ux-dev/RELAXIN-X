ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Tests/PackageManagerConfirmation
TEST := $(BUILD)/package_manager_confirmation_tests
SWIFTC ?= swiftc

SOURCES := \
	$(ROOT)/Relaxin/Backend/PackageManagers/PackageManagerSelection.swift \
	$(ROOT)/Relaxin/Backend/PackageManagers/PackageManagerInstallPlan.swift \
	$(ROOT)/Relaxin/Backend/PackageManagers/PackageManagerConfirmationDraft.swift \
	main.swift

.PHONY: all test clean
all: $(TEST)

$(TEST): $(SOURCES)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(SOURCES) -o $(TEST)

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
