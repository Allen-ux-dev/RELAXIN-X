SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

ROOT_DIRECTORY := $(abspath ../../..)
BUILD_DIRECTORY ?= $(ROOT_DIRECTORY)/build/Tests/TrustCacheNoKcallModel
TEST_BINARY := $(BUILD_DIRECTORY)/trustcache_nokcall_model_tests
MODEL_DIRECTORY := $(ROOT_DIRECTORY)/Vendor/Dopamine/BaseBin/libjailbreak/src

CC := xcrun --sdk macosx clang
MACOS_TARGET := $(shell uname -m)-apple-macos$(shell sw_vers -productVersion)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path)
CFLAGS := -std=c11 -target $(MACOS_TARGET) -isysroot $(MACOS_SDK) \
	-Wall -Wextra -Werror -O2

SOURCES := trustcache_nokcall_model_tests.c \
	$(MODEL_DIRECTORY)/trustcache_nokcall_model.c
HEADERS := $(MODEL_DIRECTORY)/trustcache_nokcall_model.h

.PHONY: all test clean

all: test

test: $(TEST_BINARY)
	"$(TEST_BINARY)"

$(TEST_BINARY): $(SOURCES) $(HEADERS) Makefile
	@mkdir -p "$(BUILD_DIRECTORY)"
	$(CC) $(CFLAGS) -I"$(MODEL_DIRECTORY)" $(SOURCES) -o "$@"

clean:
	rm -f "$(TEST_BINARY)"
