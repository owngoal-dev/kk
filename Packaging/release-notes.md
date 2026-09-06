[kwwk](https://github.com/EYHN/kwwk) — a Swift-native coding-agent CLI — built for jailbroken iOS and installed as `kk`.

## Which one do I download?

The architecture field names the **bootstrap layout, not the CPU**. Both packages carry the same arm64 binary.

| your bootstrap | download |
| -------------- | -------- |
| rootless (Dopamine, palera1n rootless) | `@PACKAGE_ID@_@VERSION@_iphoneos-arm64.deb` |
| roothide (RootHide Dopamine) | `@PACKAGE_ID@_@VERSION@_iphoneos-arm64e.deb` |

Not sure? Ask the device: `dpkg --print-architecture`.

Requires **iOS @MIN_IOS_MAJOR@ or later** and a bootstrap that provides a shell. Or just add the [OwnGoal Studio repository](https://github.com/owngoal-dev/owngoal-packages) and let your package manager pick.

## Usage

Run `kk` in a terminal on device, then `/login` to sign in — an Anthropic, ChatGPT (Codex), Copilot, Cursor, Kimi, Grok, Z.AI, or OpenRouter subscription, or an API key for any OpenAI-compatible endpoint. `/help` lists the slash commands.

It is installed as `kwwk` too, which is the name it uses in its own help text.

## About this build

Upstream [`EYHN/kwwk@@UPSTREAM_SHORT@`](https://github.com/EYHN/kwwk/commit/@UPSTREAM_REF@), plus the patches that port it to iOS — the TUI is gated to macOS/Linux upstream, iOS Foundation ships no `Process`, a rootless bootstrap has no `/bin/sh` at all, and the deployment target has to come down to reach the jailbreaks' floor. See [`patches/`](https://github.com/owngoal-dev/kk/tree/@TAG@/patches).

Verify your download against `SHA256SUMS`.

**Full changelog**: https://github.com/owngoal-dev/kk/commits/@TAG@

This packaging revision updates RootHide compatibility checks and signing.
CLI startup passes bootstrap paths to payloads that use the physical filesystem;
RootHide virtual-filesystem utilities retain their official import rewriting.
RootHide device validation is pending; a successful build is not a claim that
all interactive runtime paths have been tested.
