# `make check` is the only target the factory runs (MAKE_TARGETS in .factory/project.conf): an offline config lint,
# an Info.plist lint, then, once Package.swift exists, `swift build`, `swift test`, and a debug Skreenrek.app bundled
# into .build/app-check/ whose `skreenrek --version` must run, so a PR that breaks bundling turns CI red.
# Tests that need Screen Recording or Accessibility stay manual (Raph's Mac).
#
# `make app` builds the release Skreenrek.app into build/, ad-hoc signed. `make perf` is manual and never part of
# `check`. `make release VERSION=x.y.z` is Raph's: it Developer ID signs, notarizes and staples the app and writes
# dist/Skreenrek-x.y.z.zip plus its sha256 (scripts/release.sh). It never tags or publishes.
.PHONY: check app perf release

PERF_APP ?= Safari

check:
	bash scripts/factory-check.sh
	plutil -lint packaging/Info.plist
	@if [ -f Package.swift ]; then \
		set -e; \
		swift build; \
		swift test; \
		app=$$(bash scripts/bundle-app.sh "$$(swift build --show-bin-path)" .build/app-check); \
		version=$$(sed -nE 's/.*static let current = "([^"]+)".*/\1/p' Sources/SkreenrekCore/SkreenrekVersion.swift | head -n1); \
		out=$$("$$app/Contents/MacOS/skreenrek" --version); \
		echo "$$out"; \
		case "$$out" in *"$$version"*) ;; *) echo "make check: bundled --version printed '$$out', expected $$version" >&2; exit 1 ;; esac; \
	else \
		echo "make check: no Package.swift yet, skipping swift build/test and the app bundle"; \
	fi

app:
	swift build -c release --product skreenrek
	bash scripts/bundle-app.sh .build/release build

perf: app
	build/Skreenrek.app/Contents/MacOS/skreenrek debug perf --app "$(PERF_APP)"

release:
	@[ -n "$(VERSION)" ] || { echo "usage: make release VERSION=x.y.z" >&2; exit 1; }
	bash scripts/release.sh "$(VERSION)"
