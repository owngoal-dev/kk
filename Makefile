# kk — kwwk built for jailbroken iOS.
#
# Every step is a script under Scripts/ so the GitHub Actions workflow and a
# local checkout run the same code. This Makefile only wires them together and
# owns the one thing that differs between the two packages: the layout.

SHELL := /bin/bash
ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

CONFIG_DIR := $(ROOT_DIR)/Configuration
include $(CONFIG_DIR)/upstream.env

VERSION_FILE    := $(CONFIG_DIR)/version.txt
PACKAGE_VERSION := $(strip $(shell cat "$(VERSION_FILE)" 2>/dev/null))
PACKAGE_ID      ?= wiki.qaq.kk

BUILD_DIR     := $(ROOT_DIR)/build
SRC_DIR       := $(BUILD_DIR)/src
SCRATCH_DIR   := $(BUILD_DIR)/ios-$(KK_ARCH)
BIN_PATH_FILE := $(BUILD_DIR)/bin-path.txt
PKG_DIR       := $(BUILD_DIR)/Packages

SOURCE_PREPARER  := $(ROOT_DIR)/Scripts/prepare-source.sh
IOS_BUILDER      := $(ROOT_DIR)/Scripts/build-ios.sh
DEB_PACKAGER     := $(ROOT_DIR)/Scripts/package-deb.sh
VERSION_APPLIER  := $(ROOT_DIR)/Scripts/apply-version.sh
DEVICE_INSTALLER := $(ROOT_DIR)/Scripts/install-device.sh

# Which bootstrap layout the .deb is for. roothide is relocated into the jbroot
# it picked this boot and its programs resolve unprefixed paths inside it, so
# its paths ship without a prefix; a rootless bootstrap lives at a fixed
# /var/jb that every path in the package has to name. One arm64 binary backs
# both — only the layout and the architecture label differ.
PACKAGE_FLAVOR ?= roothide
ifeq ($(PACKAGE_FLAVOR),roothide)
PACKAGE_PREFIX       :=
PACKAGE_ARCHITECTURE := iphoneos-arm64e
else ifeq ($(PACKAGE_FLAVOR),rootless)
PACKAGE_PREFIX       := /var/jb
PACKAGE_ARCHITECTURE := iphoneos-arm64
else
$(error PACKAGE_FLAVOR must be roothide or rootless, got '$(PACKAGE_FLAVOR)')
endif

DEB_OUTPUT ?= $(PKG_DIR)/$(PACKAGE_ID)_$(PACKAGE_VERSION)_$(PACKAGE_ARCHITECTURE).deb

ifeq ($(PACKAGE_VERSION),)
$(error $(VERSION_FILE) is missing or empty; run make set-version VERSION=x.y.z)
endif

.PHONY: all help print-version print-upstream print-deb-path set-version \
	bump-upstream check source build deb deb-roothide deb-rootless debs \
	checksums install clean

all: debs

help:
	@echo "kk $(PACKAGE_VERSION) — kwwk for jailbroken iOS"
	@echo "upstream: $(KWWK_REPO) @ $(KWWK_REF)"
	@echo "target:   $(KK_ARCH)-apple-ios$(KK_MIN_IOS)"
	@echo
	@echo "  check          Validate the scripts, the config, and the patch set"
	@echo "  source         Fetch kwwk at the pinned ref and apply patches/"
	@echo "  build          Cross-compile $(KWWK_PRODUCT) for iOS"
	@echo "  deb            Package one flavor (PACKAGE_FLAVOR=$(PACKAGE_FLAVOR))"
	@echo "  deb-roothide   Package for roothide (unprefixed, iphoneos-arm64e)"
	@echo "  deb-rootless   Package for rootless (/var/jb, iphoneos-arm64)"
	@echo "  debs           Both packages plus SHA256SUMS — what CI releases"
	@echo "  install        Install onto a device over SSH and smoke-test it"
	@echo "                 (DEVICE_HOST, DEVICE_PORT, DEVICE_USER)"
	@echo "  clean          Remove build/"
	@echo
	@echo "  make set-version VERSION=1.2.3   Set the package version"
	@echo "  make bump-upstream REF=<sha>     Repin upstream and rebuild"

print-version:
	@echo "$(PACKAGE_VERSION)"

print-upstream:
	@echo "$(KWWK_REF)"

print-deb-path:
	@echo "$(DEB_OUTPUT)"

set-version:
	@test -n "$(VERSION)" || { echo "usage: make set-version VERSION=1.2.3" >&2; exit 64; }
	@"$(VERSION_APPLIER)" "$(VERSION)"

check:
	@echo "==> shell syntax"
	@for script in "$(ROOT_DIR)"/Scripts/*.sh; do bash -n "$$script" || exit 1; done
	@if command -v shellcheck >/dev/null; then \
		shellcheck --severity=warning "$(ROOT_DIR)"/Scripts/*.sh; \
	else \
		echo "    (shellcheck not installed; syntax check only)"; \
	fi
	@echo "==> config"
	@[[ "$(PACKAGE_VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$$ ]] || \
		{ echo "error: version '$(PACKAGE_VERSION)' must look like 1.2.3 or 1.2.3-2" >&2; exit 65; }
	@[[ "$(KK_MIN_IOS)" =~ ^[0-9]+\.[0-9]+$$ ]] || \
		{ echo "error: KK_MIN_IOS '$(KK_MIN_IOS)' must look like 15.0" >&2; exit 65; }
	@[[ "$(KWWK_REF)" =~ ^[0-9a-f]{40}$$ ]] || \
		echo "    warning: KWWK_REF is not a full commit sha; builds are not reproducible"
	@echo "==> patch set"
	@ls "$(ROOT_DIR)"/patches/*.patch >/dev/null
	@for patch in "$(ROOT_DIR)"/patches/*.patch; do \
		test -s "$$patch" || { echo "error: $$patch is empty" >&2; exit 65; }; \
	done
	@echo "==> packaging inputs"
	@for input in Packaging/DEBIAN/control Packaging/kk.entitlements Packaging/kk.launcher.sh; do \
		test -f "$(ROOT_DIR)/$$input" || { echo "error: missing $$input" >&2; exit 66; }; \
	done
	@plutil -lint "$(ROOT_DIR)/Packaging/kk.entitlements"
	@echo "ok"

source:
	@"$(SOURCE_PREPARER)" "$(SRC_DIR)"

build: source
	@mkdir -p "$(BUILD_DIR)"
	@"$(IOS_BUILDER)" "$(SRC_DIR)" "$(SCRATCH_DIR)" >"$(BIN_PATH_FILE)"

deb: build
	@mkdir -p "$(PKG_DIR)"
	@PACKAGE_ID="$(PACKAGE_ID)" "$(DEB_PACKAGER)" \
		"$$(cat "$(BIN_PATH_FILE)")" \
		"$(DEB_OUTPUT)" \
		"$(PACKAGE_VERSION)" \
		"$(PACKAGE_ARCHITECTURE)" \
		"$(PACKAGE_PREFIX)"

# Both layouts share the build, so these are the same recipe with the flavor
# switched; the second one finds the build already done.
deb-roothide:
	@$(MAKE) --no-print-directory PACKAGE_FLAVOR=roothide deb

deb-rootless:
	@$(MAKE) --no-print-directory PACKAGE_FLAVOR=rootless deb

debs: deb-roothide deb-rootless checksums

# The digest list is what OwnGoalPackages verifies a downloaded asset against,
# so the names in it have to be the bare asset names the release publishes.
checksums:
	@cd "$(PKG_DIR)" && shasum -a 256 *.deb | tee SHA256SUMS

# Both flavors are built and the directory is handed over, so install-device.sh
# can pick the one the attached device's own package manager reports.
install: debs
	@"$(DEVICE_INSTALLER)" "$(PKG_DIR)"

bump-upstream:
	@test -n "$(REF)" || { echo "usage: make bump-upstream REF=<sha>" >&2; exit 64; }
	@sed -i '' -e "s|^KWWK_REF=.*|KWWK_REF=$(REF)|" "$(CONFIG_DIR)/upstream.env"
	@echo "repinned upstream to $(REF)"
	@$(MAKE) --no-print-directory build

clean:
	rm -rf "$(BUILD_DIR)"
