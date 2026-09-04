ROOT := $(abspath ../../..)
OUTPUT ?= $(ROOT)/build/UpstreamBaseline/inspection
RELEASE ?=

.PHONY: inspect
inspect:
	@test -n "$(RELEASE)" || (echo 'usage: make inspect RELEASE=/path/to/Relaxin.ipa [OUTPUT=...]' >&2; exit 2)
	python3 inspect-upstream-release.py "$(RELEASE)" --output "$(OUTPUT)"
