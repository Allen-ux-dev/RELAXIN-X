TARGET = libjailbreak.dylib

CC = xcrun --sdk iphoneos clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -framework IOKit -framework IOSurface -framework IOMobileFramebuffer -framework CoreGraphics -framework ImageIO -lMobileGestalt -I../.include -I../_external/modules/litehook/src -I../_external/include/libarchive -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=$(MIN_IOS_VERSION) -fobjc-arc -dynamiclib -install_name @loader_path/$(TARGET) -O2
DEBUG ?= 0
CFLAGS += -DDEBUG=$(DEBUG)
LDFLAGS = -larchive -lbsm -L../.build -F ../_external/frameworks -lchoma
LDFLAGS += -lc++

CORE_SOURCES = $(wildcard src/*.c src/*.m src/*.S)
ROOTHIDER_SOURCES = $(wildcard src/roothider/*.c src/roothider/*.m src/roothider/*.cpp)

sign: $(TARGET)
	@ldid -S -Cadhoc $<

$(TARGET): Makefile $(CORE_SOURCES) $(wildcard ../_external/modules/litehook/src/*.c) $(ROOTHIDER_SOURCES)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(filter-out Makefile,$^)

clean:
	@rm -f $(TARGET)
