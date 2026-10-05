# Releasing Forge

A release is a signed, notarized `.dmg` on GitHub Releases. Anyone on macOS 14+ with Apple Silicon can
download and open it without Gatekeeper warnings. On first launch, Forge installs Apple's Command Line
Tools if needed.

## What gets signed

`release.sh` runs `build.sh` with a Developer ID identity, which switches signing to hardened runtime with
a secure timestamp. Nested code is signed first:

- llama.cpp's server and libraries (`Resources/llama/`)
- pi's native module and the pi executable, with `Resources/pi.entitlements`: pi is Bun-compiled, and Bun's
  JIT needs `allow-jit` and friends under hardened runtime
- `Forge.app`, with `Resources/Forge.entitlements` (microphone, for dictation)

Releases build into `dist/`, so they never replace the `build/Forge.app` you run day to day. Release builds
have a Team ID, so they keep API keys in the login Keychain; local builds use `keys.json`.

Apps that Forge generates are built on the user's Mac and ad-hoc signed. They're never downloaded, so they
don't need notarization.

## One-time setup

### 1. Developer ID certificate

Requires an Apple Developer Program membership. Only the team's **Account Holder** can create Developer ID
certificates. In Xcode → Settings → Accounts, sign in, select the team → **Manage Certificates…** → **+** →
**Developer ID Application**. Check it with:

```bash
security find-identity -v -p codesigning
```

**Back up the private key.** In Keychain Access → My Certificates, right-click the certificate → Export,
and save the `.p12` with a strong password somewhere safe (e.g. 1Password).

### 2. Notarization credentials

At [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → **App-Specific Passwords**,
generate one, then store it in your keychain. Run this yourself; it prompts for the password:

```bash
xcrun notarytool store-credentials forge-notary --apple-id <your-apple-id> --team-id <TEAM_ID>
```

If you already have a profile from another app (such as Local's `local-assistant-notary`), reuse it with
`NOTARY_PROFILE=local-assistant-notary`.

## Release from your Mac

```bash
./release.sh 0.2.0
gh release create v0.2.0 dist/Forge-0.2.0.dmg --title "Forge 0.2.0" --generate-notes
```

`release.sh` builds and signs, then notarizes twice with Apple (each usually 2 to 10 minutes). First it
notarizes the app and staples its ticket, so Forge.app opens without a network check even after it's
copied out of the DMG. Then it packages a drag-to-Applications DMG, notarizes and staples that, and
verifies both with Gatekeeper. `SKIP_NOTARIZE=1` stops after the signed DMG,
which is useful for checking signing without submitting to Apple.

## Version numbers

A release's version is its tag: `v0.3.1` builds Forge 0.3.1. Nothing bumps it automatically; the person
tagging picks the next number.

A local `./build.sh` takes its version from git, so it says which release it's ahead of: `0.3.1` on the
tag itself, `0.3.1+6` six commits later. Without git or without the tags fetched it falls back to `0.1`.

## Release from CI

`.github/workflows/mac-release.yml` builds, signs, notarizes and publishes on every `v*` tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The signing secrets live in the repo's **`release` environment**, which only `v*` tags can use. A ruleset
("Protect release tags") lets only repo admins create, move or delete `v*` tags, so nobody else can
trigger a signed build. The certificate owner adds the secrets once. Run these yourself; each prompts
for its value or reads the file:

```bash
gh secret set MACOS_CERT_P12_BASE64 --env release --repo RooCodeInc/Forge < <(base64 -i ~/Desktop/DeveloperID.p12)
gh secret set MACOS_CERT_PASSWORD   --env release --repo RooCodeInc/Forge   # the .p12 export password
gh secret set NOTARY_APPLE_ID       --env release --repo RooCodeInc/Forge
gh secret set NOTARY_TEAM_ID        --env release --repo RooCodeInc/Forge
gh secret set NOTARY_PASSWORD       --env release --repo RooCodeInc/Forge   # the app-specific password
```

Then move `DeveloperID.p12` into 1Password and delete it from the Desktop.

Re-run a release (e.g. to rebuild the DMG) against its tag:

```bash
gh workflow run mac-release.yml --ref v0.2.0 -f version=0.2.0
```

## Updates (Sparkle)

Release builds of Forge update themselves with [Sparkle](https://sparkle-project.org) 2. Once a day, and from **Forge → Check for Updates…**, Forge reads the update feed at `https://forge-updates.vercel.app/appcast.xml`. When there's a newer release, Sparkle shows its standard window with the release notes and an **Install** button. Builds from source, which have no Apple Team ID, don't check for updates.

- **Signing:** every update is signed with an Ed25519 key. The release workflow runs `scripts/sparkle-sign.swift` on the DMG, using the `SPARKLE_PRIVATE_KEY` secret in the `release` environment, and attaches the result to the release as `sparkle.json`. Sparkle checks the signature against `SUPublicEDKey` in `build.sh`, and it also requires the new app to be signed by the same Developer ID team. A local backup of the private key is in `~/Library/Application Support/Forge/Signing/sparkle-private-key` on Matt's Mac; keep a copy in 1Password. Losing the key means shipping a new public key in a release that users install by hand.
- **The feed:** `updates/` is a small Vercel app (project `forge-updates` on the Roo Code team) that keeps the repo private:
  - `/appcast.xml` builds the feed from the GitHub releases that have a `sparkle.json`, with each release's notes.
  - `/download/<tag>` redirects to GitHub's short-lived download link for that release's DMG.
  - It reads the releases with `GITHUB_TOKEN`, a fine-grained token with **Contents: read-only** on `RooCodeInc/Forge` only.
  - Deploy with `cd updates && vercel deploy --prod --scope roo-code`.
- **Only newer releases appear:** releases before the first one with `sparkle.json` aren't in the feed, because Sparkle couldn't verify them. Copies of Forge from before Sparkle was added need one manual update to a release that includes it.
