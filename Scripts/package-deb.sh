#!/usr/bin/env bash
#
# Stage, ad-hoc sign, and build one .deb from a payload directory that
# build-ios.sh assembled. Called once per bootstrap layout; the payload is the
# same both times, only the install prefix and the architecture label differ.

set -Eeuo pipefail

if [[ "$#" -ne 5 ]]; then
    echo "usage: $0 <payload-dir> <output-deb> <version> <architecture> <install-prefix>" >&2
    echo "note: install-prefix is empty for roothide and /var/jb for rootless" >&2
    exit 64
fi

payload="$1"
output_deb="$2"
version="$3"
architecture="$4"
# Empty for roothide, which is relocated into the jbroot it picked this boot and
# whose programs resolve unprefixed paths inside it, and /var/jb for a rootless
# bootstrap, which has to be named in every path the package ships — including
# the launcher's own interpreter line.
install_prefix="$5"

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=../Configuration/upstream.env
source "$repository_root/Configuration/upstream.env"

: "${KK_PROGRAM:?Configuration/upstream.env must set KK_PROGRAM}"
: "${KK_MIN_IOS:?Configuration/upstream.env must set KK_MIN_IOS}"
: "${KWWK_PRODUCT:?Configuration/upstream.env must set KWWK_PRODUCT}"
: "${KWWK_REF:?Configuration/upstream.env must set KWWK_REF}"

package_id="${PACKAGE_ID:-wiki.qaq.kk}"
control_template="$repository_root/Packaging/DEBIAN/control"
entitlements="$repository_root/Packaging/kk.entitlements"
launcher_source="$repository_root/Packaging/kk.launcher.c"

for input in "$control_template" "$entitlements" "$launcher_source"; do
    [[ -f "$input" ]] || { echo "error: missing packaging input: $input" >&2; exit 66; }
done

resource_bundle="${KWWK_PRODUCT}_KWWKAI.bundle"
[[ -d "$payload" ]] || { echo "error: no payload directory at $payload" >&2; exit 66; }
[[ -f "$payload/$KK_PROGRAM" ]] || { echo "error: payload has no $KK_PROGRAM" >&2; exit 66; }
[[ -d "$payload/$resource_bundle" ]] || { echo "error: payload has no $resource_bundle" >&2; exit 66; }

[[ "$output_deb" == *.deb ]] || { echo "error: output must end in .deb" >&2; exit 64; }
[[ "$package_id" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || { echo "error: invalid package id" >&2; exit 64; }
[[ "$version" =~ ^[0-9A-Za-z.+:~_-]+$ ]] || { echo "error: invalid version" >&2; exit 64; }
[[ "$architecture" =~ ^[A-Za-z0-9][A-Za-z0-9-]+$ ]] || { echo "error: invalid architecture" >&2; exit 64; }
[[ "$install_prefix" =~ ^(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] || { echo "error: invalid install prefix" >&2; exit 64; }

case "$architecture:$install_prefix" in
iphoneos-arm64:/var/jb | iphoneos-arm64e:) ;;
*) echo "error: architecture and install prefix name different bootstrap layouts" >&2; exit 64 ;;
esac

for tool in ldid dpkg-deb xcrun vtool; do
    command -v "$tool" >/dev/null || { echo "error: $tool is not installed" >&2; exit 69; }
done

# Refuse to package a host binary. build-ios.sh checks this too, but this script
# is callable on its own and a macOS Mach-O in a .deb fails only on device.
vtool -show-build "$payload/$KK_PROGRAM" 2>/dev/null | grep -qE '^ *platform (IOS|2)$' || {
    echo "error: $payload/$KK_PROGRAM is not an iOS binary" >&2
    exit 65
}

output_name="$(basename "$output_deb")"
mkdir -p "$(dirname "$output_deb")"
output_directory="$(cd -- "$(dirname -- "$output_deb")" && pwd -P)"
output_deb="$output_directory/$output_name"

staging="$(mktemp -d "${TMPDIR:-/tmp}/kk-deb.XXXXXX")"
temporary_deb="$output_directory/.$output_name.tmp.$$"
signed_entitlements="$(mktemp "${TMPDIR:-/tmp}/kk-entitlements.XXXXXX.plist")"
trap 'rm -rf -- "$staging"; rm -f -- "$temporary_deb" "$signed_entitlements"' EXIT
chmod 0755 "$staging"

debian="$staging/DEBIAN"
installed_root="$staging$install_prefix"
# The payload installs verbatim: the executable, its resource bundle, and any
# Swift back-deployment shim all have to stay in one directory, because the
# bundle is found beside the running executable and the shim resolves through
# the executable's @loader_path rpath. /usr/bin gets a launcher instead of a
# symlink, which would move that lookup to /usr/bin and break both.
installed_libexec="$installed_root/usr/libexec/$KK_PROGRAM"
installed_launcher="$installed_root/usr/bin/$KK_PROGRAM"
mkdir -p "$debian" "$(dirname "$installed_libexec")" "$(dirname "$installed_launcher")"

/usr/bin/ditto "$payload" "$installed_libexec"
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun clang -target "arm64-apple-ios$KK_MIN_IOS" -isysroot "$sdk_path" -Os -fvisibility=hidden \
    "-DOG_PROGRAM=\"$KK_PROGRAM\"" "-DOG_STATIC_PREFIX=\"$install_prefix\"" \
    "$launcher_source" -Wl,-dead_strip -o "$installed_launcher"

# The program still calls itself kwwk in its own help and error messages, and
# renaming those would mean carrying a patch across every upstream edit to the
# usage text for no functional gain. Shipping the second name instead makes
# what it already prints true, and costs one symlink. Pointing at the launcher
# (not the binary) is what keeps this safe: the launcher execs an absolute
# path, so the resource-bundle lookup never sees a symlinked executable.
ln -s "$KK_PROGRAM" "$installed_root/usr/bin/$KWWK_PRODUCT"

chmod 0755 "$installed_launcher" "$installed_libexec/$KK_PROGRAM"
chmod -R a+rX "$installed_libexec"

vtool -show-build "$installed_launcher" 2>/dev/null | grep -qE '^ *platform (IOS|2)$' || {
    echo "error: launcher is not an iOS binary" >&2
    exit 65
}

# Everything executable gets a signature. The shims carry no entitlements —
# only the program does, and giving a library the program's privileges would be
# handing them to anything that ever loads it.
for executable in "$installed_launcher" "$installed_libexec/$KK_PROGRAM"; do
    ldid -S"$entitlements" -Cadhoc "$executable"
done
shopt -s nullglob
for library in "$installed_libexec"/*.dylib; do
    ldid -S -Cadhoc "$library"
    chmod 0755 "$library"
done
shopt -u nullglob

# ldid silently ships an unentitled binary when the plist it was handed is
# malformed, and the symptom on device is a sandbox denial with no mention of
# signing. Read back what landed in the signature.
require_true() {
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$1" "$signed_entitlements" 2>/dev/null || true)" == true ]] || {
        echo "error: signed binary is missing entitlement: $1" >&2
        exit 65
    }
}
for executable in "$installed_launcher" "$installed_libexec/$KK_PROGRAM"; do
    ldid -e "$executable" >"$signed_entitlements"
    require_true platform-application
    require_true com.apple.private.security.no-sandbox
    require_true com.apple.private.security.storage.AppBundles
    require_true com.apple.private.security.storage.AppDataContainers
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.private.security.container-required' \
        "$signed_entitlements" 2>/dev/null || true)" == false ]] || {
        echo "error: $executable needs com.apple.private.security.container-required = false" >&2
        exit 65
    }
done

installed_size="$(du -sk "$installed_root" | awk '{print $1}')"
sed \
    -e "s|@PACKAGE_ID@|$package_id|g" \
    -e "s|@VERSION@|$version|g" \
    -e "s|@ARCHITECTURE@|$architecture|g" \
    -e "s|@INSTALLED_SIZE@|$installed_size|g" \
    -e "s|@MIN_IOS@|$KK_MIN_IOS|g" \
    -e "s|@UPSTREAM@|EYHN/kwwk@${KWWK_REF:0:12}|g" \
    "$control_template" >"$debian/control"
chmod 0644 "$debian/control"
if grep -q '@[A-Z_]*@' "$debian/control"; then
    echo "error: control still holds unsubstituted placeholders:" >&2
    grep -n '@[A-Z_]*@' "$debian/control" | sed 's/^/       /' >&2
    exit 65
fi

dpkg-deb --root-owner-group -Zzstd -b "$staging" "$temporary_deb" >/dev/null

[[ "$(dpkg-deb -f "$temporary_deb" Package)" == "$package_id" ]]
[[ "$(dpkg-deb -f "$temporary_deb" Version)" == "$version" ]]
[[ "$(dpkg-deb -f "$temporary_deb" Architecture)" == "$architecture" ]]
contents="$(dpkg-deb --contents "$temporary_deb")"
for path in \
    "$install_prefix/usr/bin/$KK_PROGRAM" \
    "$install_prefix/usr/bin/$KWWK_PRODUCT" \
    "$install_prefix/usr/libexec/$KK_PROGRAM/$KK_PROGRAM" \
    "$install_prefix/usr/libexec/$KK_PROGRAM/$resource_bundle/models.json" \
    "$install_prefix/usr/libexec/$KK_PROGRAM/$resource_bundle/cursor-models.json"; do
    grep -qF ".$path" <<<"$contents" || {
        echo "error: package is missing $path" >&2
        exit 65
    }
done

mv -f "$temporary_deb" "$output_deb"
echo "packaged $package_id $version ($architecture, prefix '${install_prefix:-/}'): $output_deb"
shasum -a 256 "$output_deb"
