# Generic "package a release" rule for any mac-forks project. Builds
# a versioned zip containing the project's source disk image -- not a
# compiled binary, since compiling happens by hand inside whatever
# vintage IDE, not something this can automate.
#
#   include tools/mac-forks/release.mk
#
# Then: make release VERSION=v1.2.0
# (VERSION defaults to `git describe` if you don't set it -- falls
# back to the commit hash if the repo has no tags yet)
#
# Tagging the commit is a deliberately separate, plain-git step, not
# folded into this target -- "build an artifact" and "declare this
# commit a release" are different actions, and the latter mutates
# shared repo state (and, if pushed, is visible to others), which
# isn't something a `make` target should do as a side effect. Something
# like:
#   git tag -a v1.2.0 -m "..." && git push origin v1.2.0

include tools/mac-forks/image.mk

VERSION      ?= $(shell git describe --tags --always --dirty)
RELEASE_DIR  ?= dist
RELEASE_NAME := $(notdir $(CURDIR))-$(VERSION)
RELEASE_ZIP  := $(RELEASE_DIR)/$(RELEASE_NAME).zip

.PHONY: release release-clean

release: $(RELEASE_ZIP)

$(RELEASE_ZIP): $(HFS_IMAGE)
	@mkdir -p $(RELEASE_DIR)
	rm -f $@ $(RELEASE_DIR)/$(RELEASE_NAME).img
	cp $(HFS_IMAGE) $(RELEASE_DIR)/$(RELEASE_NAME).img
	cd $(RELEASE_DIR) && zip $(RELEASE_NAME).zip $(RELEASE_NAME).img
	rm -f $(RELEASE_DIR)/$(RELEASE_NAME).img

release-clean:
	rm -rf $(RELEASE_DIR)
