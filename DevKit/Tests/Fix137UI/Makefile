ROOT := $(abspath ../../..)
OUT := /tmp/relaxin-fix137-ui-test

.PHONY: test clean

test:
	swiftc \
		"$(ROOT)/Relaxin/Interface/Terminal/TerminalStyle.swift" \
		"$(ROOT)/Relaxin/Interface/Home/HomeView+Credits.swift" \
		"$(ROOT)/DevKit/Tests/Fix137UI/main.swift" \
		-o "$(OUT)"
	"$(OUT)"

clean:
	rm -f "$(OUT)"
