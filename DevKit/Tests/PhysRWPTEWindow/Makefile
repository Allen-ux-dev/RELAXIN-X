ROOT := $(abspath ../../..)
SRC := $(ROOT)/Vendor/Dopamine/BaseBin/libjailbreak/src
BUILD := $(ROOT)/build/Tests/PhysRWPTEWindow
TEST := $(BUILD)/physrw_pte_window_tests

CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Werror -g -I$(SRC)

.PHONY: all test clean

all: $(TEST)

$(TEST): physrw_pte_window_tests.c $(SRC)/physrw_pte_window.c $(SRC)/physrw_pte_window.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) physrw_pte_window_tests.c $(SRC)/physrw_pte_window.c -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
