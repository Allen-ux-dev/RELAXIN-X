SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

ROOT_DIRECTORY := $(abspath ../../..)
BUILD_DIRECTORY ?= $(ROOT_DIRECTORY)/build/Tests/RootHideSignaturePolicy
TEST_BINARY := $(BUILD_DIRECTORY)/roothide_signature_policy_tests
POLICY_DIRECTORY := $(ROOT_DIRECTORY)/Vendor/Dopamine/BaseBin/libjailbreak/src/roothider

CC := xcrun --sdk macosx clang
MACOS_TARGET := $(shell uname -m)-apple-macos$(shell sw_vers -productVersion)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path)
CFLAGS := -std=c11 -target $(MACOS_TARGET) -isysroot $(MACOS_SDK) \
	-Wall -Wextra -Werror -O2

SOURCES := roothide_signature_policy_tests.c \
	$(POLICY_DIRECTORY)/signature_policy.c
HEADERS := $(POLICY_DIRECTORY)/signature_policy.h

.PHONY: all test clean

all: test

test: $(TEST_BINARY)
	"$(TEST_BINARY)"

$(TEST_BINARY): $(SOURCES) $(HEADERS) Makefile
	@mkdir -p "$(BUILD_DIRECTORY)"
	$(CC) $(CFLAGS) -I"$(POLICY_DIRECTORY)" $(SOURCES) -o "$@"

clean:
	rm -f "$(TEST_BINARY)"
