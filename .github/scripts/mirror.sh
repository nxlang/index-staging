#!/bin/sh
# The mirror (nxpkg spec 5.10 rule 5, lot X2c): for each version of the given packages'
# files, its sources' archive (`nxpkg index mirror-archive`, `mirror`), and a copy of
# each built package (`urls`), uploaded to the release `<name>` of this repository and
# named in the file. Idempotent: what is mirrored already is left alone.
#
#   mirror.sh <file.toml>...       (paths in the index, `he/ll/hello.toml`)
#
# Needs: nxpkg on PATH, gh logged in (GH_TOKEN), REPO=<owner>/<repo>. Writes the files in
# place; the caller commits and pushes. An archive whose checksum is not the index's is
# never uploaded.
set -eu
: "${REPO:?REPO=<owner>/<repo>}"
base="https://github.com/$REPO/releases/download"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
changed=0
for file in "$@"; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .toml)"
    release="$name"
    if ! gh release view "$release" -R "$REPO" >/dev/null 2>&1; then
        gh release create "$release" -R "$REPO" --title "$name (mirror)" \
            --notes "The mirror of $name: its sources and built packages, as the index names them." >/dev/null
    fi
    # What the file holds, one line each: `V <version> <mirror>` and
    # `N <version> <sha256 checksum> <first url> <all urls>` (the format nxpkg writes).
    awk '
        /^\[\[versions\]\]/ { flush(); kind = "V"; version = ""; mirror = "-"; next }
        /^\[\[versions\.nxp\]\]/ { flush(); kind = "N"; urls = ""; sum = ""; next }
        /^\[/ { flush(); kind = ""; next }
        kind == "V" && $1 == "version" { v = $0; sub(/^[^"]*"/, "", v); sub(/".*/, "", v); version = v }
        kind == "V" && $1 == "mirror" { m = $0; sub(/^[^"]*"/, "", m); sub(/".*/, "", m); mirror = m }
        kind == "N" && $1 == "urls" { u = $0; sub(/^[^\[]*\[/, "", u); sub(/\].*/, "", u); gsub(/[" ]/, "", u); urls = u }
        kind == "N" && $1 == "url" { u = $0; sub(/^[^"]*"/, "", u); sub(/".*/, "", u); urls = u }
        kind == "N" && $1 == "checksum" { s = $0; sub(/^[^"]*"/, "", s); sub(/".*/, "", s); sum = s }
        function flush() {
            if (kind == "V" && version != "") print "V", version, mirror
            if (kind == "N" && urls != "") { split(urls, a, ","); print "N", version, sum, a[1], urls }
            kind = ""
        }
        END { flush() }
    ' "$file" >"$work/items"
    while read -r kind version a b c; do
        if [ "$kind" = V ] && [ "$a" = "-" ]; then
            out="$work/$name-$version-src.tar.gz"
            nxpkg index mirror-archive "$name" "$version" --index "file://$PWD" --out "$out" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
            gh release upload "$release" "$out" -R "$REPO" >/dev/null
            url="$base/$release/$(basename "$out")"
            # `mirror` after the version's checksum line.
            awk -v v="$version" -v url="$url" '
                /^\[\[versions\]\]/ { inv = 0 }
                { print }
                /^version[ ]*=/ { inv = ($0 ~ "\"" v "\"") }
                inv && /^checksum[ ]*=[ ]*"nxsum/ { print "mirror   = \"" url "\""; inv = 0 }
            ' "$file" >"$work/f" && mv "$work/f" "$file"
            echo "mirrored $name $version: sources -> $url"
            changed=1
        fi
        if [ "$kind" = N ]; then
            case "$c" in *"$base/$release/"*) continue ;; esac
            asset="$(basename "$b")"
            curl -fsSL --retry 3 -o "$work/$asset" "$b"
            got="sha256:$(sha256sum "$work/$asset" | cut -d' ' -f1)"
            [ "$got" = "$a" ] || { echo "error: $name $version: $b is $got, the index says $a" >&2; exit 1; }
            gh release upload "$release" "$work/$asset" -R "$REPO" >/dev/null
            url="$base/$release/$asset"
            # Appended to the `urls` that lists the original.
            awk -v orig="\"$b\"" -v url="\"$url\"" '
                /^urls[ ]*=/ && index($0, orig) > 0 { sub(/\][ ]*$/, ", " url "]") }
                { print }
            ' "$file" >"$work/f" && mv "$work/f" "$file"
            echo "mirrored $name $version: $asset -> $url"
            changed=1
        fi
    done <"$work/items"
done
[ "$changed" = 1 ] || echo "mirror: nothing to mirror"
