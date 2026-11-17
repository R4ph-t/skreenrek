# Targets the factory may run (MAKE_TARGETS in .factory/project.conf).
# Offline config lint, then `swift build` and `swift test` once Package.swift exists.
# Tests that need Screen Recording or Accessibility stay manual (Raph's Mac).
.PHONY: check

check:
	bash scripts/factory-check.sh
	@if [ -f Package.swift ]; then \
		swift build && swift test; \
	else \
		echo "make check: no Package.swift yet, skipping swift build/test"; \
	fi
