#!/bin/sh
# Wires up the mac-forks hooks for THIS clone.
#
# Hooks live in .git/hooks, which git never populates from a clone --
# every clone needs to run this once:
#
#   sh tools/mac-forks/install.sh
#
# Without it, the repo is still completely valid: TodaysTheDay.π /
# .rsrc-style files just stay as their .hqx / .r sidecars, unexpanded.
# Running this makes the real files show up in the working tree.
#
# Requires macOS with the Xcode Command Line Tools installed (for
# /usr/bin/binhex, /usr/bin/DeRez, /usr/bin/Rez, /usr/bin/SetFile).
set -eu

root=$(git rev-parse --show-toplevel)

for tool in /usr/bin/binhex /usr/bin/DeRez /usr/bin/Rez /usr/bin/SetFile; do
    if [ ! -x "$tool" ]; then
        echo "install.sh: missing $tool -- install the Xcode Command Line Tools (xcode-select --install)" >&2
        exit 1
    fi
done

mkdir -p "$root/.git/hooks"
for hook in pre-commit post-checkout post-merge; do
    ln -sf "../../tools/mac-forks/hooks/$hook" "$root/.git/hooks/$hook"
done

echo "mac-forks hooks installed for $root"

echo "materializing real files from their .hqx/.r sidecars..."
"$root/tools/mac-forks/import.sh"

echo "done."
