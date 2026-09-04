ROOT := $(abspath ../../..)
ANALYSIS := $(ROOT)/RelaxinEngine/KernelAccess/Analysis
PROFILE := $(ROOT)/RelaxinEngine/KernelAccess/Exploit/Rocket/Profile
LOG := $(ROOT)/RelaxinEngine/Log
KERNEL_ACCESS := $(ROOT)/RelaxinEngine/KernelAccess
BUILD := $(ROOT)/build/Tests/KernelOffsetTable
TEST := $(BUILD)/kernel_offset_table_tests
SHIPPED_TABLE := $(ROOT)/Relaxin/Resources/KernelOffsets.plist

CC ?= cc
PYTHON ?= python3
# The reader is compiled for the host, which is what makes the plist contract
# testable off-device: it reaches Foundation, xpc, and the two engine headers
# that describe the layout, and nothing else.
FRAMEWORK_HEADERS := $(BUILD)/include/RelaxinEngine
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -g -fobjc-arc -fblocks \
	-I$(ANALYSIS) \
	-I$(LOG) \
	-I$(BUILD)/include
LDFLAGS := -framework Foundation

.PHONY: all test clean

all: $(TEST)

# RLXKernelInfo.h reaches its neighbour as <RelaxinEngine/RLXKernelLayout.h>,
# which is the framework's own name for it. Xcode supplies that mapping; here
# it is staged by hand.
$(FRAMEWORK_HEADERS)/RLXKernelLayout.h: $(KERNEL_ACCESS)/RLXKernelLayout.h
	@mkdir -p $(FRAMEWORK_HEADERS)
	cp $< $@

$(TEST): kernel_offset_table_tests.m \
	$(ANALYSIS)/RLXKernelOffsetTable.m \
	$(ANALYSIS)/RLXKernelOffsetTable.h \
	$(PROFILE)/Platform.c \
	$(PROFILE)/Platform.h \
	$(LOG)/RLXEngineLog.m \
	$(LOG)/RLXEngineLog.h \
	$(FRAMEWORK_HEADERS)/RLXKernelLayout.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) \
		kernel_offset_table_tests.m \
		$(ANALYSIS)/RLXKernelOffsetTable.m \
		$(PROFILE)/Platform.c \
		$(LOG)/RLXEngineLog.m \
		$(LDFLAGS) -o $@

test: $(TEST)
	$(PYTHON) kernel_offset_tool_tests.py
	$(TEST) round-trip
	$(TEST) ppl-without-gfx
	$(TEST) cpu-family-fitness
	$(TEST) miss
	$(TEST) future-schema
	$(TEST) future-profile-version
	$(TEST) incomplete-profile
	$(TEST) incomplete-gfx-profile
	$(TEST) non-dictionary-profile
	$(TEST) sptm-without-arguments
	$(TEST) out-of-range-index
	$(TEST) bundle-isolation
	@if [ -f "$(SHIPPED_TABLE)" ]; then \
		$(TEST) shipped "$(SHIPPED_TABLE)"; \
	else \
		echo "skip shipped: $(SHIPPED_TABLE) is absent"; \
	fi

clean:
	rm -rf $(BUILD)
