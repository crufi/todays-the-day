# Builds this project's source onto a disk image and launches Snow
# with it attached as an extra SCSI disk, ready to open in Symantec
# C++.
#
# All the actual work -- discovering which files to include, bridging
# real resource forks through MacBinary, stamping type/creator -- lives
# in tools/mac-forks/build-floppy.sh, driven by the same git-attribute
# discovery mac-forks already uses elsewhere. Nothing here is
# project-specific except where Snow lives and which workspace to boot.
#
# build-floppy.sh's native output is a plain HFS image in floppy
# format -- a real, valid floppy image, just one Snow's own --floppy
# doesn't recognize (confirmed: doesn't boot/mount). So it's only an
# intermediate step here: djjr converts it into a partitioned
# SCSI-style device image (same shape as System71.hda etc.), which
# gets attached via the workspace's own scsi_targets JSON -- the same
# edit Snow itself makes when you attach a disk through the GUI and
# save, just automated (tools/mac-forks/snow-attach-disk.py) so it
# can happen from the command line.
#
# The generated workspace has to live in $(SNOW_PATH), not this
# project's build/ -- confirmed ("Failed to load workspace: No such
# file or directory"): the template's OTHER entries (ROM, PRAM,
# disk1-3.hda) are bare relative filenames, and Snow resolves those
# relative to wherever the workspace file itself sits. Moving the file
# out of $(SNOW_PATH) breaks every one of those; only the newly added
# disk gets (and needs) an absolute path, since it genuinely lives
# elsewhere. It's a small generated glue file, not a copy of anything
# real -- same idea as iix.snoww/Mac IIx.snoww already sitting there.
#
# Requires (on top of mac-forks' own requirements): djjr
#   curl -L -o /tmp/djjr.pkg https://diskjockey.onegeekarmy.eu/files/djjr/djjr-2.1.0.pkg && installer -pkg /tmp/djjr.pkg -target CurrentUserHomeDirectory
#   (or: sudo port install djjr)

SNOW_PATH      := $(HOME)/Snow
SNOW           := $(SNOW_PATH)/Snow.app/Contents/MacOS/Snow
SNOW_WORKSPACE ?= $(SNOW_PATH)/iix.snoww   # <-- point this at your own workspace

BUILD_DIR     := build
HFS_IMAGE     := $(BUILD_DIR)/source.img     # plain HFS, floppy format -- build-floppy.sh's native output
DEVICE_IMAGE  := $(BUILD_DIR)/source.hda     # same content, converted to a SCSI-attachable device
VOLUME_BLOCKS := 8192   # 512-byte blocks = 4MB; bump if the project outgrows it
VOLUME_LABEL  := Source
TEXT_CREATOR  := KAHL   # Symantec/THINK C, so double-click opens source in the IDE

# Must live in $(SNOW_PATH) itself, not build/ -- see the note above.
# Named after this directory so it can't collide with another
# project's generated workspace if this Makefile gets reused elsewhere.
WORKSPACE := $(SNOW_PATH)/$(notdir $(CURDIR)).snoww

.PHONY: all run clean

all: $(HFS_IMAGE)

$(HFS_IMAGE): tools/mac-forks/import.sh
	sh tools/mac-forks/import.sh
	sh tools/mac-forks/build-floppy.sh $@ $(VOLUME_BLOCKS) $(VOLUME_LABEL) $(TEXT_CREATOR)

$(DEVICE_IMAGE): $(HFS_IMAGE)
	djjr convert to-device $(HFS_IMAGE) $@

$(WORKSPACE): $(DEVICE_IMAGE) tools/mac-forks/snow-attach-disk.py
	python3 tools/mac-forks/snow-attach-disk.py $(SNOW_WORKSPACE) $(DEVICE_IMAGE) $@

run: $(WORKSPACE)
	$(SNOW) --fullscreen $(WORKSPACE) &

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(WORKSPACE)
