# Builds a floppy image of this project's files and launches Snow with
# it attached, ready to open in Symantec C++.
#
# All the actual work -- discovering which files to include, bridging
# real resource forks through MacBinary, stamping type/creator -- lives
# in tools/mac-forks/build-floppy.sh, driven by the same git-attribute
# discovery mac-forks already uses elsewhere. Nothing here is
# project-specific except where Snow lives and which workspace to boot.
#
# Snow's floppy image support (--floppy=) doesn't recognize a plain HFS
# image the way real hardware's floppy driver would -- confirmed this
# doesn't boot/mount. What does work: djjr convert to-device turns it
# into a partitioned SCSI-style image (same shape as System71.hda etc.),
# and Snow has no CLI flag to attach an extra SCSI disk at launch either
# -- but that's just an edit to the workspace's own JSON (scsi_targets),
# the same edit Snow itself makes when you attach a disk via its GUI and
# save. tools/snow/attach-disk.py automates that: copies your workspace,
# adds the built disk in the first empty slot, writes the result to
# build/ without touching your own workspace file.
#
# Requires (on top of mac-forks' own requirements): djjr
#   curl -L -o /tmp/djjr.pkg https://diskjockey.onegeekarmy.eu/files/djjr/djjr-2.1.0.pkg && installer -pkg /tmp/djjr.pkg -target CurrentUserHomeDirectory
#   (or: sudo port install djjr)

SNOW_PATH      := $(HOME)/Snow
SNOW           := $(SNOW_PATH)/Snow.app/Contents/MacOS/Snow
SNOW_WORKSPACE ?= $(SNOW_PATH)/iix.snoww   # <-- point this at your own workspace

BUILD_DIR     := build
FLOPPY_IMAGE  := $(BUILD_DIR)/out.img
DEVICE_IMAGE  := $(BUILD_DIR)/out.hda
WORKSPACE     := $(BUILD_DIR)/out.snoww
FLOPPY_BLOCKS := 8192   # 512-byte blocks = 4MB; bump if the project outgrows it
FLOPPY_LABEL  := Build
TEXT_CREATOR  := KAHL   # Symantec/THINK C, so double-click opens source in the IDE

.PHONY: all run clean

all: $(FLOPPY_IMAGE)

$(FLOPPY_IMAGE): tools/mac-forks/import.sh
	sh tools/mac-forks/import.sh
	sh tools/mac-forks/build-floppy.sh $@ $(FLOPPY_BLOCKS) $(FLOPPY_LABEL) $(TEXT_CREATOR)

$(DEVICE_IMAGE): $(FLOPPY_IMAGE)
	djjr convert to-device $(FLOPPY_IMAGE) $@

$(WORKSPACE): $(DEVICE_IMAGE) tools/snow/attach-disk.py
	python3 tools/snow/attach-disk.py $(SNOW_WORKSPACE) $(DEVICE_IMAGE) $@

run: $(WORKSPACE)
	$(SNOW) --fullscreen $(WORKSPACE) &

clean:
	rm -rf $(BUILD_DIR)
