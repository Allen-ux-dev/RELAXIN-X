ROOT := $(abspath ../../..)
ACCESS := $(ROOT)/RelaxinEngine/KernelAccess/Access
DIAGNOSTIC := $(ROOT)/RelaxinEngine/Diagnostic
BUILD := $(ROOT)/build/Tests/KernelAccessFailure
TEST := $(BUILD)/kernel_access_failure_tests

CC ?= cc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -g -fobjc-arc \
	-I$(ACCESS) \
	-I$(DIAGNOSTIC)
LDFLAGS := -framework Foundation

.PHONY: all test clean

all: $(TEST)

# Neither source reaches past Foundation, which is what makes the classification
# testable off-device: the failure type and the diagnostic builder are the whole
# dependency set.
$(TEST): kernel_access_failure_tests.m \
	$(ACCESS)/RLXKernelAccessFailure.m \
	$(ACCESS)/RLXKernelAccessFailure.h \
	$(DIAGNOSTIC)/RLXEngineDiagnostic.m \
	$(DIAGNOSTIC)/RLXEngineDiagnostic.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) \
		kernel_access_failure_tests.m \
		$(ACCESS)/RLXKernelAccessFailure.m \
		$(DIAGNOSTIC)/RLXEngineDiagnostic.m \
		$(LDFLAGS) -o $@

test: $(TEST)
	$(TEST) build-facts
	$(TEST) fold
	$(TEST) fold-no-duplicate
	$(TEST) single-kind

clean:
	rm -rf $(BUILD)
