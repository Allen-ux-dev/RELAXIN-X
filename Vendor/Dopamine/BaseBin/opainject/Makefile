TARGET := opainject
DEBUG ?= 0
CC := clang
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
ARCH_FLAGS := -arch arm64 -arch arm64e
SOURCES := main.m dyld.m shellcode_inject.m rop_inject.m thread_utils.m task_utils.m arm64.m

CFLAGS := \
	-isysroot $(SDK) \
	$(ARCH_FLAGS) \
	-miphoneos-version-min=$(MIN_IOS_VERSION) \
	-F../_external/frameworks \
	-fobjc-arc \
	-DTHEOS_LEAN_AND_MEAN \
	-DDEBUG=$(DEBUG) \
	-O2
LDFLAGS := \
	-framework Foundation \
	-framework CoreFoundation \
	-framework CoreSymbolication \
	-Wl,-rpath,/var/jb/Library/Frameworks \
	-Wl,-rpath,/var/jb/usr/lib \
	-Wl,-rpath,@loader_path/.jbroot/Library/Frameworks \
	-Wl,-rpath,@loader_path/.jbroot/usr/lib

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)

.PHONY: all clean
