TARGET = boomerang
DEBUG ?= 0

CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=$(MIN_IOS_VERSION) -fobjc-arc -Wno-nullability-completeness-on-arrays -O2 -DDEBUG=$(DEBUG)
LDFLAGS = -L../.build -ljailbreak

sign: $(TARGET)
	@ldid -Sentitlements.plist -Cadhoc $<

$(TARGET): $(wildcard src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
