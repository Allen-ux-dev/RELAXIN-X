TARGET = forkfix.dylib
DEBUG ?= 0
CC = clang

CFLAGS = -I../.include -I./src -I../_external/modules/litehook/src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -Wno-deprecated-declarations -miphoneos-version-min=$(MIN_IOS_VERSION) -O2 -DDEBUG=$(DEBUG)
LDFLAGS = -dynamiclib

sign: $(TARGET)
	@ldid -S -Cadhoc $^

$(TARGET): $(wildcard src/*.c src/*.S ../libjailbreak/src/jbclient_*.c ../_external/modules/litehook/src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
