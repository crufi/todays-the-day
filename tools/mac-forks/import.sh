#!/bin/sh
# Reconstitutes the real, gitignored, resource-fork-bearing files from
# their tracked .hqx / .r sidecars. Run automatically by the
# post-checkout / post-merge hooks; safe to run by hand too (e.g.
# after pulling, or `tools/mac-forks/import.sh`).
#
# Because the real files are gitignored rather than tracked, this
# writes them directly with no risk of racing git's own checkout
# machinery -- there's no tracked path for git to be materializing at
# the same time.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"
# shellcheck source=lib.sh
. "$root/tools/mac-forks/lib.sh"

from_hqx() {
    src=$1
    dest=${src%.*}
    tmp=$(mktemp -d)
    cp "$src" "$tmp/in.hqx"
    (cd "$tmp" && /usr/bin/binhex decode -n -o restored in.hqx)
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    mv "$tmp/restored" "$dest"
    rm -rf "$tmp"
    echo "binhex: $src -> $dest"
}

from_r() {
    src=$1
    dest=${src%.*}
    first_line=$(head -n 1 "$src")
    type_raw=$(printf '%s' "$first_line" | sed -n 's#^/\* mac-forks: type=\(.*\) creator=\(.*\) \*/$#\1#p')
    creator_raw=$(printf '%s' "$first_line" | sed -n 's#^/\* mac-forks: type=\(.*\) creator=\(.*\) \*/$#\2#p')
    tmp=$(mktemp -d)
    /usr/bin/Rez "$src" -o "$tmp/restored"
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    mv "$tmp/restored" "$dest"
    rm -rf "$tmp"
    if [ -n "$type_raw" ] && [ -n "$creator_raw" ]; then
        /usr/bin/SetFile -t "$(printf '%b' "$type_raw")" -c "$(printf '%b' "$creator_raw")" "$dest"
    fi
    echo "derez:  $src -> $dest"
}

find "$root" \( -path "$root/.git" -o -path "$root/tools/mac-forks" \) -prune -o -type f -print |
while IFS= read -r f; do
    rel=${f#"$root"/}
    if has_ext_ci "$rel" hqx; then
        from_hqx "$f"
    elif has_ext_ci "$rel" r; then
        from_r "$f"
    fi
done
