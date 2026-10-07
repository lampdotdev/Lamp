# Releasing Lamp

A release is a signed, notarized `.dmg` on GitHub Releases. Anyone on macOS 14+ with Apple Silicon can
download and open it without Gatekeeper warnings. On first launch, Lamp installs Apple's Command Line
Tools if needed.

## What gets signed

`release.sh` runs `build.sh` with a Developer ID identity, which switches signing to hardened runtime with
a secure timestamp. Nested code is signed first:

- llama.cpp's server and libraries (`Resources/llama/`)
- pi's native module and the pi executable, with `Resources/pi.entitlements`: pi is Bun-compiled, and Bun's
  JIT needs `allow-jit` and friends under hardened runtime
- `Lamp.app`, with `Resources/Lamp.entitlements` (microphone, for dictation)

Releases build into `dist/`, so they never replace the `build/Lamp.app` you run day to day. Release builds
have a Team ID, so they keep API keys in the login Keychain; local builds use `keys.json`. A release that
finds a `keys.json` in its folder (from a build from source that used to share it) moves those keys into the
Keychain and removes the file.

Apps that Lamp generates are built on the user's Mac and ad-hoc signed. They're never downloaded, so they
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

### 3. Sparkle signing key

Updates are signed with an Ed25519 key (see **Updates** below). The release workflow needs it as the
`SPARKLE_PRIVATE_KEY` secret in the repository's `release` environment; generate a new pair only when
starting from nothing, because a new public key has to ship in a release people install by hand.

## Release from your Mac

```bash
./release.sh 0.2.0
gh release create v0.2.0 dist/Lamp-0.2.0.dmg --title "Lamp 0.2.0" --notes-file notes.md
```

The notes are what people read in the update window: write the version's section in `RELEASE_NOTES.md`
before tagging (the workflow takes it from there), or pass your own file here. Never GitHub's generated
list of pull requests.

`release.sh` builds the release flavor (`FLAVOR=release`: the name Lamp, the `dev.lamp.host` bundle id, the update feed; `build.sh` on its own makes Lamp Dev) and signs, then notarizes twice with Apple (each usually 2 to 10 minutes). First it
notarizes the app and staples its ticket, so Lamp.app opens without a network check even after it's
copied out of the DMG. Then it packages a drag-to-Applications DMG, notarizes and staples that, and
verifies both with Gatekeeper. `SKIP_NOTARIZE=1` stops after the signed DMG,
which is useful for checking signing without submitting to Apple.

The DMG's window (Lamp, an arrow and Applications over a night sky) is laid out by
[dmgbuild](https://github.com/dmgbuild/dmgbuild), which `release.sh` installs into a throwaway virtualenv,
from `scripts/dmg-settings.py`. Its background is `Resources/DMG/background.tiff`; after changing the
picture (`Resources/DMG/sky.png`) or the icons' positions, run `swift scripts/dmg-background.swift` to draw
it again.

## Version numbers

A release's version is its tag: `v0.3.1` builds Lamp 0.3.1. Nothing bumps it automatically; the person
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
gh secret set MACOS_CERT_P12_BASE64 --env release --repo RooCodeInc/Lamp < <(base64 -i ~/Desktop/DeveloperID.p12)
gh secret set MACOS_CERT_PASSWORD   --env release --repo RooCodeInc/Lamp   # the .p12 export password
gh secret set NOTARY_APPLE_ID       --env release --repo RooCodeInc/Lamp
gh secret set NOTARY_TEAM_ID        --env release --repo RooCodeInc/Lamp
gh secret set NOTARY_PASSWORD       --env release --repo RooCodeInc/Lamp   # the app-specific password
```

Then move `DeveloperID.p12` into 1Password and delete it from the Desktop.

Re-run a release (e.g. to rebuild the DMG) against its tag:

```bash
gh workflow run mac-release.yml --ref v0.2.0 -f version=0.2.0
```

## Trying the first run

`scripts/fresh-start.sh begin` quits Lamp, puts your whole setup aside (the Lamp folder in Application
Support, the `dev.lamp.host` defaults and any Keychain items) and opens Lamp as a first-time user would
see it: the welcome screen, the key check, picking an engine, making the first app. `scripts/fresh-start.sh
restore` throws away what the fresh run made and puts your setup back. Nothing is deleted until you restore.

It can't show a Mac without the Command Line Tools, Gatekeeper on a fresh download, or permission prompts
you've already answered. A second macOS user account shows the prompts; a clean VM with the release DMG
shows everything, and is worth doing once for a release that changes setup.

## Updates (Sparkle)

Release builds of Lamp update themselves with [Sparkle](https://sparkle-project.org) 2. Once a day, and from **Lamp → Check for Updates…**, Lamp reads the update feed at `https://updates.lamp.dev/appcast.xml`. When there's a newer release, Sparkle shows its standard window with the release notes and an **Install** button. Builds from source, which have no Apple Team ID, don't check for updates.

- **Signing:** every update is signed with an Ed25519 key. The release workflow runs `scripts/sparkle-sign.swift` on the DMG, using the `SPARKLE_PRIVATE_KEY` secret in the `release` environment, and attaches the result to the release as `sparkle.json`. Sparkle checks the signature against `SUPublicEDKey` in `build.sh`, and it also requires the new app to be signed by the same Developer ID team. A local backup of the private key is in `~/Library/Application Support/Lamp/Signing/sparkle-private-key` on Matt's Mac; keep a copy in 1Password. Losing the key means shipping a new public key in a release that users install by hand.
- **The feed:** `updates/` is a small Vercel app (project `forge-updates` on the Roo Code team, served at `updates.lamp.dev`; `lamp.dev` itself is kept for the site) that keeps the repo private:
  - `/appcast.xml` builds the feed from the GitHub releases that have a `sparkle.json`, with each release's notes.
  - `/download/<tag>` redirects to GitHub's short-lived download link for that release's DMG; `/download/latest`
    picks the newest published release, which is where the website's Download button points.
  - It reads the releases with `GITHUB_TOKEN`, a fine-grained token with **Contents: read-only** on `RooCodeInc/Lamp` only.
  - Deploy with `cd updates && vercel deploy --prod --scope roo-code`.
- **Only newer releases appear:** releases before the first one with `sparkle.json` aren't in the feed, because Sparkle couldn't verify them. Copies of Lamp from before Sparkle was added need one manual update to a release that includes it.

## Website

`site/` is the page at `lamp.dev`: one static Astro page styled with Tailwind, in its own Vercel project
(`lamp-site` on the Roo Code team). `lamp.dev` is registered through Vercel on that team, with its DNS there
too, and `updates.lamp.dev` belongs to `forge-updates`. The page has nothing release-specific: its Download
button goes to `https://updates.lamp.dev/download/latest`, so a new release needs nothing done here.

- Run it locally with `cd site && npm install && npm run dev`, or `npm run build && npx astro preview` for
  exactly what gets deployed (the dev server can miss styles from a page added while it's running).
- `site/vercel.json` sets the framework, caches the fingerprinted files under `/_astro/` for a year, and adds
  a few security headers. `public/og.png` is the 1200×630 card shown where the link is shared.
- The pictures are real windows taken from Lamp Dev with made-up data (⌘⇧4 then Space, which keeps the
  shadow): `site/src/assets/lamp.png` is Lamp under the headline, and `site/src/assets/apps/` holds the apps
  the carousel cycles through, each centred on a canvas of the same size so the slides line up. Retake them
  when Lamp's look changes.

**First deploy** (once): deploy the update server first, so the Download button's `/download/latest` exists,
then create the site's project from `site/` and give it the domain.

```
cd updates && vercel deploy --prod --scope roo-code
cd ../site && vercel link --scope roo-code --project lamp-site     # answer yes to create it
vercel deploy --prod
vercel domains add lamp.dev
vercel domains add www.lamp.dev                                     # then redirect www to lamp.dev in the project's Domains settings
```

**Later deploys:** `cd site && vercel deploy --prod --scope roo-code`. If the project is ever connected to the
GitHub repo instead, set its Root Directory to `site`.
