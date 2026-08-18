#!/usr/bin/env bash
#
# Write the package version to Configuration/version.txt.
#
# Accepts a release tag as well as a bare version, because CI hands it
# "$GITHUB_REF_NAME" straight from a v-prefixed tag.

set -Eeuo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: $0 <version>" >&2
    exit 64
fi

version="${1#v}"
# X.Y.Z tracks upstream's KWWKBuild.version; the optional -N is a packaging
# revision for a respin of the same upstream code, and apt orders it after the
# bare version.
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]] || {
    echo "error: version must look like 1.2.3 or 1.2.3-2 (got '$1')" >&2
    exit 64
}

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
printf '%s\n' "$version" >"$repository_root/Configuration/version.txt"
echo "version is now $version"
