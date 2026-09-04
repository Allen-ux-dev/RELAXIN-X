TARGET := MachOMerger
DEBUG ?= 0
SWIFTC := xcrun --sdk iphoneos swiftc
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
TARGET_TRIPLE := arm64-apple-ios$(MIN_IOS_VERSION)
BUILD_DIR := .build-direct

SWIFTUTILS_SOURCES := $(shell find Dependencies/SwiftUtils/Sources/SwiftUtils -name '*.swift' -print)
SWIFTMACHO_SOURCES := $(shell find Dependencies/SwiftMachO/Sources/SwiftMachO -name '*.swift' -print)
PATCHFINDER_SOURCES := Dependencies/PatchfinderUtils/Sources/PatchfinderUtils/AArch64Instr.swift
MACHOMERGER_SOURCES := $(shell find Sources/MachOMerger -name '*.swift' -print)

SWIFTC_COMMON := \
	-sdk "$(SDK)" \
	-target $(TARGET_TRIPLE) \
	-swift-version 5 \
	-O

ifeq ($(DEBUG), 1)
SWIFTC_COMMON += -D DEBUG
endif

all: $(TARGET)

$(BUILD_DIR)/libSwiftUtils.a: $(SWIFTUTILS_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTC_COMMON) \
		-parse-as-library \
		-emit-library -static \
		-emit-module -emit-module-path $(BUILD_DIR)/SwiftUtils.swiftmodule \
		-module-name SwiftUtils \
		-o $@ \
		$^

$(BUILD_DIR)/libSwiftMachO.a: $(SWIFTMACHO_SOURCES) $(BUILD_DIR)/libSwiftUtils.a
	$(SWIFTC) $(SWIFTC_COMMON) \
		-I $(BUILD_DIR) \
		-parse-as-library \
		-emit-library -static \
		-emit-module -emit-module-path $(BUILD_DIR)/SwiftMachO.swiftmodule \
		-module-name SwiftMachO \
		-o $@ \
		$(SWIFTMACHO_SOURCES)

$(BUILD_DIR)/libPatchfinderUtils.a: $(PATCHFINDER_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTC_COMMON) \
		-parse-as-library \
		-emit-library -static \
		-emit-module -emit-module-path $(BUILD_DIR)/PatchfinderUtils.swiftmodule \
		-module-name PatchfinderUtils \
		-o $@ \
		$^

$(TARGET): \
		$(MACHOMERGER_SOURCES) \
		$(BUILD_DIR)/libSwiftUtils.a \
		$(BUILD_DIR)/libSwiftMachO.a \
		$(BUILD_DIR)/libPatchfinderUtils.a
	$(SWIFTC) $(SWIFTC_COMMON) \
		-I $(BUILD_DIR) \
		-L $(BUILD_DIR) \
		-lPatchfinderUtils \
		-lSwiftMachO \
		-lSwiftUtils \
		-framework IOKit \
		-framework CoreServices \
		-Xcc -DIOS_BUILD \
		-Xcc -Wno-incompatible-sysroot \
		-o $@ \
		$(MACHOMERGER_SOURCES)

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f $(TARGET)

.PHONY: all clean
