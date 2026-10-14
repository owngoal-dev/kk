[kwwk](https://github.com/EYHN/kwwk) — a Swift-native coding-agent CLI — built for iOS on custom firmware and installed as `kk`.

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

Upstream [kwwk v@UPSTREAM_VERSION@](https://github.com/EYHN/kwwk/releases/tag/v@UPSTREAM_VERSION@) at [`@UPSTREAM_SHORT@`](https://github.com/EYHN/kwwk/commit/@UPSTREAM_REF@), which builds for iOS 15 itself, plus a packaging patch that loads the model catalogs from beside the executable. See [`patches/`](https://github.com/owngoal-dev/kk/tree/@TAG@/patches).

Verify your download against `SHA256SUMS`.

**Full changelog**: https://github.com/owngoal-dev/kk/commits/@TAG@
CLI startup passes bootstrap paths to payloads that use the physical filesystem;
RootHide virtual-filesystem utilities retain their official import rewriting.
