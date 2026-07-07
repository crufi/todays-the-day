#!/usr/bin/env python3
"""Copy a Snow workspace (.snoww), adding one disk image as an
additional SCSI target in the first empty ("None") slot.

Snow's CLI (as of this writing) can only attach media at launch via
--floppy; there's no equivalent flag for a SCSI/HDD-style device
image. Snow's own attach-a-disk-in-the-GUI-and-save-workspace flow
does exactly this same edit to the .snoww JSON, so this just automates
that, non-interactively.

Touches ONLY the new disk's path -- every other field (ROM, PRAM,
existing disks) is left exactly as the template has it. An earlier
version of this script resolved every path in the workspace to
absolute, on the theory that the template's own relative paths
wouldn't survive being copied to a different directory; that broke
Snow (confirmed). Whatever Snow resolves those relative paths against
isn't "the workspace file's own directory" the way this assumed -- so
leave them alone and only touch what's actually new.

Usage: attach-disk.py <template.snoww> <disk.hda> <output.snoww>
"""
import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 4:
        sys.exit(f"usage: {sys.argv[0]} <template.snoww> <disk.hda> <output.snoww>")
    template_path, disk_path, output_path = (Path(p) for p in sys.argv[1:4])

    workspace = json.loads(template_path.read_text())
    targets = workspace.get("scsi_targets", [])

    try:
        slot = targets.index("None")
    except ValueError:
        sys.exit(f"error: no empty SCSI slot in {template_path} (all {len(targets)} are in use)")
    targets[slot] = {"Disk": str(disk_path.resolve())}

    output_path.write_text(json.dumps(workspace, indent=2))
    print(f"attached {disk_path} as SCSI target {slot} -> {output_path}")


if __name__ == "__main__":
    main()
