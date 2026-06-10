APP_NAME := ClipPixTran
PROJECT := $(APP_NAME).xcodeproj
SCHEME := $(APP_NAME)
CONFIGURATION ?= Release
DERIVED_DATA ?= .build/xcode-app
TEST_DERIVED_DATA ?= .build/xcode-test
BUILT_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
APP_BUNDLE := $(APP_NAME).app
SPARKLE_SIGN_UPDATE := $(DERIVED_DATA)/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
SPARKLE_GENERATE_KEYS := $(DERIVED_DATA)/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys

VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
VERSION := $(or $(VERSION),1.0)
TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null)
TAG := $(or $(TAG),v$(VERSION))
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null)
BUILD_NUMBER := $(or $(BUILD_NUMBER),1)

CODE_SIGN_STYLE ?= Manual
CODE_SIGN_IDENTITY ?= -
DEVELOPMENT_TEAM ?=
XCODEBUILD_SIGNING_FLAGS := CODE_SIGN_STYLE="$(CODE_SIGN_STYLE)" CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" $(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)",)

LOCAL_DEVELOPMENT_TEAM := $(shell awk -F= '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/{gsub(/[[:space:]]/,"",$$2); print $$2; exit}' Config/Signing.local.xcconfig 2>/dev/null)
SIGNED_DERIVED_DATA ?= .build/xcode-signed
SIGNED_CODE_SIGN_STYLE ?= Manual
SIGNED_CODE_SIGN_IDENTITY ?= Apple Development
SIGNED_DEVELOPMENT_TEAM ?= $(LOCAL_DEVELOPMENT_TEAM)
SIGNED_REQUIRED_AUTHORITY ?= Apple Development

ZIP := $(APP_NAME)-$(TAG).zip
DMG := $(APP_NAME)-$(TAG).dmg
DMG_STAGING := .build/$(APP_NAME)-dmg-staging

.PHONY: all app build resolve-packages test package zip dmg signed-package package-signed signed-zip signed-dmg signed-app run-signed verify-signed-app require-signed-signing clean run run-dev print-sparkle-sign-update print-sparkle-generate-keys

all: app

app: build
	@rm -rf "$(APP_BUNDLE)"
	@ditto "$(BUILT_APP)" "$(APP_BUNDLE)"
	@codesign --verify --deep --strict --verbose=1 "$(APP_BUNDLE)"
	@echo "$(APP_BUNDLE)"

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-destination 'platform=macOS,arch=arm64' \
		MARKETING_VERSION="$(VERSION)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		$(XCODEBUILD_SIGNING_FLAGS) \
		build

resolve-packages:
	xcodebuild \
		-resolvePackageDependencies \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)"

test:
	xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-destination 'platform=macOS' \
		$(XCODEBUILD_SIGNING_FLAGS)

package: zip dmg

zip: app
	@rm -f "$(ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	@echo "$(ZIP)"

dmg: app
	@rm -rf "$(DMG_STAGING)"
	@mkdir -p "$(DMG_STAGING)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGING)/$(APP_BUNDLE)"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG)"
	@rm -rf "$(DMG_STAGING)"
	@echo "$(DMG)"

run: app
	open -n "$(APP_BUNDLE)"

run-dev:
	$(MAKE) run CONFIGURATION=Debug

signed-package: signed-zip signed-dmg

package-signed: signed-package

signed-app: require-signed-signing
	$(MAKE) app \
		CONFIGURATION=Release \
		DERIVED_DATA="$(SIGNED_DERIVED_DATA)" \
		CODE_SIGN_STYLE="$(SIGNED_CODE_SIGN_STYLE)" \
		CODE_SIGN_IDENTITY="$(SIGNED_CODE_SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(SIGNED_DEVELOPMENT_TEAM)"
	$(MAKE) verify-signed-app

signed-zip: signed-app
	@rm -f "$(ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	@echo "$(ZIP)"

signed-dmg: signed-app
	@rm -rf "$(DMG_STAGING)"
	@mkdir -p "$(DMG_STAGING)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGING)/$(APP_BUNDLE)"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG)"
	@rm -rf "$(DMG_STAGING)"
	@echo "$(DMG)"

run-signed: signed-app
	open -n "$(APP_BUNDLE)"

verify-signed-app:
	@codesign --verify --deep --strict --verbose=1 "$(APP_BUNDLE)"
	@SIGN_INFO="$$(codesign -dv --verbose=4 "$(APP_BUNDLE)" 2>&1)"; \
		printf '%s\n' "$$SIGN_INFO" | grep -E "Authority=|TeamIdentifier="; \
		if printf '%s\n' "$$SIGN_INFO" | grep -q "TeamIdentifier=not set"; then \
			echo "Code signature has no TeamIdentifier. Check SIGNED_CODE_SIGN_IDENTITY and SIGNED_DEVELOPMENT_TEAM."; \
			exit 1; \
		fi; \
		printf '%s\n' "$$SIGN_INFO" | grep -F -q "Authority=$(SIGNED_REQUIRED_AUTHORITY)" || (echo "Expected Authority=$(SIGNED_REQUIRED_AUTHORITY)"; exit 1); \
		printf '%s\n' "$$SIGN_INFO" | grep -F -q "TeamIdentifier=$(SIGNED_DEVELOPMENT_TEAM)" || (echo "Expected TeamIdentifier=$(SIGNED_DEVELOPMENT_TEAM)"; exit 1)

require-signed-signing:
	@test -n "$(SIGNED_DEVELOPMENT_TEAM)" || (echo "Set SIGNED_DEVELOPMENT_TEAM=YOUR_TEAM_ID or create Config/Signing.local.xcconfig"; exit 1)
	@security find-identity -v -p codesigning | grep -F -q "$(SIGNED_CODE_SIGN_IDENTITY)" || (echo "No $(SIGNED_CODE_SIGN_IDENTITY) signing identity found in the login keychain"; exit 1)

print-sparkle-sign-update:
	@test -x "$(SPARKLE_SIGN_UPDATE)"
	@printf '%s\n' "$(SPARKLE_SIGN_UPDATE)"

print-sparkle-generate-keys:
	@test -x "$(SPARKLE_GENERATE_KEYS)"
	@printf '%s\n' "$(SPARKLE_GENERATE_KEYS)"

clean:
	rm -rf "$(APP_BUNDLE)"
	rm -rf "$(DERIVED_DATA)"
	rm -rf "$(SIGNED_DERIVED_DATA)"
	rm -rf "$(TEST_DERIVED_DATA)"
	rm -rf "$(DMG_STAGING)"
	rm -f "$(ZIP)" "$(DMG)"
