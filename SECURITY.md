# Security

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub's
[private vulnerability reporting](https://github.com/RooCodeInc/Lamp/security/advisories/new) on this repo.
<!-- TODO (maintainers): add a security contact email here once one exists, e.g. security@lamp.dev. -->

Say what you found, how to reproduce it, and what it lets someone do. We'll acknowledge the report within a
few days and keep you posted while it's fixed. We're glad to credit you in the release notes if you'd like.

## What's in scope

- **Lamp.app** itself, including the local HTTP endpoints it runs on your Mac (approvals, the agent's tools,
  the AI gateway) and the way it signs and installs the apps it builds.
- **Generated apps:** the files Lamp writes into every app (`LampSupport.swift` and friends, see
  `Sources/Lamp/Template.swift`), and how an app talks to Lamp and to other apps on your local network.
- **The website and update service** in `site/` and `updates/` (lamp.dev and updates.lamp.dev): bug reports,
  shared wishes, the update feed and downloads.

Bugs in the coding agents Lamp bundles or drives (pi, Claude Code, Codex, llama.cpp) belong with those
projects, unless the problem is in how Lamp runs them.

A review of all of the above as it stood when the code was published, with what each endpoint checks and what's
still to do, is in [docs/development/security-review-2026-10.md](docs/development/security-review-2026-10.md).

## How Lamp handles your data

Lamp runs on your Mac, and so does the agent. Lamp's own commands over an app's folder run in that app's
sandbox. Whether the agent's shell commands wait for your approval is a setting (**Settings → Building**: Only
when risky, Always or Never); with Only when risky, lower-risk commands run in the sandbox without asking. Files
outside an app's own folder are checked the same way whichever engine is building.

API keys stay on your Mac, in the login Keychain (release builds) or a private file (builds from source), and
are sent only to the provider they're for, with one exception: an iPhone or iPad app that uses AI away from
your Mac is given your OpenRouter key, which it keeps in the phone's Keychain. **Help → AI & Privacy** inside
Lamp says all of this to the person using it.
