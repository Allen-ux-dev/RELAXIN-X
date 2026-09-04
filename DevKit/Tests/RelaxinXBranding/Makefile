ROOT := $(abspath ../../..)
OUT := /tmp/relaxin-x-branding-test

.PHONY: test clean

test:
	swiftc \
		"$(ROOT)/Relaxin/Interface/Terminal/TerminalStyle.swift" \
		"$(ROOT)/Relaxin/Interface/Home/HomeView+Credits.swift" \
		"$(ROOT)/DevKit/Tests/RelaxinXBranding/main.swift" \
		-o "$(OUT)"
	"$(OUT)"

clean:
	rm -f "$(OUT)"
