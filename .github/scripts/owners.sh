#!/bin/sh
# The ownership check of a pull request (nxpkg spec 5.10 rule 3), which `nxpkg index
# check` leaves to the index's automation: who opened it is GitHub's knowledge.
#
#   owners.sh <base commit> <GitHub login of the pull request's author>
#
# - a package that exists at <base> may be changed only by one of its `owners`
#   (`github:<login>`): otherwise the check fails;
# - a new name, or a change of `owners` or `signers`, needs a person: said in the
#   summary (the pull request is then merged by hand; never automatically).
# Reads only the index's files: runs no code of the pull request.
set -eu
base="$1"
author="$2"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
status=0
review=""
line_of() { # the `<key> = [...]` line of a package file's text, "" when none
    printf '%s\n' "$2" | sed -n "s/^$1[[:space:]]*=[[:space:]]*\(\[.*\]\)[[:space:]]*\$/\1/p" | head -1
}
for path in $(git diff --name-only "$base" HEAD); do
    case "$path" in
        index.toml|names|.github/*|README.md|SECURITY.md|CNAME|.nojekyll) continue ;;
        *.toml) ;;
        *) continue ;;
    esac
    name="$(basename "$path" .toml)"
    if ! old="$(git show "$base:$path" 2>/dev/null)"; then
        review="$review- \`$name\`: a new name (nxpkg spec 5.10 rules 3 and 4)\n"
        continue
    fi
    new="$(cat "$path" 2>/dev/null || true)"
    owners="$(line_of owners "$old")"
    case "$owners" in
        *"\"github:$author\""*) ;;
        *)
            echo "error: $path: $author is not one of the owners of $name ($owners)" >&2
            status=1
            ;;
    esac
    for key in owners signers; do
        if [ "$(line_of "$key" "$old")" != "$(line_of "$key" "$new")" ]; then
            review="$review- \`$name\`: its \`$key\` change\n"
        fi
    done
done
{
    echo "## Ownership"
    if [ "$status" = 0 ]; then echo "The author, \`$author\`, owns every package this pull request changes."; fi
    if [ -n "$review" ]; then
        echo
        echo "**A person must review this pull request** before it is merged:"
        printf '%b' "$review"
    fi
} >>"$summary"
exit "$status"
