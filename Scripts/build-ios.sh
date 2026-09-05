#!/usr/bin/env bash
#
# Cross-compile the kwwk product for iOS out of a prepared source tree, verify
# the result is really an iOS binary, and assemble everything that has to ship
# beside it into one payload directory.
#
# Prints the payload directory on stdout (the last line). Its contents are
# exactly what lands in <prefix>/usr/libexec/kk, so packaging does not have to
# know anything about toolchain layout. Everything else goes to stderr.

set -Eeuo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 <src-dir> <scratch-dir>" >&2
    exit 64
fi

src_dir="$1"
scratch_dir="$2"
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=../Configuration/upstream.env
source "$repository_root/Configuration/upstream.env"

: "${KWWK_PRODUCT:?Configuration/upstream.env must set KWWK_PRODUCT}"
: "${KK_PROGRAM:?Configuration/upstream.env must set KK_PROGRAM}"
: "${KK_MIN_IOS:?Configuration/upstream.env must set KK_MIN_IOS}"
: "${KK_ARCH:?Configuration/upstream.env must set KK_ARCH}"

[[ -f "$src_dir/Package.swift" ]] || {
    echo "error: $src_dir is not a prepared source tree (run Scripts/prepare-source.sh)" >&2
    exit 66
}

sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
[[ -d "$sdk_path" ]] || { echo "error: no iPhoneOS SDK; install Xcode" >&2; exit 69; }
toolchain="$(dirname -- "$(dirname -- "$(xcrun -f swiftc)")")"
triple="$KK_ARCH-apple-ios$KK_MIN_IOS"

# There is no Swift SDK bundle for iOS, so every stage has to be pointed at the
# iPhoneOS sysroot by hand, and each of these flags covers a stage the others
# miss. Dropping any one still "succeeds" — with a binary that either targets
# the wrong platform or links against macOS stubs.
#
#   --triple          makes SwiftPM itself agree the build is for iOS, which is
#                     what decides `#if os(iOS)` across the whole graph. Its
#                     version component is advisory: SwiftPM raises everything
#                     to the package's own deployment target, which is why
#                     patches/ lowers Package.swift's .iOS() instead.
#   -Xswiftc -sdk     the Swift frontend's sysroot.
#   -Xcc -isysroot    the C sysroot, for BoringSSL / libwebp / libpng / stb.
#   -Xclang-linker    the *link* driver's sysroot. Without it clang links
#     -isysroot       against macOS stubs and warns "using sysroot for 'macOS'
#                     but targeting arm64-apple-ios".
#   -Xlinker          the same answer for ld's own library search.
#     -syslibroot
build_flags=(
    --package-path "$src_dir"
    --scratch-path "$scratch_dir"
    --build-system native
    --configuration release
    --product "$KWWK_PRODUCT"
    --triple "$triple"
    -Xswiftc -sdk -Xswiftc "$sdk_path"
    -Xcc -isysroot -Xcc "$sdk_path"
    -Xswiftc -file-prefix-map -Xswiftc "$src_dir=/src"
    -Xswiftc -file-prefix-map -Xswiftc "$scratch_dir=/build"
    -Xswiftc -debug-prefix-map -Xswiftc "$src_dir=/src"
    -Xswiftc -debug-prefix-map -Xswiftc "$scratch_dir=/build"
    -Xcc "-ffile-prefix-map=$src_dir=/src"
    -Xcc "-ffile-prefix-map=$scratch_dir=/build"
    -Xcc "-fdebug-prefix-map=$src_dir=/src"
    -Xcc "-fdebug-prefix-map=$scratch_dir=/build"
    -Xcc "-fmacro-prefix-map=$src_dir=/src"
    -Xcc "-fmacro-prefix-map=$scratch_dir=/build"
    -Xswiftc -Xclang-linker -Xswiftc -isysroot
    -Xswiftc -Xclang-linker -Xswiftc "$sdk_path"
    -Xlinker -syslibroot -Xlinker "$sdk_path"
)

# --build-system native is deprecated but load-bearing, and the failure it
# avoids is not obvious. Under the default (swiftbuild) system the -Xcc target
# override leaks into the host tools that libpng's package builds — libwebp
# pulls libpng in — so pnglibconf's objects come out iOS while its link step
# still runs for macOS, and the build dies on "building for 'macOS', but
# linking in object file built for 'iOS'". Replacing this flag needs a real
# Swift SDK bundle for iOS, not a flag tweak.
echo "building $KWWK_PRODUCT for $triple" >&2
echo "  SDK:       $sdk_path" >&2
echo "  toolchain: $toolchain" >&2

mkdir -p "$scratch_dir"
swift build "${build_flags[@]}" >&2

bin_dir="$(swift build "${build_flags[@]}" --show-bin-path 2>/dev/null)"
executable="$bin_dir/$KWWK_PRODUCT"
[[ -f "$executable" ]] || { echo "error: build produced no $executable" >&2; exit 65; }

# SwiftPM leaves the absolute output paths of every Swift and Clang object in
# the linked debug data. Prefix maps normalize source paths, but do not rewrite
# those object-file breadcrumbs. Strip debug sections before signing so a CI
# checkout path cannot become part of the published executable.
/usr/bin/strip -S "$executable"

# A macOS host cross-compiling to iOS fails quietly in exactly one way: the
# flags get dropped and out comes a perfectly good macOS binary that no device
# will load. Read the platform back off the Mach-O rather than trusting flags.
build_version="$(vtool -show-build "$executable" 2>/dev/null)"
grep -qE '^ *platform (IOS|2)$' <<<"$build_version" || {
    echo "error: $executable is not an iOS binary:" >&2
    sed 's/^/       /' <<<"$build_version" >&2
    exit 65
}
grep -qE "^ *minos $KK_MIN_IOS\$" <<<"$build_version" || {
    echo "error: $executable does not target iOS $KK_MIN_IOS:" >&2
    sed 's/^/       /' <<<"$build_version" >&2
    echo "hint: SwiftPM raises this to Package.swift's deployment target" >&2
    exit 65
}

architectures="$(lipo -archs "$executable")"
[[ "$architectures" == "$KK_ARCH" ]] || {
    echo "error: expected a $KK_ARCH binary, got '$architectures'" >&2
    exit 65
}

for private_path in "$repository_root" "$src_dir" "$scratch_dir"; do
    if LC_ALL=C grep -aF "$private_path" "$executable" >/dev/null; then
        echo "error: $executable embeds private build path: $private_path" >&2
        exit 65
    fi
done

# Every absolute dependency has to be a path a stock device provides out of the
# dyld shared cache. A macOS-only framework here would mean the link found the
# wrong sysroot despite the checks above.
while read -r dependency; do
    case "$dependency" in
    @*) ;;
    /usr/lib/* | /System/Library/Frameworks/*) ;;
    *)
        echo "error: $executable depends on a path iOS does not provide: $dependency" >&2
        exit 65
        ;;
    esac
done < <(otool -L "$executable" | tail -n +2 | awk '{print $1}')

# The iOS patch makes the catalog loader resolve this sidecar beside the
# running executable. Copy it from the pinned source instead of using SwiftPM's
# generated resource accessor, whose release fallback embeds the build
# machine's absolute scratch path in the executable.
bundle="$src_dir/Sources/KWWKAI/Resources"
[[ -d "$bundle" ]] || { echo "error: source tree has no resource directory at $bundle" >&2; exit 65; }
for resource in models.json cursor-models.json; do
    [[ -f "$bundle/$resource" ]] || {
        echo "error: resource bundle is missing $resource" >&2
        exit 65
    }
done

payload="$scratch_dir/payload"
rm -rf -- "$payload"
mkdir -p "$payload"
# The program is named here, once, so packaging stays a straight copy. The
# sidecar keeps its established name because that is what the lookup asks for.
/usr/bin/ditto "$executable" "$payload/$KK_PROGRAM"
/usr/bin/ditto "$bundle" "$payload/${KWWK_PRODUCT}_KWWKAI.bundle"

# Swift back-deployment libraries. Targeting an OS older than the one whose
# runtime carries a given stdlib type makes the compiler autolink a shim for it
# — at iOS 15 that is libswiftCompatibilitySpan, because swift-nio and
# swift-collections use OutputSpan, which only reached the OS stdlib much
# later. The linker already gave the executable an @loader_path rpath, so the
# shim just has to sit beside it; nothing extra is needed at link time.
#
# Resolved from the toolchain rather than hardcoded: the directory carries the
# Swift version that introduced the shim (swift-6.2/), so it moves.
shopt -s nullglob
for dependency in $(otool -L "$payload/$KK_PROGRAM" | tail -n +2 | awk '{print $1}' | grep '^@rpath/'); do
    library="${dependency#@rpath/}"
    candidates=("$toolchain"/lib/swift-*/iphoneos/"$library")
    if ((${#candidates[@]} == 0)); then
        echo "error: $KK_PROGRAM needs $library and the toolchain does not ship it" >&2
        echo "       looked in $toolchain/lib/swift-*/iphoneos/" >&2
        exit 65
    fi
    # Newest Swift version wins if the toolchain ships several.
    source_library="$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n1)"

    # The shims ship fat; thin to the one architecture that is being packaged so
    # the .deb does not carry a slice no target device runs.
    lipo -thin "$KK_ARCH" "$source_library" -output "$payload/$library" 2>/dev/null ||
        /usr/bin/ditto "$source_library" "$payload/$library"
    chmod 0755 "$payload/$library"

    library_minos="$(vtool -show-build "$payload/$library" 2>/dev/null | grep -m1 -E '^ *minos' | awk '{print $2}')"
    echo "  bundled $library (iOS $library_minos minimum) from $(basename "$(dirname "$(dirname "$source_library")")")" >&2

    # A shim that itself needs something relocatable would need its own payload
    # entry, and there is no reason for one to.
    otool -L "$payload/$library" | tail -n +2 | awk '{print $1}' | grep -q '^@' && {
        echo "error: $library has relocatable dependencies of its own" >&2
        exit 65
    }
done
shopt -u nullglob

# Nothing may be left unresolved: every @rpath entry must now have a file in the
# payload, because @loader_path is the only rpath that points anywhere the
# package installs.
while read -r dependency; do
    case "$dependency" in
    @rpath/*)
        [[ -f "$payload/${dependency#@rpath/}" ]] || {
            echo "error: unresolved dependency $dependency is not in the payload" >&2
            exit 65
        }
        ;;
    @*)
        echo "error: $KK_PROGRAM has a dependency no rpath can resolve: $dependency" >&2
        exit 65
        ;;
    esac
done < <(otool -L "$payload/$KK_PROGRAM" | tail -n +2 | awk '{print $1}')

{
    echo "built $KK_PROGRAM: $architectures, iOS $KK_MIN_IOS minimum, $(
        du -h "$payload/$KK_PROGRAM" | cut -f1 | tr -d ' '
    )"
    echo "payload ($(du -sh "$payload" | cut -f1 | tr -d ' ') total):"
    (cd "$payload" && find . -maxdepth 1 -mindepth 1 | sed 's|^\./|  |')
    echo "system dependencies:"
    otool -L "$payload/$KK_PROGRAM" | tail -n +2 | awk '{print "  " $1}'
} >&2

printf '%s\n' "$payload"
