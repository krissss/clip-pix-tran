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
XCODEBUILD_SIGNING_FLAGS := CODE_SIGN_STYLE="$(CODE_SIGN_STYLE)" CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)"

ZIP := $(APP_NAME)-$(TAG).zip
DMG := $(APP_NAME)-$(TAG).dmg
DMG_STAGING := .build/$(APP_NAME)-dmg-staging

.PHONY: all app build resolve-packages test package zip dmg clean run run-dev print-sparkle-sign-update print-sparkle-generate-keys

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

print-sparkle-sign-update:
	@test -x "$(SPARKLE_SIGN_UPDATE)"
	@printf '%s\n' "$(SPARKLE_SIGN_UPDATE)"

print-sparkle-generate-keys:
	@test -x "$(SPARKLE_GENERATE_KEYS)"
	@printf '%s\n' "$(SPARKLE_GENERATE_KEYS)"

clean:
	rm -rf "$(APP_BUNDLE)"
	rm -rf "$(DERIVED_DATA)"
	rm -rf "$(TEST_DERIVED_DATA)"
	rm -rf "$(DMG_STAGING)"
	rm -f "$(ZIP)" "$(DMG)"
