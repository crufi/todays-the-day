# Builds this project's source onto a disk image and launches it in
# Snow, ready to open in Symantec C++. All the actual logic (file
# discovery, MacBinary bridging, the djjr/workspace dance Snow needs)
# lives in tools/mac-forks/snow.mk -- see that file for how it works
# and what else can be overridden here.

SNOW_WORKSPACE ?= $(HOME)/Snow/iix.snoww   # <-- point this at your own workspace
TEXT_CREATOR   := KAHL   # Symantec/THINK C, so double-click opens source in the IDE
VOLUME_LABEL   := Today's the Day   # HFS volume name shown in the emulator

include tools/mac-forks/snow.mk

include tools/mac-forks/release.mk
