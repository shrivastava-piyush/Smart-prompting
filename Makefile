# Smart Prompting — build targets.
# All targets are free to run; no paid Apple Developer account required.

SHELL := /bin/bash
BUILD_DIR := build
DEVELOPMENT_TEAM ?=

.PHONY: all cli mac ios release test clean install-cli install-launchd refresh-ios doctor

all: cli

cli:
	@bash scripts/build-cli.sh

mac:
	@bash scripts/build-mac-app.sh

ios:
	@bash scripts/build-ios-ipa.sh

release: cli mac ios
	@echo "Artifacts in $(BUILD_DIR)/"

test:
	swift test

clean:
	rm -rf $(BUILD_DIR) .build

install-cli: cli
	sudo install -m 0755 $(BUILD_DIR)/sp /usr/local/bin/sp
	@echo "Installed /usr/local/bin/sp"

install-launchd:
	@bash scripts/install-launchd.sh

refresh-ios:
	@xcodebuild -scheme SmartPromptingiOS \
		-destination 'generic/platform=iOS' \
		-allowProvisioningUpdates \
		build

doctor: install-cli
	sp doctor
