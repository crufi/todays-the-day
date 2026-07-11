#!/bin/sh
# Warns before something is about to destroy a disk image (typically a
# djjr-converted .hda) that might hold emulator-side edits nothing has
# pulled back into git yet -- see pull-from-disk.sh. Two independent
# checks; if either trips, requires typing an exact confirmation phrase
# before letting the caller proceed. Anything else aborts (non-zero
# exit), leaving the disk image untouched.
#
# Usage: tools/mac-forks/guard-overwrite.sh <disk-image>
#
# Set FORCE=1 (env or `make ... FORCE=1`) to skip all of this --
# needed for non-interactive use, since the confirmation prompt reads
# from stdin and would otherwise hang.
set -eu
export LC_ALL=C   # HFS catalog names off hls are raw Mac Roman bytes

disk=${1:?"usage: $0 <disk-image>"}

[ -z "${FORCE:-}" ] || exit 0
[ -f "$disk" ] || exit 0   # nothing to lose

for tool in hmount humount hls; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$0: missing $tool -- install hfsutils (brew install hfsutils)" >&2; exit 1; }
done

root=$(git rev-parse --show-toplevel)
cd "$root"
# shellcheck source=lib.sh
. "$root/tools/mac-forks/lib.sh"

hfsname() {
    printf '%s' "$1" | iconv -f UTF-8 -t MACINTOSH
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Candidate files: same discovery build-floppy.sh/pull-from-disk.sh use
# (tracked .hqx/.r sidecars name the real forked file; filter=mactext
# names the real text file directly). Written to a file rather than piped
# into the while loops below so they run in *this* shell, not a subshell
# -- needed so $newest_local actually survives past the loop.
git -c core.quotePath=false ls-files > "$tmp/tracked"

newest_local=0
: >"$tmp/candidates"   # real-path TAB local-mtime
while IFS= read -r f; do
    if has_ext_ci "$f" hqx || has_ext_ci "$f" r; then
        real=${f%.*}
    else
        attr=$(git check-attr filter -- "$f" | awk -F': ' '{print $NF}')
        [ "$attr" = mactext ] || continue
        real=$f
    fi
    [ -e "$real" ] || continue
    mtime=$(stat -f %m "$real")
    [ "$mtime" -gt "$newest_local" ] && newest_local=$mtime
    printf '%s\t%s\n' "$real" "$mtime" >>"$tmp/candidates"
done <"$tmp/tracked"

# Whole-image check: is the disk image itself newer than every local
# tracked file? If so, something touched it (almost certainly the
# emulator) after the last local edit.
disk_mtime=$(stat -f %m "$disk")
whole_flag=0
[ "$disk_mtime" -gt "$newest_local" ] && whole_flag=1

# Per-file check: hls -l shows "Mon DD HH:MM" for recent files or
# "Mon DD  YYYY" for older ones -- a 4-digit third token means "use this
# year," an HH:MM token means "assume the current year" (hls's own
# recent-vs-old heuristic, same as classic ls -l).
humount 2>/dev/null || true
hmount "$disk" >/dev/null
: >"$tmp/hls_dates"
hls -l 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        f\ *|F\ *) ;;
        *) continue ;;
    esac
    set -- $line
    mon=$5; day=$6; tyr=$7
    shift 7
    name="$*"
    # Force :00 seconds -- hls only has minute resolution, but `date -j
    # -f` fills any field missing from the input (seconds, here) from the
    # *current* wall-clock time rather than zero. Left alone, that makes
    # the parsed epoch drift later the longer this script takes to run,
    # confirmed to produce false positives on files pulled only seconds
    # earlier in the same minute.
    case "$tyr" in
        *:*) fmt="%b %d %Y %H:%M:%S"; ts="$mon $day $(date +%Y) $tyr:00" ;;
        *)   fmt="%b %d %Y %H:%M:%S"; ts="$mon $day $tyr 00:00:00" ;;
    esac
    epoch=$(date -j -f "$fmt" "$ts" +%s 2>/dev/null) || continue
    printf '%s\t%s\n' "$name" "$epoch" >>"$tmp/hls_dates"
done
humount >/dev/null

: >"$tmp/newer_files"
while IFS="$(printf '\t')" read -r real mtime; do
    hname=$(hfsname "$real")
    hepoch=$(awk -F'\t' -v n="$hname" '$1==n{print $2; exit}' "$tmp/hls_dates")
    # hls only has minute resolution, so truncate the local mtime to the
    # same minute before comparing -- otherwise a file pulled seconds ago
    # (same minute as the disk's own timestamp) reads as "stale" purely
    # from sub-minute jitter.
    mtime_trunc=$((mtime - mtime % 60))
    if [ -n "$hepoch" ] && [ "$hepoch" -gt "$mtime_trunc" ]; then
        printf '%s\n' "$real" >>"$tmp/newer_files"
    fi
done <"$tmp/candidates"

file_count=$(wc -l <"$tmp/newer_files" | tr -d ' ')

# Red for the warning + confirmation prompt specifically -- the whole
# point is to stand out against the rest of the build's normal output.
# Skipped when stderr isn't a terminal (FORCE=1 already exits before this
# point for non-interactive use, but a redirected-but-not-forced run
# shouldn't get raw escape codes in a log file).
if [ -t 2 ]; then
    RED=$(printf '\033[31m')
    RESET=$(printf '\033[0m')
else
    RED=
    RESET=
fi

if [ "$whole_flag" = 1 ] || [ "$file_count" -gt 0 ]; then
    printf '%sWARNING: %s may hold changes that only exist there.%s\n' "$RED" "$disk" "$RESET" >&2
    [ "$whole_flag" = 1 ] && echo "  - $disk itself is newer than every local tracked file" >&2
    if [ "$file_count" -gt 0 ]; then
        echo "  - these files on $disk look newer than their local copies:" >&2
        while IFS= read -r nf; do echo "      $nf" >&2; done <"$tmp/newer_files"
    fi
    echo "" >&2
    echo "Run 'make pull' first if you want to keep those changes." >&2
    echo "" >&2
    if [ "$file_count" -gt 0 ]; then
        phrase="BORK $file_count"
    else
        phrase="BORK DISK"
    fi
    printf '%sType %s to overwrite %s and discard anything only stored there: %s' "$RED" "$phrase" "$disk" "$RESET" >&2
    read -r answer
    if [ "$answer" != "$phrase" ]; then
        echo "aborted -- $disk left untouched" >&2
        exit 1
    fi
fi
