TARGET = jbctl
DEBUG ?= 0

CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework CoreTelephony -framework Security -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -Wno-availability -miphoneos-version-min=$(MIN_IOS_VERSION) -fobjc-arc -DDEBUG=$(DEBUG)
LDFLAGS = -L../.build -ljailbreak -lchoma

sign: $(TARGET)
	@ldid -Sentitlements.plist -Cadhoc $<

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
