# kk — Agent Notes

[kwwk](https://github.com/EYHN/kwwk) — a Swift-native coding-agent CLI — built
for jailbroken iOS 15+ and installed as `kk`, for both roothide and rootless
bootstraps.

This repository holds **no application source**. It fetches kwwk at a pinned
commit, applies `patches/`, cross-compiles, and packages. Everything runs
through `Scripts/`, so CI and a local checkout execute the same code.

## Hard rules

- **Not a fork.** Never vendor kwwk source here. Every change to it is a patch
  in `patches/`, applied by `Scripts/prepare-source.sh` to a fresh checkout of
  `KWWK_REF`. Keep patches small and single-purpose — one theme, one file group
  — because each one has to survive an upstream rebase on its own.
- **`KWWK_REF` is a full commit sha**, not a branch. `patches/` is
  context-sensitive; a moving branch turns "the build broke" into "which of the
  last twenty upstream commits broke it". Bump with `make bump-upstream REF=…`.
- **One arm64 binary backs both packages.** arm64 runs on every arm64e device
  and the reverse is not true. The two `.deb` architectures name a *bootstrap
  layout*, not a CPU: `iphoneos-arm64` is rootless, `iphoneos-arm64e` is
  roothide. Never build an arm64e slice for the "arm64e" package.
- **Never hardcode a bootstrap path in patched source.** Probe for the file and
  take the first that exists — a rootless bootstrap answers under `/var/jb`,
  while this Swift payload is not vroot-linked and uses the physical bootstrap
  PATH supplied by its launcher on RootHide. Prefix substitution belongs in
  *packaging* (`@PREFIX@`), not in Swift.
- **Versions live in `Configuration/version.txt` only**, written by
  `make set-version VERSION=x.y.z`. `X.Y.Z` tracks upstream's
  `KWWKBuild.version` so the number in the package matches the one the welcome
  card prints; `X.Y.Z-N` is a packaging-only respin of the same upstream code.
  CI sets it from the tag.
- **Never rename the provider-facing identity strings.**
  `Sources/KWWKAI/ProviderAttribution.swift` (`kwwk`, `kwwk-coding-agent`,
  `https://kwwk.dev`) and the client ids in `OAuthProviders.swift`,
  `StoredProviders.swift`, and `CursorAgentProvider.swift` are what the
  subscription providers see. Changing them risks losing the "log in with your
  existing subscription" access that is the whole point of the tool. The
  `~/.kwwk/` paths are likewise off limits: they hold the OAuth store, sessions,
  and skills, and are shared with any other kwwk install for that user.
- **The program keeps calling itself `kwwk` in its own output**, and that is
  deliberate: the usage text and the ~15 `kwwk:` error prefixes live in files
  upstream edits often, and the block wordmark literally spells k-w-w-k in ASCII
  art. The package installs `/usr/bin/kwwk` as a symlink to the `kk` launcher
  instead, which makes everything it prints true for one line of packaging. The
  symlink points at the *launcher*, never the binary — see the last gotcha.

## Layout

```
Configuration/upstream.env   pinned ref, product/program names, iOS floor, arch
Configuration/version.txt    package version
patches/NNNN-*.patch         applied in sorted order to a pristine checkout
Packaging/DEBIAN/control     control template (@PLACEHOLDER@ substituted)
Packaging/kk.entitlements    what the signed binary carries, and why
Packaging/kk.launcher.sh     /usr/bin/kk → the real binary in libexec
Scripts/prepare-source.sh    fetch + patch (idempotent, stamped)
Scripts/build-ios.sh         cross-compile, verify, assemble the payload
Scripts/package-deb.sh       stage + ldid + dpkg-deb + verify
Scripts/install-device.sh    install over SSH and smoke-test (dev only)
build/                       everything generated; not source
```

`build-ios.sh` prints a **payload directory** whose contents are exactly what
lands in `<prefix>/usr/libexec/kk`. That is the contract between building and
packaging: `package-deb.sh` copies it verbatim and knows nothing about toolchain
layout.

## Build & verify

- `make check` — script syntax, config sanity, patch set, packaging inputs
- `make source` — fetch + patch; fails loudly if a patch no longer applies
- `make build` — cross-compile and verify the Mach-O
- `make debs` — both packages plus `SHA256SUMS`; what CI releases
- `make install` — install the rootless package on an attached device and
  smoke-test it. Over USB, forward sshd first: `iproxy 4422:2222 &`

There is no simulator or host test loop: the product is a terminal program for a
jailbroken device, and the only meaningful verification is
`kk --self-test` on one. That check launches the binary, loads the resource
bundle, and parses both model catalogs — it is the cheapest thing that proves
the build is not merely well-formed.

## Gotchas that bit us

- **`--build-system native` is load-bearing**, deprecation warning
  notwithstanding. Under the default (swiftbuild) system the `-Xcc` target
  override leaks into the host tools libpng builds — libwebp pulls libpng in —
  so `pnglibconf`'s objects come out iOS while its link step still runs for
  macOS: *"building for 'macOS', but linking in object file built for 'iOS'"*.
  Removing the flag needs a real Swift SDK bundle for iOS, not a flag tweak.
- **`--triple`'s version component is advisory.** SwiftPM raises every target to
  the *package's* deployment target, so `arm64-apple-ios15.0` silently produced
  `minos 17.0` while `Package.swift` said `.iOS(.v17)`. That is what patch 0005
  is for, and why `build-ios.sh` reads `minos` back off the Mach-O instead of
  trusting the flag.
- **Four separate sysroot flags, one per stage.** Frontend (`-Xswiftc -sdk`), C
  (`-Xcc -isysroot`), *link driver* (`-Xswiftc -Xclang-linker -Xswiftc
  -isysroot`), and ld (`-Xlinker -syslibroot`). Omitting the link-driver one
  still builds — against macOS stubs, with a
  `-Wincompatible-sysroot` warning buried in the log.
- **`libswiftCompatibilitySpan.dylib` has to ship.** swift-nio and
  swift-collections use `OutputSpan`, which no shipping iOS runtime carries —
  checked on iOS 18.5: *"no such file, not in dyld cache"* — so the compiler
  autolinks the back-deployment shim at any realistic deployment target. This is
  not an iOS 15 tax, and raising the floor does not remove it. The linker
  already gives the executable an `@loader_path` rpath, so the shim only has to
  sit beside it; `build-ios.sh` resolves it out of the toolchain's
  `usr/lib/swift-*/iphoneos/` and thins it to arm64.
- **Test by installing, never by copying.** A binary copied to a user-writable
  path (`/var/mobile/...`) runs with its entitlements ignored, because the
  jailbreak's trustcache never saw it, and the first symptom is a *dylib* error:
  `file system sandbox blocked mmap()` of the shim. `dpkg -i` into the bootstrap
  is what registers the signature. `install-device.sh` exists so this is not
  re-learned.
- **iOS ships no shell.** Under rootless `/bin/sh` does not exist at all
  (`/var/jb/bin/sh` → dash). Patch 0003 probes instead of guessing.
- **iOS Foundation has no `Process` and no `homeDirectoryForCurrentUser`**
  (patches 0002, 0004). `posix_spawn` replaces the first; `NSHomeDirectory()`
  replaces the second, which is what upstream already does elsewhere. The
  browser handoff for `/login` goes through uikittools' `uiopen` — hence the
  `Depends: uikittools`.
- **`split(separator:)` with a multi-character separator is iOS 16+** (the
  `Collection` overload). A single-character literal infers `Character` and is
  ancient, so only the one multi-character call site needed patch 0006.
- **`NSLocking.withLock` is fine** — `@_alwaysEmitIntoClient` and
  `@available(iOS 8.0)`, so it back-deploys. There are 30-plus call sites; do
  not "fix" them.
- **`/usr/bin/kk` is a launcher, not a symlink.** SwiftPM's `Bundle.module`
  looks for `kwwk_KWWKAI.bundle` beside the *running* executable, so a symlink
  from `/usr/bin` sends that lookup to `/usr/bin` and the CLI starts with no
  model catalog. The bundle keeps its SwiftPM name (derived from the *package*,
  not the product) however the program is renamed.

## The OwnGoalPackages contract

[OwnGoalPackages](https://github.com/owngoal-dev/OwnGoalPackages) builds the
apt repository by scanning this repo's releases, so the release shape is an
interface:

- The newest release that is **not a draft, not a prerelease**, and whose tag
  carries no `alpha|beta|rc|pre|preview|dev|nightly|snapshot` marker is the one
  it takes. A draft release is invisible to it.
- It picks the asset whose name **ends in** `iphoneos-arm64.deb` /
  `iphoneos-arm64e.deb`, and verifies it against a `SHA256SUMS` asset listing
  bare file names.

`make debs` produces exactly those names and that digest list. Do not rename
release assets.

## RootHide signing and launcher checks

RootHide's official Developer README requires both
`com.apple.private.security.storage.AppBundles` and
`com.apple.private.security.storage.AppDataContainers`, in addition to the
platform and no-sandbox entitlements. Keep these in the executable signature
and verify the extracted signature after packaging; a correct package layout
alone does not establish access to RootHide's app-container installation path.
Source: https://github.com/roothide/Developer/blob/main/README.md

For payloads that do not use vroot, the launcher exports physical bootstrap
PATH, SHELL and default CA/browser paths. Preserve explicit CA/browser settings
and already physical or custom SHELL paths. Host launcher tests simulate the
path boundary and verify argv/exit status; they do not prove that iOS loads the
binary. Test the installed package from both zsh and fish on a RootHide device.
Do not add vroot to a payload while retaining a launcher that exports physical
paths: the filesystem view must remain consistent across the boundary.
