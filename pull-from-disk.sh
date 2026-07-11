#!/bin/sh
# Pulls files off a disk image (plain .img or a djjr-converted .hda) back
# into the git working tree -- the reverse of build-floppy.sh. For when
# files got edited directly in the emulator (inside the IDE, say) and
# those edits only exist on the disk image so far.
#
# Usage: tools/mac-forks/pull-from-disk.sh <disk-image>
#
# Driven by the same git-attribute discovery as build-floppy.sh/export.sh/
# import.sh: tracked .hqx/.r sidecars name the real, materialized forked
# files; filter=mactext names the real text files. No per-project file
# list needed.
#
# Also rescues files that exist on the disk with no tracked counterpart
# at all -- created directly in the emulator, never added to git. Pulled
# via MacBinary regardless of what they turn out to be (there's no
# tracked .gitattributes match to consult yet for something never
# tracked), which faithfully preserves whatever's actually there; from
# that point on it's an ordinary new local file, same as one you'd
# created by hand -- `git add` picks up .gitattributes' filter=mactext if
# the extension matches, or export.sh's own resource-fork detection
# sidecars it on the next commit if it's genuinely forked.
#
# Does NOT run export.sh or `git add` -- it only updates the real,
# gitignored/working-tree files. The pre-commit hook already syncs
# sidecars from real files normally; after running this, `git status`/
# `git diff` show exactly what came back from the emulator, same as any
# other local edit.
#
# Requires hfsutils (hmount/humount/hcopy/hls) and macbinary -- same as
# build-floppy.sh.
set -eu

for tool in hmount humount hcopy hls; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$0: missing $tool -- install hfsutils (brew install hfsutils)" >&2
        exit 1
    fi
done
for tool in macbinary iconv; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$0: missing $tool -- expected to ship with base macOS" >&2
        exit 1
    fi
done

disk=${1:?"usage: $0 <disk-image>"}
[ -f "$disk" ] || { echo "$0: $disk: no such file" >&2; exit 1; }

root=$(git rev-parse --show-toplevel)
cd "$root"
# shellcheck source=lib.sh
. "$root/tools/mac-forks/lib.sh"

# Same byte-level reasoning as build-floppy.sh's hfsname(): HFS catalog
# names are raw Mac Roman bytes, not UTF-8, so writing/matching them
# needs an explicit conversion, not whatever the locale happens to do.
hfsname() {
    printf '%s' "$1" | LC_ALL=C iconv -f UTF-8 -t MACINTOSH
}

# Reverse direction, for turning a raw HFS catalog name (Mac Roman) back
# into a usable local filename -- best-effort, falls back to the raw
# bytes if a file was named with something outside Mac Roman's
# repertoire (shouldn't happen from a real HFS volume).
display_name() {
    printf '%s' "$1" | LC_ALL=C iconv -f MACINTOSH -t UTF-8 2>/dev/null || printf '%s' "$1"
}

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

humount 2>/dev/null || true   # in case a previous run left something mounted
hmount "$disk"

# Forked files: pull as MacBinary (both forks + type/creator in one
# blob) and decode back into a real macOS file, overwriting whatever's
# currently reconstituted at that path. Decode into a tmpdir first and
# only replace the real file once that's succeeded -- same reasoning as
# import.sh's from_hqx: a failed decode should leave the existing file
# alone, not delete it and come up empty.
git -c core.quotePath=false ls-files | while IFS= read -r f; do
    if has_ext_ci "$f" hqx || has_ext_ci "$f" r; then
        real=${f%.*}
        tmp=$(mktemp -d)
        if hcopy -m ":$(hfsname "$real")" "$tmp/blob.bin" 2>/dev/null; then
            macbinary decode -p -C "$tmp" -o restored <"$tmp/blob.bin"
            mkdir -p "$(dirname "$real")"
            rm -rf "${real:?}"
            mv "$tmp/restored" "$real"
            touch "$real"   # macbinary decode sets mtime from the MacBinary
                             # header's own date field, not extraction time --
                             # confirmed empirically it can be hours stale,
                             # which would make guard-overwrite.sh re-flag a
                             # file we just pulled as still needing a pull
            echo "hcopy -m: $real"
        fi
        rm -rf "$tmp"
    fi
done

# mactext-filtered text files: pull the data fork raw (no translation --
# same hcopy -a/-t double-conversion bug build-floppy.sh works around).
# The bytes on disk are already genuine Mac Roman + CR, exactly what the
# working tree expects -- git's own mactext clean filter normalizes them
# at the next `git add`.
git -c core.quotePath=false ls-files | while IFS= read -r f; do
    attr=$(git check-attr filter -- "$f" | awk -F': ' '{print $NF}')
    if [ "$attr" = mactext ]; then
        if hcopy -r ":$(hfsname "$f")" "$f.pulled" 2>/dev/null; then
            mv "$f.pulled" "$f"
            echo "hcopy -r: $f"
        fi
    fi
done

# New files: present on the disk, no tracked counterpart at all -- build
# the same "expected HFS name per tracked candidate" list guard-overwrite.sh
# uses, then anything on the disk that doesn't match gets pulled too.
: >"$tmp_root/candidate_hfsnames"
git -c core.quotePath=false ls-files | while IFS= read -r f; do
    if has_ext_ci "$f" hqx || has_ext_ci "$f" r; then
        real=${f%.*}
    else
        attr=$(git check-attr filter -- "$f" | awk -F': ' '{print $NF}')
        [ "$attr" = mactext ] || continue
        real=$f
    fi
    printf '%s\n' "$(hfsname "$real")" >>"$tmp_root/candidate_hfsnames"
done

hls -l 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        f\ *|F\ *) ;;
        *) continue ;;
    esac
    set -- $line
    shift 7
    name="$*"
    grep -qxF "$name" "$tmp_root/candidate_hfsnames" 2>/dev/null && continue
    real=$(display_name "$name")
    tmp=$(mktemp -d)
    if hcopy -m ":$name" "$tmp/blob.bin" 2>/dev/null; then
        macbinary decode -p -C "$tmp" -o restored <"$tmp/blob.bin"
        mkdir -p "$(dirname "$real")"
        rm -rf "${real:?}"
        mv "$tmp/restored" "$real"
        touch "$real"
        echo "hcopy -m (new): $real"
    fi
    rm -rf "$tmp"
done

humount
echo "done pulling from $disk"
