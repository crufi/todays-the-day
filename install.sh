#!/bin/sh
# Wires up the mac-forks hooks for THIS clone.
#
# Hooks live in .git/hooks, which git never populates from a clone --
# every clone needs to run this once:
#
#   sh tools/mac-forks/install.sh
#
# Without it, the repo is still completely valid: resource-fork-bearing
# files just stay as their .hqx / .r sidecars, unexpanded, and classic
# Mac text files just stay in their UTF-8/LF form. Running this makes
# the real files show up in the working tree as a vintage Mac
# toolchain expects.
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

# mactext has no forks/races to worry about, so it's a plain git
# filter rather than a hook -- but the filter *driver* still has to be
# configured locally, same reasoning as the machex/macderez filters
# used to need (see this project's git history for why that approach
# was abandoned for resource forks specifically: git's own checkout
# can't be raced safely). Text-only content has no such problem.
git config filter.mactext.clean  "$root/tools/mac-forks/mactext-clean"
git config filter.mactext.smudge "$root/tools/mac-forks/mactext-smudge"
git config filter.mactext.required true

echo "mac-forks hooks + filters installed for $root"

# Filter config only affects *future* checkouts. If this clone was
# checked out before mactext was configured, its filtered files are
# still sitting there un-smudged (UTF-8/LF instead of Mac Roman/CR). A
# plain `git checkout HEAD -- .` doesn't fix this: git compares the
# clean-filtered worktree content against the stored blob first, and
# since an already-clean file cleans to itself, git thinks nothing
# changed and skips re-invoking smudge entirely. So instead, delete
# and re-checkout specifically the files mactext applies to -- with
# nothing on disk, git has no "already matches" shortcut to take, and
# smudge is forced to actually run.
mactext_paths=$(mktemp)
trap 'rm -f "$mactext_paths"' EXIT
git -C "$root" ls-files | while IFS= read -r f; do
    attr=$(git -C "$root" check-attr filter -- "$f" | awk -F': ' '{print $NF}')
    if [ "$attr" = mactext ]; then
        printf '%s\n' "$f"
    fi
    true
done >"$mactext_paths"
if [ -s "$mactext_paths" ]; then
    # mactext-smudge can't announce itself the way import.sh's binhex/
    # derez conversions do -- its stdout as a git filter *is* the file
    # content git writes, so printing a status line there would
    # corrupt the file. This is the only place that can say it happened.
    echo "converting to Mac Roman / CR line endings:"
    sed 's/^/  /' "$mactext_paths"
    while IFS= read -r f; do
        rm -f "$root/$f"
    done <"$mactext_paths"
    xargs git -C "$root" checkout HEAD -- <"$mactext_paths"
fi

echo "materializing real files from their .hqx/.r sidecars..."
"$root/tools/mac-forks/import.sh"

echo "done."
