#!/bin/sh
# Wires up the mac-forks hooks for THIS clone.
#
# Hooks live in .git/hooks, which git never populates from a clone --
# every clone needs to run this once:
#
#   sh tools/mac-forks/install.sh
#
# Without it, the repo is still completely valid: resource-fork-bearing
# files just stay as their .hqx / .r sidecars, unexpanded, and CR-only
# text files just stay LF-converted. Running this makes the real files
# show up in the working tree as a vintage Mac toolchain expects.
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

# maceol has no forks/races to worry about, so it's a plain git filter
# rather than a hook -- but the filter *driver* still has to be
# configured locally, same reasoning as the machex/macderez filters
# used to need (see this project's git history for why that approach
# was abandoned for resource forks specifically: git's own checkout
# can't be raced safely). Text-only content has no such problem.
git config filter.maceol.clean  "$root/tools/mac-forks/maceol-clean"
git config filter.maceol.smudge "$root/tools/mac-forks/maceol-smudge"
git config filter.maceol.required true

echo "mac-forks hooks + filters installed for $root"

echo "materializing real files from their .hqx/.r sidecars..."
"$root/tools/mac-forks/import.sh"

echo "done."
