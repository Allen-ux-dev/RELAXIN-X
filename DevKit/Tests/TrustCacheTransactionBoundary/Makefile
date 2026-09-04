ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Tests/TrustCacheTransactionBoundary
TEST := $(BUILD)/trustcache_transaction_tests
CLANG ?= clang

.PHONY: all test clean
all: $(TEST)

$(TEST): trustcache_transaction_tests.m $(ROOT)/RelaxinEngine/Stages/Bootstrap/RLXTrustCacheTransaction.m
	@mkdir -p $(BUILD)
	$(CLANG) -x objective-c -std=gnu11 -Wall -Wextra -Werror \
		-I$(ROOT)/RelaxinEngine/Stages/Bootstrap \
		trustcache_transaction_tests.m \
		$(ROOT)/RelaxinEngine/Stages/Bootstrap/RLXTrustCacheTransaction.m \
		-o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD)
