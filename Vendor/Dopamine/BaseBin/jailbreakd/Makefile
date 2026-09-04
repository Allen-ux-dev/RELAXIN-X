TARGET = jailbreakd
DEBUG ?= 0

CC = clang
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)

CFLAGS = -Werror -Wno-availability -framework Foundation -framework CoreServices -I../.include -I./src -isysroot $(SDK) -arch arm64 -arch arm64e -miphoneos-version-min=$(MIN_IOS_VERSION) -fobjc-arc -Wno-nullability-completeness-on-arrays -O3 -DDEBUG=$(DEBUG)
LDFLAGS = -L../.build -ljailbreak -lbsm
SOURCES = $(wildcard src/*.m src/*.c)

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)

.PHONY: all clean
