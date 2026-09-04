TARGET = systemhook.dylib
DEBUG ?= 0
CC = clang

CFLAGS = -I../.include -I./src -I../_external/modules/litehook/src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=$(MIN_IOS_VERSION) -install_name $(TARGET) -Wno-deprecated-declarations -Os -moutline -DDEBUG=$(DEBUG) -DSYSTEMHOOK_LOG_BACKEND_SYSLOG=1
LDFLAGS = -dynamiclib -framework CoreFoundation -Wl,-ld_classic

sign: $(TARGET)
	@ldid -S -Cadhoc $^

SYSTEMHOOK_SOURCES = $(wildcard src/*.c src/*.m ../libjailbreak/src/jbclient_*.c)

$(TARGET): $(SYSTEMHOOK_SOURCES) $(wildcard ../_external/modules/litehook/src/*.c) ../libjailbreak/src/roothider/jailbreakd.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
