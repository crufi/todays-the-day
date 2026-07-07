# Builds a floppy image of this project's files and launches Snow with
# it attached, ready to open in Symantec C++.
#
# All the actual work -- discovering which files to include, bridging
# real resource forks through MacBinary, stamping type/creator -- lives
# in tools/mac-forks/build-floppy.sh, driven by the same git-attribute
# discovery mac-forks already uses elsewhere. Nothing here is
# project-specific except where Snow lives and which workspace to boot.

SNOW_PATH      := $(HOME)/Snow
SNOW           := $(SNOW_PATH)/Snow.app/Contents/MacOS/Snow
SNOW_WORKSPACE ?= $(SNOW_PATH)/System71.snoww   # <-- point this at your own workspace

BUILD_DIR     := build
FLOPPY_IMAGE  := $(BUILD_DIR)/todays-the-day.img
FLOPPY_BLOCKS := 8192   # 512-byte blocks = 4MB; bump if the project outgrows it
FLOPPY_LABEL  := TodaysTheDay
TEXT_CREATOR  := KAHL   # Symantec/THINK C, so double-click opens source in the IDE

.PHONY: all run clean

all: $(FLOPPY_IMAGE)

$(FLOPPY_IMAGE): tools/mac-forks/import.sh
	sh tools/mac-forks/import.sh
	sh tools/mac-forks/build-floppy.sh $@ $(FLOPPY_BLOCKS) $(FLOPPY_LABEL) $(TEXT_CREATOR)

run: $(FLOPPY_IMAGE)
	$(SNOW) --fullscreen --floppy=$(FLOPPY_IMAGE) $(SNOW_WORKSPACE)

clean:
	rm -f $(FLOPPY_IMAGE)
