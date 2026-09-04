# Host build of the kernelcache offset dumper.
#
# The tool links macOS builds of ChOma and XPF, and compiles the engine's own
# StaticProfile.c / Patterns.c / XNUVersion.c. Sharing those sources is the
# point: the table this produces has to be what the device would have computed.

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

ROOT_DIR   := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../../..)
BASEBIN    := $(ROOT_DIR)/Vendor/Dopamine/BaseBin
ROCKET     := $(ROOT_DIR)/RelaxinEngine/KernelAccess/Exploit/Rocket
WORK       := $(ROOT_DIR)/build/KernelOffsets
CHOMA_WORK := $(WORK)/ChOma
XPF_WORK   := $(WORK)/XPF
INCLUDE    := $(WORK)/include
OBJ        := $(WORK)/obj
TOOL       := $(WORK)/rlx-dump-kernel-offsets

CHOMA_LIB  := $(CHOMA_WORK)/output/lib/libchoma.a
CHOMA_INC  := $(CHOMA_WORK)/output/include

XPF_SOURCES := $(wildcard $(BASEBIN)/XPF/src/*.c)
XPF_OBJECTS := $(patsubst $(BASEBIN)/XPF/src/%.c,$(OBJ)/xpf-%.o,$(XPF_SOURCES))

ENGINE_SOURCES := \
    $(ROCKET)/Profile/StaticProfile.c \
    $(ROCKET)/Profile/XNUVersion.c \
    $(ROCKET)/Backend/GFX/Patterns.c \
    $(ROCKET)/Backend/GFX/Status.c \
    $(ROCKET)/Profile/Platform.c
ENGINE_OBJECTS := $(patsubst %.c,$(OBJ)/engine-%.o,$(notdir $(ENGINE_SOURCES)))

CC := clang
# -Wno-deprecated-declarations: ChOma and XPF both call sbrk-era APIs that the
# iOS build already tolerates; this build must not be stricter than that one.
CFLAGS := -O2 -g -fblocks -Wno-deprecated-declarations \
    -I$(INCLUDE) -I$(CHOMA_INC) -mmacosx-version-min=11.0
LDFLAGS := -lcompression -framework Foundation

.PHONY: all clean tool

all: tool

tool: $(TOOL)

$(CHOMA_LIB):
	@mkdir -p $(dir $(CHOMA_WORK))
	@rsync -a --exclude .git --exclude build --exclude output \
	    "$(BASEBIN)/ChOma/" "$(CHOMA_WORK)/"
	@$(MAKE) -C "$(CHOMA_WORK)" DISABLE_SIGNING=1 DISABLE_TESTS=1 \
	    output/lib/libchoma.a copy-choma-headers

# The engine sources include their dependencies the way the iOS target presents
# them — <xpf/xpf.h>, <libjailbreak/info.h>, <choma/...> — so the staged tree
# reproduces those names from the in-repo sources rather than from a BaseBin
# build that may not have run.
$(INCLUDE)/xpf/xpf.h: $(CHOMA_LIB)
	@mkdir -p $(INCLUDE)/xpf $(INCLUDE)/libjailbreak/roothider
	@cp "$(BASEBIN)/XPF/src/xpf.h" "$(INCLUDE)/xpf/xpf.h"
	@rm -rf "$(INCLUDE)/choma"
	@cp -R "$(CHOMA_INC)/choma" "$(INCLUDE)/choma"
	@cp "$(BASEBIN)"/libjailbreak/src/*.h "$(INCLUDE)/libjailbreak/"
	@cp "$(BASEBIN)"/libjailbreak/src/roothider/*.h \
	    "$(INCLUDE)/libjailbreak/roothider/"
	@rsync -a "$(BASEBIN)/_external/include/" "$(INCLUDE)/"

$(OBJ)/xpf-%.o: $(BASEBIN)/XPF/src/%.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ)/engine-StaticProfile.o: $(ROCKET)/Profile/StaticProfile.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ)/engine-XNUVersion.o: $(ROCKET)/Profile/XNUVersion.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ)/engine-Platform.o: $(ROCKET)/Profile/Platform.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ)/engine-Patterns.o: $(ROCKET)/Backend/GFX/Patterns.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ)/engine-Status.o: $(ROCKET)/Backend/GFX/Status.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ)/dump-kernel-offsets.o: dump-kernel-offsets.c $(INCLUDE)/xpf/xpf.h
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -c $< -o $@

$(TOOL): $(OBJ)/dump-kernel-offsets.o $(ENGINE_OBJECTS) $(XPF_OBJECTS) $(CHOMA_LIB)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $(OBJ)/dump-kernel-offsets.o $(ENGINE_OBJECTS) \
	    $(XPF_OBJECTS) $(CHOMA_LIB) $(LDFLAGS)

clean:
	@rm -rf "$(WORK)"
