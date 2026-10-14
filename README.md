# kk

[kwwk](https://github.com/EYHN/kwwk) — a Swift-native coding-agent CLI — built
for iOS on custom firmware and installed as `kk`. One arm64 build, packaged for
both **roothide** and **rootless** bootstraps.

```
$ kk
  ╭─ kwwk v0.1.44 ─────────────────────────────────────────────────────────────╮
  │ Welcome!               │ Tips                                              │
  │                        │ /      slash commands                             │
  │ █  █ █   █ █   █ █  █  │ @path  attach a file or image                     │
  │ █ █  █   █ █   █ █ █   │ ⇧⏎     insert a newline                           │
  │ ██   █ █ █ █ █ █ ██    │ Esc    interrupt · Ctrl-C to quit                 │
  │ █ █  ██ ██ ██ ██ █ █   │                                                   │
  │ █  █ █   █ █   █ █  █  │                                                   │
  ╰────────────────────────────────────────────────────────────────────────────╯
  not signed in — run /login to pick a provider
```

## Install

From the [OwnGoal Studio repository](https://github.com/owngoal-dev/owngoal-packages),
or grab the `.deb` for your bootstrap from
[Releases](../../releases) and `dpkg -i` it:

| bootstrap | package architecture |
| --------- | -------------------- |
| rootless  | `iphoneos-arm64`     |
| roothide  | `iphoneos-arm64e`    |

The architecture field names the **bootstrap layout**, not the CPU — both
packages carry the same arm64 binary. If you are unsure which you have, ask the
device: `dpkg --print-architecture`.

Requires iOS 15 or later and a bootstrap that provides a shell. Then run `kk` in
a terminal on device and `/login` to sign in to a provider — an Anthropic,
ChatGPT (Codex), Copilot, Cursor, Kimi, Grok, Z.AI, or OpenRouter subscription,
or an API key for any OpenAI-compatible endpoint. It is installed as `kwwk` too,
which is the name it uses in its own help.

## What this repository is

Packaging, not a fork. There is no application source here: the build fetches
kwwk at a pinned commit, applies the patches in `patches/`, cross-compiles for
`arm64-apple-ios15.0`, and produces the two packages.

The iOS port itself lives upstream: since EYHN/kwwk#196 kwwk targets iOS 15 and
builds its CLI for iOS (TUI, `posix_spawn` in place of `Process`, the bootstrap
shell probe, `NSHomeDirectory()`). What is left here is packaging:

| patch  | why                                                                   |
| ------ | --------------------------------------------------------------------- |
| `0001` | Load the model catalogs from the sidecar beside the executable instead of `Bundle.module`, whose release accessor embeds the build machine's path |

`KWWK_REF` follows upstream releases: `.github/workflows/track-upstream.yml`
checks daily for a new kwwk tag, repins to it, and releases the matching kk
version when the patch still applies and the build passes.

## Build it yourself

Needs macOS with Xcode, plus `ldid` and `dpkg` (`brew install ldid dpkg`).

```sh
make check     # scripts, config, patch set
make debs      # both packages + SHA256SUMS, into build/Packages
```

To install on an attached device over USB:

```sh
iproxy 4422:2222 &
make install
```

`make help` lists the rest. `AGENTS.md` has the details that are easy to get
wrong — why the deprecated `--build-system native` flag is load-bearing, why the
Swift back-deployment shim has to ship, and why you must test by installing
rather than by copying a binary onto the device.

## Credits

kwwk is by [EYHN](https://github.com/EYHN/kwwk), MIT licensed. This repository
only packages it; the iOS patches are MIT as well.
