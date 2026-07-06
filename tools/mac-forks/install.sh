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

# Filter config only affects *future* checkouts. If this clone was
# checked out before maceol was configured, its filtered files are
# still sitting there un-smudged (LF instead of CR). A plain
# `git checkout HEAD -- .` doesn't fix this: git compares the
# clean-filtered worktree content against the stored blob first, and
# since an LF-only file cleans to itself (tr '\r' '\n' is a no-op on
# text with no CR), git thinks nothing changed and skips re-invoking
# smudge entirely. So instead, delete and re-checkout specifically the
# files maceol applies to -- with nothing on disk, git has no "already
# matches" shortcut to take, and smudge is forced to actually run.
maceol_paths=$(mktemp)
trap 'rm -f "$maceol_paths"' EXIT
git -C "$root" ls-files | while IFS= read -r f; do
    attr=$(git -C "$root" check-attr filter -- "$f" | awk -F': ' '{print $NF}')
    if [ "$attr" = maceol ]; then
        printf '%s\n' "$f"
    fi
    true
done >"$maceol_paths"
if [ -s "$maceol_paths" ]; then
    while IFS= read -r f; do
        rm -f "$root/$f"
    done <"$maceol_paths"
    xargs git -C "$root" checkout HEAD -- <"$maceol_paths"
fi

echo "materializing real files from their .hqx/.r sidecars..."
"$root/tools/mac-forks/import.sh"

echo "done."
