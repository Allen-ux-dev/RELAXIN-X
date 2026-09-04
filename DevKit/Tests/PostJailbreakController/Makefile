ROOT := $(abspath ../../..)
MODULE := $(ROOT)/RelaxinPostJailbreak
BUILD := $(ROOT)/build/Tests/PostJailbreakController
TEST := $(BUILD)/post_jailbreak_controller_tests

CC ?= cc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -g -fobjc-arc -fblocks \
	-I$(MODULE)/Controller \
	-I$(MODULE)/Actions
LDFLAGS := -framework Foundation

.PHONY: all test clean

all: $(TEST)

$(TEST): post_jailbreak_controller_tests.m \
	$(MODULE)/Controller/RLXPostJailbreakController.m \
	$(MODULE)/Controller/RLXPostJailbreakController.h \
	$(MODULE)/Controller/RLXPostJailbreakLog.m \
	$(MODULE)/Controller/RLXPostJailbreakLog.h \
	$(MODULE)/Actions/RLXPostJailbreakActionRunner.m \
	$(MODULE)/Actions/RLXPostJailbreakActionRunner.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) \
		post_jailbreak_controller_tests.m \
		$(MODULE)/Controller/RLXPostJailbreakController.m \
		$(MODULE)/Controller/RLXPostJailbreakLog.m \
		$(MODULE)/Actions/RLXPostJailbreakActionRunner.m \
		$(LDFLAGS) -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
