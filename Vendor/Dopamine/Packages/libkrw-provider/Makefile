TARGET = libkrw-dopamine.dylib
CC = clang
SIGNATURE_VERIFIER = ../../build/Tools/VerifyAdHocSignature

CFLAGS = -I../../BaseBin/.include -Isrc -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=$(MIN_IOS_VERSION) -fobjc-arc -O2
LDFLAGS = -dynamiclib -rpath @loader_path/.jbroot/usr/lib -L../../BaseBin/.build -ljailbreak

all: $(TARGET) sign

$(SIGNATURE_VERIFIER): $(SIGNATURE_VERIFIER_SOURCE)
	@mkdir -p $(dir $@)
	@xcrun --sdk macosx clang \
		-target "$$(uname -m)-apple-macos$$(sw_vers -productVersion)" \
		-isysroot "$$(xcrun --sdk macosx --show-sdk-path)" \
		-Wall -Wextra -Werror -O2 $< -o $@
	@/usr/bin/codesign --force --sign - --timestamp=none $@
	@/usr/bin/codesign --verify --strict $@

sign: $(TARGET) $(SIGNATURE_VERIFIER)
	@/usr/bin/codesign --force --sign - --timestamp=none $(TARGET)
	@$(SIGNATURE_VERIFIER) $(TARGET)
	@/usr/bin/codesign --verify --strict $(TARGET)

$(TARGET): $(wildcard src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	install_name_tool -change "@loader_path/libjailbreak.dylib" "@rpath/libjailbreak.dylib" $@

clean:
	@rm -f $(TARGET)
	@rm -f libkrw-dopamine.deb

package: all
	@mkdir -p .package/DEBIAN
	@mkdir -p .package/usr/lib/libkrw
	@cp control .package/DEBIAN/control
	@cp libkrw-dopamine.dylib .package/usr/lib/libkrw/libkrw-dopamine.dylib
	@dpkg-deb --root-owner-group -Zzstd -b .package ./libkrw-dopamine.deb
	@rm -rf .package
