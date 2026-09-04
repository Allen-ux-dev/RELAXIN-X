ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/Tests/RuntimeBackendPolicy/runtime_backend_policy_tests
SOURCES := \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift \
	$(ROOT)/Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicyStore.swift \
	main.swift

.PHONY: test clean

test: $(OUT)
	$(OUT)

$(OUT): $(SOURCES)
	@mkdir -p "$(dir $@)"
	swiftc $(SOURCES) -o "$@"

clean:
	rm -rf "$(ROOT)/build/Tests/RuntimeBackendPolicy"
