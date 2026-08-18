#!/usr/bin/env bash
#
# Fetch kwwk at the pinned ref into <work-dir> and apply patches/ on top.
#
# Idempotent: a stamp records the ref plus the digest of every patch, so a
# repeat call with nothing changed leaves the tree (and any incremental build
# state pointing at it) alone. When something *has* changed the checkout is
# reset hard and repatched, because a half-applied patch set is the one state
# that produces confusing compiler errors instead of an honest failure.

set -Eeuo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: $0 <work-dir>" >&2
    exit 64
fi

work_dir="$1"
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
patch_dir="$repository_root/patches"

# shellcheck source=../Configuration/upstream.env
source "$repository_root/Configuration/upstream.env"

: "${KWWK_REPO:?Configuration/upstream.env must set KWWK_REPO}"
: "${KWWK_REF:?Configuration/upstream.env must set KWWK_REF}"

[[ -d "$patch_dir" ]] || { echo "error: missing patches directory: $patch_dir" >&2; exit 66; }

shopt -s nullglob
patches=("$patch_dir"/*.patch)
shopt -u nullglob
((${#patches[@]} > 0)) || { echo "error: patches/ holds no .patch files" >&2; exit 66; }

# The stamp has to cover the patch *contents*, not just their names — editing a
# patch in place is the normal way to work on one, and a name-only stamp would
# silently reuse a tree built from the previous version.
stamp_input="$KWWK_REPO@$KWWK_REF"$'\n'
for patch in "${patches[@]}"; do
    stamp_input+="$(shasum -a 256 "$patch" | cut -d ' ' -f 1)  $(basename "$patch")"$'\n'
done
stamp="$(printf '%s' "$stamp_input" | shasum -a 256 | cut -d ' ' -f 1)"
stamp_file="$work_dir/.kk-source-stamp"

if [[ -f "$stamp_file" && "$(cat "$stamp_file")" == "$stamp" ]]; then
    echo "source is already prepared at $KWWK_REF with ${#patches[@]} patch(es)"
    exit 0
fi

mkdir -p "$work_dir"
if [[ ! -d "$work_dir/.git" ]]; then
    git -C "$work_dir" init --quiet
    git -C "$work_dir" remote add origin "$KWWK_REPO"
fi

git -C "$work_dir" remote set-url origin "$KWWK_REPO"
rm -f "$stamp_file"

# Fetching the ref itself (rather than cloning and then checking out) keeps this
# to one shallow object transfer whether KWWK_REF is a commit or a branch.
echo "fetching $KWWK_REPO at $KWWK_REF"
git -C "$work_dir" fetch --quiet --depth 1 --force origin "$KWWK_REF"
git -C "$work_dir" checkout --quiet --detach FETCH_HEAD
git -C "$work_dir" reset --quiet --hard FETCH_HEAD
git -C "$work_dir" clean -qfdx

resolved_ref="$(git -C "$work_dir" rev-parse HEAD)"
echo "checked out $resolved_ref"

for patch in "${patches[@]}"; do
    echo "applying $(basename "$patch")"
    # --3way would let a patch "succeed" by leaving conflict markers in a Swift
    # file, which fails later and further away. Refuse instead: a patch that no
    # longer applies is a signal to look at what upstream changed.
    if ! git -C "$work_dir" apply --whitespace=nowarn "$patch"; then
        echo "error: $(basename "$patch") does not apply to $resolved_ref" >&2
        echo "       upstream moved; rebase the patch or repin KWWK_REF" >&2
        exit 65
    fi
done

printf '%s\n' "$stamp" >"$stamp_file"
echo "prepared $KWWK_REF with ${#patches[@]} patch(es)"
