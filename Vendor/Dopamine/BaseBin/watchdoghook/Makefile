TARGET = watchdoghook.dylib
DEBUG ?= 0
CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=$(MIN_IOS_VERSION) -fobjc-arc -O2 -DDEBUG=$(DEBUG)
LDFLAGS = -dynamiclib -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/fallback -L../_external/lib -lellekit -framework IOKit

sign: $(TARGET)
	@ldid -S -Cadhoc $^

$(TARGET): $(wildcard src/*.m src/*.c) ../libjailbreak/src/jbclient_mach.c ../libjailbreak/src/jbclient_xpc.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
