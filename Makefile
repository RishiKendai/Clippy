# Clippy: build, run and package.
#   make dev      build a debug Clippy.app and run it in the foreground (logs in this terminal, Ctrl-C quits)
#   make build    universal release Clippy.app + dist/Clippy.dmg to share
#   make install  build release and copy Clippy.app to /Applications
#   make test     run unit tests
#   make clean    remove build output (build/, .build/, dist/)
#   make signing-cert  one-time: create the local "Clippy Dev" signing identity (keeps Accessibility across rebuilds)

VERSION      ?= 1.0
BUILD_NUMBER ?= 1
export VERSION BUILD_NUMBER

DEV_APP     := build/debug/Clippy.app
RELEASE_APP := build/release/Clippy.app
DMG         := dist/Clippy.dmg

.PHONY: dev build app dmg install test icon clean signing-cert

dev:
	@scripts/dev.sh

build: app dmg

app:
	@scripts/build-app.sh release

dmg:
	@scripts/make-dmg.sh

install: app
	@pkill -x Clippy 2>/dev/null || true
	@rm -rf /Applications/Clippy.app
	@cp -R $(RELEASE_APP) /Applications/Clippy.app
	@echo "==> installed /Applications/Clippy.app"
	@open /Applications/Clippy.app

# swift-testing's macro plugin lives in a subfolder the Command Line Tools don't always search.
TESTING_PLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
TEST_FLAGS      := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

test:
	@swift test $(TEST_FLAGS)

signing-cert:
	@scripts/create-signing-identity.sh

icon:
	@swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	@rm -rf build .build dist
