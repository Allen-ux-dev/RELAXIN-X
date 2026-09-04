ROOT := $(abspath ../../..)
SRC := $(ROOT)/RelaxinEngine/KernelAccess/Exploit/Rocket/Bootstrap
BUILD := $(ROOT)/build/Tests/CopyioWindow
TEST := $(BUILD)/copyio_window_tests

CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Werror -g -I$(SRC)

.PHONY: all test clean

all: $(TEST)

$(TEST): copyio_window_tests.c $(SRC)/CopyioWindow.c $(SRC)/CopyioWindow.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) copyio_window_tests.c $(SRC)/CopyioWindow.c -o $@

test: $(TEST)
	$(TEST) edges
	$(TEST) not-degenerate
	$(TEST) krw-band
	$(TEST) fixed-width
	$(TEST) signed-pointers

clean:
	rm -rf $(BUILD)
