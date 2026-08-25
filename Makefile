# QuitProtect — confirm-before-quit guard for selected apps.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. SPM project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := QuitProtect
BUNDLE_TYPE      := app
PRODUCT_NAME     := QuitProtect.app
BUNDLE_ID        := cc.jorviksoftware.QuitProtect
BUILD_SYSTEM     := spm
SPM_PRODUCT      := QuitProtect

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := QuitProtect.entitlements

include ../jorvik-release/release.mk

# The gesture timing catalog names a Localizable.strings key per option, and nothing in
# the type system ties the two together. Check both directions before the build, so a new
# timing option cannot ship rendering its derived fallback label in every language.
# `release.mk` owns the `build` recipe; this rule only adds a prerequisite to it.
build: check-localisation

.PHONY: check-localisation
check-localisation:
	@tools/check-localisation.sh
