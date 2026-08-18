#!/usr/bin/env bash
#
# Render Packaging/release-notes.md for one tag, on stdout.
#
# `gh release create --generate-notes` produces a bare changelog link, which is
# the wrong thing on the page where someone has to choose between two .debs
# whose architectures name a bootstrap layout rather than a CPU. This fills in
# the version, the upstream commit, and the iOS floor so that page explains
# itself without anyone remembering to write it each time.

set -Eeuo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: $0 <tag>" >&2
    exit 64
fi

tag="$1"
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
template="$repository_root/Packaging/release-notes.md"

# shellcheck source=../Configuration/upstream.env
source "$repository_root/Configuration/upstream.env"

: "${KWWK_REF:?Configuration/upstream.env must set KWWK_REF}"
: "${KK_MIN_IOS:?Configuration/upstream.env must set KK_MIN_IOS}"

[[ -f "$template" ]] || { echo "error: missing $template" >&2; exit 66; }

version="$(cat "$repository_root/Configuration/version.txt")"
version="${version//[[:space:]]/}"
package_id="${PACKAGE_ID:-wiki.qaq.kk}"

rendered="$(
    sed \
        -e "s|@PACKAGE_ID@|$package_id|g" \
        -e "s|@VERSION@|$version|g" \
        -e "s|@TAG@|$tag|g" \
        -e "s|@UPSTREAM_REF@|$KWWK_REF|g" \
        -e "s|@UPSTREAM_SHORT@|${KWWK_REF:0:7}|g" \
        -e "s|@MIN_IOS_MAJOR@|${KK_MIN_IOS%%.*}|g" \
        "$template"
)"

# A leftover placeholder would ship as literal @NOISE@ on the release page.
if grep -q '@[A-Z_]*@' <<<"$rendered"; then
    echo "error: release notes still hold unsubstituted placeholders:" >&2
    grep -n '@[A-Z_]*@' <<<"$rendered" | sed 's/^/       /' >&2
    exit 65
fi

printf '%s\n' "$rendered"
