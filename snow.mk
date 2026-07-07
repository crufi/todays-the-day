# Generic build/run rules for launching a mac-forks project's source
# in the Snow emulator. Include this from your own project's Makefile:
#
#   SNOW_WORKSPACE ?= $(HOME)/Snow/your-workspace.snoww   # required, no default
#   TEXT_CREATOR   := KAHL                                 # required, no default -- your toolchain's creator code
#   # SNOW_PATH, VOLUME_BLOCKS, VOLUME_LABEL, BUILD_DIR all optional, see below
#
#   include tools/mac-forks/snow.mk
#
# Requires (on top of mac-forks' own requirements): djjr
#   curl -L -o /tmp/djjr.pkg https://diskjockey.onegeekarmy.eu/files/djjr/djjr-2.1.0.pkg && installer -pkg /tmp/djjr.pkg -target CurrentUserHomeDirectory
#   (or: sudo port install djjr)
#
# build-floppy.sh's native output is a plain HFS image in floppy
# format -- a real, valid floppy image, just one Snow's own --floppy
# doesn't recognize (confirmed: doesn't boot/mount). So it's only an
# intermediate step here: djjr converts it into a partitioned
# SCSI-style device image (same shape as a real hard disk image),
# which gets attached via the workspace's own scsi_targets JSON --
# the same edit Snow itself makes when you attach a disk through the
# GUI and save, just automated (snow-attach-disk.py) so it can happen
# from the command line.
#
# The generated workspace has to live in SNOW_PATH itself, not this
# project's BUILD_DIR -- confirmed ("Failed to load workspace: No
# such file or directory"): the template's OTHER entries (ROM, PRAM,
# other disks) are typically bare relative filenames, and Snow
# resolves those relative to wherever the workspace file itself sits.
# Moving the file out of SNOW_PATH breaks every one of those; only
# the newly added disk gets (and needs) an absolute path, since it
# genuinely lives elsewhere.

SNOW_PATH     ?= $(HOME)/Snow
SNOW          := $(SNOW_PATH)/Snow.app/Contents/MacOS/Snow
BUILD_DIR     ?= build
VOLUME_BLOCKS ?= 8192   # 512-byte blocks = 4MB; bump if the project outgrows it
VOLUME_LABEL  ?= Source

HFS_IMAGE    := $(BUILD_DIR)/source.img     # plain HFS, floppy format -- build-floppy.sh's native output
DEVICE_IMAGE := $(BUILD_DIR)/source.hda     # same content, converted to a SCSI-attachable device

# Named after the including project's own directory, so multiple
# projects using this fragment don't collide writing into SNOW_PATH.
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
