# kk

[kwwk](https://github.com/EYHN/kwwk) — a Swift-native coding-agent CLI — built
for jailbroken iOS and installed as `kk`. One arm64 build, packaged for both
**roothide** and **rootless** bootstraps.

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

From the [OwnGoal Studio repository](https://github.com/owngoal-dev/OwnGoalPackages),
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

The patches are the iOS port, and each is small enough to rebase by hand:

| patch  | why                                                                   |
| ------ | --------------------------------------------------------------------- |
| `0001` | The TUI is gated to macOS/Linux; iOS gets a real TTY from a jailbreak shell |
| `0002` | iOS Foundation has no `Process` — `posix_spawn` and `uiopen` instead   |
| `0003` | iOS ships no shell; a rootless bootstrap has no `/bin/sh` at all       |
| `0004` | `homeDirectoryForCurrentUser` is unavailable on iOS                    |
| `0005` | Lower the deployment target so the floor is the jailbreaks', not iOS 17 |
| `0006` | One `split(separator:)` call needs the iOS 16+ `Collection` overload   |

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
