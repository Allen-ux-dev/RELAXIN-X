ifndef MIN_IOS_VERSION
$(error MIN_IOS_VERSION must be supplied by the project build)
endif
export MIN_IOS_VERSION
ifndef SIGNATURE_VERIFIER_SOURCE
$(error SIGNATURE_VERIFIER_SOURCE must be supplied by the project build)
endif
export SIGNATURE_VERIFIER_SOURCE
export PATH := $(dir $(shell xcrun --find clang)):$(PATH)

all:
	@$(MAKE) -C libkrw-provider package
	@$(MAKE) -C libroot package
	@$(MAKE) -C basebin-link package

clean:
	@$(MAKE) -C libkrw-provider clean
	@$(MAKE) -C libroot clean
	@$(MAKE) -C basebin-link clean

.PHONY: all clean
