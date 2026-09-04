ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/Tests/PackageManagerSelection/package_manager_selection_tests
SOURCES := \
	$(ROOT)/Relaxin/Backend/PackageManagers/PackageManagerSelection.swift \
	main.swift

.PHONY: test clean

test: $(OUT)
	$(OUT)

$(OUT): $(SOURCES)
	@mkdir -p $(dir $@)
	swiftc $(SOURCES) -o $@

clean:
	rm -rf $(ROOT)/build/Tests/PackageManagerSelection
