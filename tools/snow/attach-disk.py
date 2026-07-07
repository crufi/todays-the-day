#!/usr/bin/env python3
"""Copy a Snow workspace (.snoww), adding one disk image as an
additional SCSI target in the first empty ("None") slot.

Snow's CLI (as of this writing) can only attach media at launch via
--floppy; there's no equivalent flag for a SCSI/HDD-style device
image. Snow's own attach-a-disk-in-the-GUI-and-save-workspace flow
does exactly this same edit to the .snoww JSON, so this just automates
that, non-interactively.

The template's own file paths (ROM, PRAM, existing disks) are stored
relative to the template's own directory. Since the output workspace
gets written somewhere else entirely (this project's build/ dir), this
resolves every path in the copy to absolute, not just the newly added
one -- otherwise the pre-existing entries would silently point at
nonexistent files relative to the new location.

Usage: attach-disk.py <template.snoww> <disk.hda> <output.snoww>
"""
import json
import sys
from pathlib import Path

PATH_FIELDS = ("rom_path", "display_card_rom_path", "pram_path", "extension_rom_path")


def resolve(base_dir, value):
    if not value:
        return value
    path = Path(value)
    return str(path) if path.is_absolute() else str((base_dir / path).resolve())


def main():
    if len(sys.argv) != 4:
        sys.exit(f"usage: {sys.argv[0]} <template.snoww> <disk.hda> <output.snoww>")
    template_path, disk_path, output_path = (Path(p) for p in sys.argv[1:4])

    workspace = json.loads(template_path.read_text())
    base_dir = template_path.resolve().parent

    for field in PATH_FIELDS:
        if field in workspace:
            workspace[field] = resolve(base_dir, workspace[field])

    targets = workspace.get("scsi_targets", [])
    for entry in targets:
        if isinstance(entry, dict) and "Disk" in entry:
            entry["Disk"] = resolve(base_dir, entry["Disk"])

    try:
        slot = targets.index("None")
    except ValueError:
        sys.exit(f"error: no empty SCSI slot in {template_path} (all {len(targets)} are in use)")
    targets[slot] = {"Disk": str(disk_path.resolve())}

    output_path.write_text(json.dumps(workspace, indent=2))
    print(f"attached {disk_path} as SCSI target {slot} -> {output_path}")


if __name__ == "__main__":
    main()
