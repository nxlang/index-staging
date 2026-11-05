#!/bin/sh
# What the periodic check does with its report (nxpkg spec 5.10 rule 6):
# - each package with a URL or a tag not `ok` has one open issue, addressed to its
#   owners, commented at each run while it lasts, closed when it is fixed;
# - after four weeks without a fix, an original URL of a built package that has a
#   mirror is removed from `urls` (the mirror remains), in a commit of its own; a moved
#   tag, a source mirror or a URL without another one is only reported.
#
#   report.sh <report.txt>      (the output of `nxpkg index check --remote`)
#
# Needs gh (GH_TOKEN, issues: write) and REPO; DRY_RUN=1 prints what it would do.
# Leaves the files changed for the caller to commit and push.
set -eu
report="$1"
: "${REPO:?REPO=<owner>/<repo>}"
today="$(date -u +%F)"
weeks4="$(date -u -d '28 days ago' +%F 2>/dev/null || date -u -v-28d +%F)"
gh_() { if [ "${DRY_RUN:-0}" = 1 ]; then echo "gh $*"; else gh "$@"; fi; }
file_of() { # the package file of a name (nxpkg spec 5.4 rule 8)
    n="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
    case "${#n}" in
        1|2) echo "${#n}/$n.toml" ;;
        3) echo "3/$(printf '%s' "$n" | cut -c1)/$n.toml" ;;
        *) echo "$(printf '%s' "$n" | cut -c1-2)/$(printf '%s' "$n" | cut -c3-4)/$n.toml" ;;
    esac
}
bad="$(grep -v '^ok ' "$report" | grep -E '^(changed|missing) ' || true)"
names="$( (printf '%s\n' "$bad" | awk 'NF {print $2}'; gh_ issue list -R "$REPO" --state open --label periodic --json title --jq '.[].title' 2>/dev/null | sed -n 's/^periodic check: //p') | sort -u)"
for name in $names; do
    lines="$(printf '%s\n' "$bad" | awk -v n="$name" '$2 == n')"
    number="$(gh issue list -R "$REPO" --state open --label periodic --search "in:title \"periodic check: $name\"" --json number,title --jq ".[] | select(.title == \"periodic check: $name\") | .number" 2>/dev/null | head -1)"
    if [ -z "$lines" ]; then
        [ -n "$number" ] && gh_ issue close "$number" -R "$REPO" --comment "Fixed: every URL and tag of $name is ok ($today)."
        continue
    fi
    file="$(file_of "$name")"
    owners="$(sed -n 's/^owners[[:space:]]*=[[:space:]]*\[\(.*\)\]/\1/p' "$file" 2>/dev/null | tr -d '" ' | tr ',' '\n' | sed -n 's/^github:/@/p' | tr '\n' ' ')"
    body="$(printf 'The periodic check of %s found, for `%s`:\n\n```\n%s\n```\n\n%s: after four weeks without a fix, an original URL of a built package that has a mirror is removed from `urls` (nxpkg spec 5.10 rule 6); a moved tag is never followed.' "$today" "$name" "$lines" "${owners:-The owners}")"
    if [ -z "$number" ]; then
        gh_ issue create -R "$REPO" --title "periodic check: $name" --label periodic --body "$body"
        continue
    fi
    gh_ issue comment "$number" -R "$REPO" --body "$body"
    opened="$(gh issue view "$number" -R "$REPO" --json createdAt --jq '.createdAt[0:10]' 2>/dev/null || echo "$today")"
    [ "$opened" \< "$weeks4" ] || [ "$opened" = "$weeks4" ] || continue
    # Four weeks: each original URL of a built package that another URL backs is removed.
    printf '%s\n' "$lines" | while read -r state n version url rest; do
        [ -z "$rest" ] || continue                       # a git source and its tag: reported only
        grep -q "^urls[[:space:]]*=.*\"$url\"" "$file" || continue    # a source mirror: reported only
        grep "^urls[[:space:]]*=.*\"$url\"" "$file" | grep -q ',' || continue   # no other URL: kept
        awk -v u="\"$url\"" '/^urls[ ]*=/ && index($0, u) { sub(", " u, ""); sub(u ", ", "") } { print }' "$file" >"$file.new" && mv "$file.new" "$file"
        echo "removed $url from $name $version (issue #$number, opened $opened)"
    done
done
