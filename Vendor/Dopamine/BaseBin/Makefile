#all: mktemp choma

# Keep every host-side subproject on the compiler paired with the selected iOS SDK.
export PATH := $(dir $(shell xcrun --find clang)):$(PATH)
ifndef MIN_IOS_VERSION
$(error MIN_IOS_VERSION must be supplied by the project build)
endif
export MIN_IOS_VERSION
ifndef SIGNATURE_VERIFIER_SOURCE
$(error SIGNATURE_VERIFIER_SOURCE must be supplied by the project build)
endif
export SIGNATURE_VERIFIER_SOURCE

DEBUG ?= 0
export DEBUG

CODESIGN := /usr/bin/codesign
CODESIGN_FLAGS := --force --sign - --timestamp=none
SIGNATURE_VERIFIER := ../build/Tools/VerifyAdHocSignature
TAR := gtar

#mktemp:
#	rm -rf .build-dir
#	mkdir .build-dir

#choma:
#	$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib" $@

all: basebin.tar

subprojects: ChOma XPF MachOMerger opainject libjailbreak systemhook forkfix launchdhook boomerang jbctl watchdoghook roothidehooks jailbreakd bootstrapper

ChOma: .build .include
	@$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib"
	@cp ChOma/output/ios/lib/libchoma.dylib .build
	@ldid -S -Cadhoc .build/libchoma.dylib
	@cp -r ChOma/output/ios/include/choma .include

XPF: .build .include ChOma
	@# Rebuild only when sources are newer than the staged dylib (or missing).
	@if [ -f .build/libxpf.dylib ] \
		&& [ -z "$$(find XPF/src -type f -newer .build/libxpf.dylib -print -quit 2>/dev/null)" ]; then \
		echo "[+] libxpf.dylib up to date — skipping"; \
	else \
		rm -rf ../build/XPF; \
		mkdir -p ../build/XPF; \
		rsync -a --exclude .git XPF/ ../build/XPF/; \
		$(MAKE) -C ../build/XPF output/ios/libxpf.dylib CHOMA_PATH=../../BaseBin/ChOma CHOMA_DYLIB_PATH="../../BaseBin/.build"; \
		cp ../build/XPF/output/ios/libxpf.dylib .build/libxpf.dylib; \
		mkdir -p .include/xpf; \
		cp ../build/XPF/src/xpf.h .include/xpf; \
	fi
	@ldid -S -Cadhoc .build/libxpf.dylib

MachOMerger: .build .include
	@$(MAKE) -C MachOMerger
	@cp MachOMerger/MachOMerger .build

opainject: .build .include
	$(MAKE) -C opainject
	@cp opainject/opainject .build
	@ldid -Sopainject/entitlements.plist -Cadhoc .build/opainject

libjailbreak: .build .include ChOma
	$(MAKE) -C libjailbreak
	@cp libjailbreak/libjailbreak.dylib .build
	@mkdir -p .include/libjailbreak
	@cp libjailbreak/src/*.h .include/libjailbreak
	@mkdir -p .include/libjailbreak/roothider
	@cp libjailbreak/src/roothider/*.h .include/libjailbreak/roothider

# Simulator variants of the runtime libraries linked by RelaxinEngine. The
# simulator has no jailbreak target, but the framework must still link and
# load these dylibs; private symbols with no simulator SDK counterpart (e.g.
# IOMobileFramebuffer) stay dynamically bound and are never called on the
# simulator mock task path. The variants carry a -sim suffix so they can live
# next to the device libraries and be selected by SDK-conditional link flags.
SIM_SDK_PATH := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
SIM_VERSION_FLAG := -mios-simulator-version-min=$(MIN_IOS_VERSION)

simulator-libs: ChOma-simulator XPF-simulator libjailbreak-simulator

.build-simulator:
	mkdir -p .build-simulator

ChOma-simulator: .build-simulator
	@$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 \
		BUILD_DIR=build/ios-simulator \
		OUTPUT_DIR=output/ios-simulator \
		CFLAGS="-Wall -Werror -fPIC -Wno-pointer-to-int-cast -Wno-unused-command-line-argument -Wno-deprecated-declarations -framework CoreFoundation -DDISABLE_SIGNING=1 -DDEBUG=$(DEBUG) -arch arm64 -isysroot $(SIM_SDK_PATH) $(SIM_VERSION_FLAG)" \
		DYLIB_LDFLAGS="-install_name @loader_path/libchoma-sim.dylib"
	@cp ChOma/output/ios-simulator/lib/libchoma.dylib .build-simulator/libchoma-sim.dylib
	@ldid -S -Cadhoc .build-simulator/libchoma-sim.dylib

XPF-simulator: .build-simulator ChOma-simulator
	@rm -rf ../build/XPF-simulator
	@mkdir -p ../build/XPF-simulator
	@rsync -a --exclude .git XPF/ ../build/XPF-simulator/
	$(MAKE) -C ../build/XPF-simulator output/ios/libxpf.dylib \
		CHOMA_PATH=../../BaseBin/ChOma \
		CHOMA_DYLIB_PATH="../../BaseBin/.build-simulator" \
		CFLAGS_IOS="-O2 -framework Foundation -I../../BaseBin/ChOma/include -isysroot $(SIM_SDK_PATH) $(SIM_VERSION_FLAG) -arch arm64 -I./external/ios/include -DDEBUG=$(DEBUG)" \
		LDFLAGS="-lcompression -L../../BaseBin/.build-simulator -lchoma-sim"
	@cp ../build/XPF-simulator/output/ios/libxpf.dylib .build-simulator/libxpf-sim.dylib
	@install_name_tool -id @loader_path/libxpf-sim.dylib .build-simulator/libxpf-sim.dylib
	@ldid -S -Cadhoc .build-simulator/libxpf-sim.dylib

libjailbreak-simulator: .build-simulator .include ChOma-simulator
	$(MAKE) -C libjailbreak TARGET=libjailbreak-simulator.dylib \
		CC="xcrun --sdk iphonesimulator clang" \
		CFLAGS="-framework Foundation -framework CoreServices -framework Security -framework IOKit -framework IOSurface -framework CoreGraphics -framework ImageIO -lMobileGestalt -I../.include -I../_external/modules/litehook/src -I../_external/include/libarchive -isysroot $(SIM_SDK_PATH) -arch arm64 $(SIM_VERSION_FLAG) -fobjc-arc -dynamiclib -install_name @loader_path/libjailbreak-sim.dylib -O2 -DDEBUG=$(DEBUG)" \
		LDFLAGS="-larchive -lbsm -L../.build-simulator -F ../_external/frameworks -lchoma-sim -lc++ -undefined dynamic_lookup" \
		libjailbreak-simulator.dylib
	@cp libjailbreak/libjailbreak-simulator.dylib .build-simulator/libjailbreak-sim.dylib
	@rm -f libjailbreak/libjailbreak-simulator.dylib
	@ldid -S -Cadhoc .build-simulator/libjailbreak-sim.dylib

systemhook: .build .include libjailbreak
	$(MAKE) -C systemhook
	@cp systemhook/systemhook.dylib .build

forkfix: .build .include libjailbreak systemhook
	$(MAKE) -C forkfix
	@cp forkfix/forkfix.dylib .build

launchdhook: .build .include libjailbreak
	$(MAKE) -C launchdhook
	@cp launchdhook/launchdhook.dylib .build
	@ldid -S -Cadhoc .build/launchdhook.dylib

boomerang: .build .include libjailbreak
	$(MAKE) -C boomerang
	@cp boomerang/boomerang .build

jbctl: .build .include libjailbreak
	$(MAKE) -C jbctl
	@cp jbctl/jbctl .build

watchdoghook: .build .include libjailbreak
	$(MAKE) -C watchdoghook
	@cp watchdoghook/watchdoghook.dylib .build

roothidehooks: .build .include libjailbreak
	$(MAKE) -C roothidehooks

bootstrapper: .build .include libjailbreak
	$(MAKE) -C bootstrapper
	@cp bootstrapper/bootstrapper .build

jailbreakd: .build .include libjailbreak
	$(MAKE) -C jailbreakd
	@cp jailbreakd/jailbreakd .build/jailbreakd
	@ldid -Sjailbreakd/entitlements.plist -Cadhoc .build/jailbreakd

$(SIGNATURE_VERIFIER): $(SIGNATURE_VERIFIER_SOURCE)
	@mkdir -p $(dir $@)
	@xcrun --sdk macosx clang \
		-target "$$(uname -m)-apple-macos$$(sw_vers -productVersion)" \
		-isysroot "$$(xcrun --sdk macosx --show-sdk-path)" \
		-Wall -Wextra -Werror -O2 $< -o $@
	@/usr/bin/codesign --force --sign - --timestamp=none $@
	@/usr/bin/codesign --verify --strict $@

# Real directory targets (not phony): seed once and keep mtimes so clang's
# module cache and staged artifacts survive incremental `make -C BaseBin`.
.build:
	mkdir -p .build
	cp -r _external/basebin/* .build
	cp _external/basebin/.version _external/basebin/.AppIdentifier .build

.include:
	mkdir -p .include
	cp -rp _external/include/* .include
# If the SDK already ships XPC (it does so in iOS 17.4+), remove the local copy of it
ifneq (,$(wildcard $(shell xcrun --sdk iphoneos --show-sdk-path)/usr/include/xpc.modulemap))
	rm -rf .include/xpc
endif

codesign-basebin: subprojects $(SIGNATURE_VERIFIER)
	@for binary in \
		.build/fallback/CydiaSubstrate.framework/CydiaSubstrate \
		.build/forkfix.dylib \
		.build/launchdhook.dylib \
		.build/libchoma.dylib \
		.build/libjailbreak.dylib \
		.build/libxpf.dylib \
		.build/roothidehooks.dylib \
		.build/systemhook.dylib \
		.build/watchdoghook.dylib; do \
		$(CODESIGN) $(CODESIGN_FLAGS) "$$binary"; \
	done
	@$(CODESIGN) $(CODESIGN_FLAGS) --entitlements MachOMerger/MachOMerger.entitlements .build/MachOMerger
	@$(CODESIGN) $(CODESIGN_FLAGS) --entitlements boomerang/entitlements.plist .build/boomerang
	@$(CODESIGN) $(CODESIGN_FLAGS) --entitlements bootstrapper/entitlements.plist .build/bootstrapper
	@$(CODESIGN) $(CODESIGN_FLAGS) --entitlements jailbreakd/entitlements.plist .build/jailbreakd
	@$(CODESIGN) $(CODESIGN_FLAGS) --entitlements jbctl/entitlements.plist .build/jbctl
	@$(CODESIGN) $(CODESIGN_FLAGS) --entitlements opainject/entitlements.plist .build/opainject
	@for binary in \
		.build/fallback/CydiaSubstrate.framework/CydiaSubstrate \
		.build/forkfix.dylib \
		.build/launchdhook.dylib \
		.build/libchoma.dylib \
		.build/libjailbreak.dylib \
		.build/libxpf.dylib \
		.build/roothidehooks.dylib \
		.build/systemhook.dylib \
		.build/watchdoghook.dylib \
		.build/MachOMerger \
		.build/boomerang \
		.build/bootstrapper \
		.build/jailbreakd \
		.build/jbctl \
		.build/opainject; do \
		$(SIGNATURE_VERIFIER) "$$binary"; \
		$(CODESIGN) --verify --strict "$$binary"; \
	done

basebin.tc: codesign-basebin
	trustcache create \
		-u 00000000-0000-0000-0000-000000000000 \
		.build/basebin.tc \
		.build
	cp .build/basebin.tc basebin.tc

# dyldhook dylibs do not need to be added to the basebin trustcache
dyldhook: basebin.tc
	$(MAKE) -C dyldhook
	@cp dyldhook/*.dylib .build
	@for binary in .build/dyldhook_*.dylib; do \
		$(CODESIGN) $(CODESIGN_FLAGS) "$$binary"; \
		$(SIGNATURE_VERIFIER) "$$binary"; \
		$(CODESIGN) --verify --strict "$$binary"; \
	done

basebin.tar: basebin.tc dyldhook
	@find ./.build -name ".DS_Store" -delete
	@$(TAR) \
		--sort=name \
		--mtime="@$(SOURCE_DATE_EPOCH)" \
		--clamp-mtime \
		--owner=0 \
		--group=0 \
		--transform "s/^.build/basebin/" \
		-cvf "basebin.tar" ".build"

clean:
	@$(MAKE) -C ChOma $@
	@$(MAKE) -C XPF $@
	@$(MAKE) -C MachOMerger $@
	@$(MAKE) -C opainject $@
	@$(MAKE) -C libjailbreak $@
	@$(MAKE) -C systemhook $@
	@$(MAKE) -C forkfix $@
	@$(MAKE) -C launchdhook $@
	@$(MAKE) -C boomerang $@
	@$(MAKE) -C jbctl $@
	@$(MAKE) -C watchdoghook $@
	@$(MAKE) -C roothidehooks $@
	@$(MAKE) -C bootstrapper $@
	@$(MAKE) -C jailbreakd $@
	@$(MAKE) -C dyldhook $@
	@rm -rf .build
	@rm -rf .build-simulator
	@rm -rf .include
	@rm -rf basebin.tar
	@rm -rf basebin.tc
	@rm -rf ../build/XPF
	@rm -rf ../build/XPF-simulator

.PHONY: clean ChOma XPF MachOMerger opainject libjailbreak systemhook forkfix launchdhook boomerang jbctl watchdoghook roothidehooks codesign-basebin basebin.tc dyldhook basebin.tar jailbreakd bootstrapper subprojects simulator-libs ChOma-simulator XPF-simulator libjailbreak-simulator
