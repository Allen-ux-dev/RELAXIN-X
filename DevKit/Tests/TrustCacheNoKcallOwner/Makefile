ROOT := $(abspath ../../..)
SRC := $(ROOT)/Vendor/Dopamine/BaseBin/libjailbreak/src
BUILD := $(ROOT)/build/Tests/TrustCacheNoKcallOwner
TEST := $(BUILD)/trustcache_nokcall_owner_tests
NON_OWNER_TEST := $(BUILD)/trustcache_nokcall_owner_non_owner_tests

CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Werror -g -pthread \
	-D_GNU_SOURCE \
	-I$(SRC)
LDFLAGS := -pthread

.PHONY: all test clean

all: $(TEST) $(NON_OWNER_TEST)

$(TEST): trustcache_nokcall_owner_tests.c \
	$(SRC)/trustcache_nokcall_owner.c \
	$(SRC)/trustcache_nokcall_owner.h \
	$(SRC)/trustcache_nokcall_controller.h \
	$(SRC)/trustcache_nokcall_model.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DTCNO_OWNER_TEST_PROCESS_ID=1 \
		trustcache_nokcall_owner_tests.c \
		$(SRC)/trustcache_nokcall_owner.c \
		$(LDFLAGS) -o $@

$(NON_OWNER_TEST): trustcache_nokcall_owner_tests.c \
	$(SRC)/trustcache_nokcall_owner.c \
	$(SRC)/trustcache_nokcall_owner.h \
	$(SRC)/trustcache_nokcall_controller.h \
	$(SRC)/trustcache_nokcall_model.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DTCNO_OWNER_TEST_PROCESS_ID=42 \
		trustcache_nokcall_owner_tests.c \
		$(SRC)/trustcache_nokcall_owner.c \
		$(LDFLAGS) -o $@

test: $(TEST) $(NON_OWNER_TEST)
	$(TEST) gate
	$(TEST) no-carrier
	$(TEST) create-failure
	$(TEST) operation-errors
	$(TEST) retry-recovery
	$(TEST) lifecycle
	$(NON_OWNER_TEST) non-owner

clean:
	rm -rf $(BUILD)
