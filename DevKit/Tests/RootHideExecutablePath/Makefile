SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

ROOT_DIRECTORY := $(abspath ../../..)
BUILD_DIRECTORY ?= $(ROOT_DIRECTORY)/build/Tests/RootHideExecutablePath
TEST_BINARY := $(BUILD_DIRECTORY)/roothide_executable_path_tests
POLICY_HEADER := $(ROOT_DIRECTORY)/Vendor/Dopamine/BaseBin/systemhook/src/relaxin_executable_path.h

CC := xcrun --sdk macosx clang
MACOS_TARGET := $(shell uname -m)-apple-macos$(shell sw_vers -productVersion)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path)
CFLAGS := -std=c11 -target $(MACOS_TARGET) -isysroot $(MACOS_SDK) \
	-Wall -Wextra -Werror -O2

.PHONY: all test clean

all: test

test: $(TEST_BINARY)
	"$(TEST_BINARY)"

$(TEST_BINARY): roothide_executable_path_tests.c $(POLICY_HEADER) Makefile
	@mkdir -p "$(BUILD_DIRECTORY)"
	$(CC) $(CFLAGS) -I"$(dir $(POLICY_HEADER))" $< -o "$@"

clean:
	rm -f "$(TEST_BINARY)"
