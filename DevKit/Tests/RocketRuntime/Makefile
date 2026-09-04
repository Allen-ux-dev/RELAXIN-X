ROOT := $(abspath ../../..)
ACCESS := $(ROOT)/RelaxinEngine/KernelAccess/Access
BUILD := $(ROOT)/build/Tests/RocketRuntime
INCLUDE := $(BUILD)/include
TEST := $(BUILD)/rocket_runtime_owner_tests

CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Werror -g -pthread \
	-I$(ACCESS) \
	-I$(CURDIR)/Stubs \
	-I$(INCLUDE)
LDFLAGS := -pthread

.PHONY: all test clean

all: $(TEST)

# RLXKernelAccess.h reaches for the framework-style <RelaxinEngine/...> path, so
# the real public header is linked into place rather than copied: the test is
# meant to fail when that ABI changes under it.
$(TEST): rocket_runtime_owner_tests.c \
	$(ACCESS)/RLXRocketRuntime.c \
	$(ACCESS)/RLXRocketRuntime.h \
	$(ROOT)/RelaxinEngine/KernelAccess/RLXKernelAccess.h \
	Stubs/libjailbreak/primitives_external.h
	@mkdir -p $(INCLUDE)/RelaxinEngine
	@ln -sf $(ROOT)/RelaxinEngine/KernelAccess/RLXKernelLayout.h \
		$(INCLUDE)/RelaxinEngine/RLXKernelLayout.h
	$(CC) $(CFLAGS) \
		rocket_runtime_owner_tests.c \
		$(ACCESS)/RLXRocketRuntime.c \
		$(LDFLAGS) -o $@

# The runtime's state is process-global and its Dirty latch is terminal, so each
# case gets its own process rather than a reset nothing else would ever call.
test: $(TEST)
	$(TEST) owner-race
	$(TEST) stale-generation
	$(TEST) repeated-finalize
	$(TEST) acquire-without-start
	$(TEST) dirty-latch
	$(TEST) drain-in-flight
	$(TEST) drain-timeout

clean:
	rm -rf $(BUILD)
