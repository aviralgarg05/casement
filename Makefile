# Casement: builds with the Xcode Command Line Tools alone.
# swift-testing's macros need the plugin path spelled out when the Command Line Tools are the
# selected toolchain; with Xcode selected they are found without it. Deriving the path from
# `xcode-select -p` and adding it only when it is there means one command works either way, so
# what you run locally is what CI runs.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
SWIFT_TEST_FLAGS = $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS),)

.PHONY: build app run demo test e2e e2e-media perf snapshots motion-snapshots settings-snapshots check install release clean

build:            ## Debug build of the app and CLI
	swift build

app:              ## Release Casement.app in build/ (ad-hoc signed)
	scripts/bundle.sh

run: app          ## Build and launch Casement.app
	open build/Casement.app

demo:             ## Launch with demo content (debug build)
	swift build --product Casement && .build/debug/Casement --demo

# The results go to a file as well as the console, because the console is not a reliable record
# of which test failed. Tests run concurrently and all of them report through one stdout, which
# is block-buffered when it is a pipe rather than a terminal, and writes can land on top of one
# another: run 38280213005 lost about a hundred event lines, among them the three that named
# the one test that failed, and left a line reading "Suite MoveToApplicati" with
# another test's line spliced into it. The test process writes this file itself, one record per
# test, so a failure is still named when the log has lost it. git ignores build/ already.
#
# The directory is made first because swift test does not make it: given a path in a folder that
# is not there it runs the whole suite, then fails at the end with "No such file or directory"
# and exit 2. Locally build/ is usually left over from an earlier `make app` and the mistake is
# invisible; on a fresh checkout, which is what CI does, every run fails however green the tests
# were. That is run 38459963550.
test:             ## Unit + system tests (swift-testing); results in build/test-results.xml
	@mkdir -p build
	swift test $(SWIFT_TEST_FLAGS) --xunit-output build/test-results.xml

e2e: app          ## End-to-end tests against the real app (isolated config, own port)
	python3 Tests/E2E/e2e.py

e2e-media: app    ## …plus the MediaRemote bridge test (skips itself if something is playing)
	CASEMENT_E2E_MEDIA=1 python3 Tests/E2E/e2e.py

perf: app         ## CPU per island state against the performance budget
	scripts/perf.sh

snapshots:        ## Render every island state to build/snapshots/*.png
	swift build --product Casement && .build/debug/Casement --snapshot build/snapshots

motion-snapshots: ## Render each island transition as a contact sheet to build/motion-snapshots/*.png
	swift build --product Casement && .build/debug/Casement --snapshot-motion build/motion-snapshots

settings-snapshots: ## Render every Settings page, light and dark, to build/settings-snapshots/*.png
	swift build --product Casement && .build/debug/Casement --settings-snapshot build/settings-snapshots

check: test e2e perf  ## Everything

# The printed command has to survive make before it reaches the shell. An earlier revision wrote
# `$(brew --prefix …)`, which make reads as one of its own variables, named `brew --prefix …`; it
# is undefined, so make substituted the empty string and the line printed `/bin/casementctl`.
# `/bin` is SIP-protected, so that command fails even under sudo. `$$(…)` is what reaches the
# shell. The directory is worked out the same way README.md does it: Homebrew's prefix when there
# is one, `~/.local` otherwise, never `/usr/local`, which is owned by root on macOS.
install: app      ## Copy to /Applications and link the CLI (asks nothing; review first)
	rm -rf /Applications/Casement.app && cp -R build/Casement.app /Applications/
	@BIN="$$(brew --prefix 2>/dev/null || echo "$$HOME/.local")/bin"; \
	echo "CLI: mkdir -p \"$$BIN\" && ln -sf /Applications/Casement.app/Contents/MacOS/casementctl \"$$BIN/casementctl\""

release:          ## Zip, checksum and notes for the newest CHANGELOG version (PUBLISH=1 creates the GitHub release)
	scripts/release.sh $(if $(PUBLISH),--publish,)

clean:
	rm -rf .build build
