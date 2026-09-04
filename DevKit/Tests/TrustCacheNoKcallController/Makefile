ROOT := ../../..
SRC := $(ROOT)/Vendor/Dopamine/BaseBin/libjailbreak/src
BUILD := .build
TEST := $(BUILD)/trustcache_nokcall_controller_tests

CC ?= xcrun clang
CFLAGS := -std=c11 -Wall -Wextra -Werror -g \
	-fsanitize=address,undefined \
	-I$(SRC) \
	-DRELAXIN_BASEBIN_DEBUG=1
LDFLAGS := -fsanitize=address,undefined

.PHONY: all test clean

all: $(TEST)

$(TEST): trustcache_nokcall_controller_tests.c \
	$(SRC)/trustcache_nokcall_controller.c \
	$(SRC)/trustcache_nokcall_controller.h \
	$(SRC)/trustcache_nokcall_model.c \
	$(SRC)/trustcache_nokcall_model.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) \
		trustcache_nokcall_controller_tests.c \
		$(SRC)/trustcache_nokcall_controller.c \
		$(SRC)/trustcache_nokcall_model.c \
		$(LDFLAGS) -o $@

test: $(TEST)
	ASAN_OPTIONS=detect_leaks=0 $(TEST)

clean:
	rm -rf $(BUILD)
