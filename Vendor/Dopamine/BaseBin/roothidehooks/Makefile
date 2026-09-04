MIN_IOS_VERSION ?=
ifeq ($(strip $(MIN_IOS_VERSION)),)
$(error MIN_IOS_VERSION is required)
endif

DEBUG ?= 0
SDK ?= iphoneos
ARCHS ?= arm64 arm64e
OUTPUT_DIR ?= $(abspath $(CURDIR)/../.build)
OBJECT_DIR := $(CURDIR)/.objects

BASEBIN_DIR := $(abspath $(CURDIR)/..)
VENDOR_DIR := $(abspath $(CURDIR)/../../..)
OUTPUT := $(OUTPUT_DIR)/roothidehooks.dylib
SOURCES := $(sort $(wildcard $(CURDIR)/*.m))
OBJECTS := $(patsubst $(CURDIR)/%.m,$(OBJECT_DIR)/%.o,$(SOURCES))
HEADERS := $(sort $(wildcard $(CURDIR)/*.h)) \
	$(VENDOR_DIR)/CaptainHook/CaptainHook.h
LINK_INPUTS := \
	$(BASEBIN_DIR)/.build/libjailbreak.dylib \
	$(BASEBIN_DIR)/_external/lib/libellekit.tbd \
	$(BASEBIN_DIR)/_external/lib/libroothide.tbd

CC := xcrun --sdk $(SDK) clang
ARCH_FLAGS := $(foreach arch,$(ARCHS),-arch $(arch))
CPPFLAGS := \
	-I$(VENDOR_DIR) \
	-I$(BASEBIN_DIR)/.include \
	-I$(BASEBIN_DIR)/_external/include
CFLAGS := \
	$(ARCH_FLAGS) \
	-miphoneos-version-min=$(MIN_IOS_VERSION) \
	-fobjc-arc \
	-fblocks \
	-Werror \
	-DDEBUG=$(DEBUG)
LDFLAGS := \
	$(ARCH_FLAGS) \
	-miphoneos-version-min=$(MIN_IOS_VERSION) \
	-dynamiclib \
	-Wl,-install_name,/basebin/roothidehooks.dylib \
	-Wl,-rpath,@loader_path/.jbroot/Library/Frameworks \
	-Wl,-rpath,@loader_path/fallback \
	-L$(BASEBIN_DIR)/.build \
	-L$(BASEBIN_DIR)/_external/lib \
	-ljailbreak \
	-lellekit \
	-lroothide \
	-framework Foundation \
	-framework CoreFoundation \
	-framework Security

.DEFAULT_GOAL := all

all: $(OUTPUT)

$(OUTPUT): $(OBJECTS) $(LINK_INPUTS)
	@mkdir -p $(OUTPUT_DIR)
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@

$(OBJECT_DIR)/%.o: $(CURDIR)/%.m $(HEADERS)
	@mkdir -p $(OBJECT_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OBJECT_DIR)/lsd.o: CFLAGS += -fno-objc-arc

clean:
	rm -f $(OUTPUT)
	rm -rf $(OBJECT_DIR)

.PHONY: all clean
