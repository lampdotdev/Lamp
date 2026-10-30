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
- Lamp's player (`Resources/LampPlayer.bundle`), the Mac app every game and screen is a copy of: `build.sh` compiles
  it afresh for a release, before the starters, and each copy is signed again as its own app when Lamp makes it
- the starters' prebuilt apps: `build.sh` has the new Lamp build each starter as a person's Mac would
  (`PrebuiltStarters.swift`), signs it and zips it into `dist/assets` (`Lamp-Starter-<starter>-<version>.zip`,
  `Lamp-Nightly-Starter-…` for a nightly), which goes up on the release beside the DMG, so a new person's starters open
  at once, before Apple's build tools are installed. Lamp's bundle carries none of them: it pins each one's address,
  size and SHA-256 (the starter's `listing/prebuilt.json`), and Lamp fetches it with the starter's tree when the
  starter is first opened, checking its signature as Lamp's own before using it (`StarterDownloads`, "Starters are
  fetched when they're first opened" in docs/development/desk.md). This adds about five minutes to a release. So a
  release's assets must be on it before anyone opens a starter: the workflows upload them with the DMG. A development
  build leaves them out (a Lamp Dev without them builds a starter once it's opened, out of sight);
  `PREBUILD_STARTERS=1 ./build.sh` builds them too, into `build/assets`, which its listing points at by file, reusing
  the ones in `.build/prebuilt-starters` while what they're made from is unchanged. The starters' trees are never in
  the bundle either: each is fetched from its public repository at the pinned commit, checked against that commit.
- `Lamp.app`, with `Resources/Lamp.entitlements` (microphone, for dictation)

Releases build into `dist/`, so they never replace the `build/Lamp.app` you run day to day. Release builds
have a Team ID, so they keep API keys in the login Keychain; local builds use `keys.json`. A release that
finds a `keys.json` in its folder (from a build from source that used to share it) moves those keys into the
Keychain and removes the file.

Apps that Lamp generates are built on the user's Mac and signed there with Lamp's own self-signed
certificate ("Lamp App Signing", see `scripts/signing-identity.sh`), or ad hoc when that can't be done.
They're never downloaded, so they don't need notarization.

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
gh release create v0.2.0 dist/Lamp-0.2.0.dmg dist/assets/* --title "Lamp 0.2.0" --notes-file notes.md
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

It builds with the Xcode named in `.github/xcode-version`, which `.github/workflows/mac-build.yml` builds and tests
every pull request with too, so code only a newer Xcode accepts fails on the pull request rather than at release.
Both run on GitHub's `xcode-27` runner image (macOS 27 with Xcode 27, a preview image for now): the Xcode the team
builds with, and the one generated apps are compiled with on their Macs. Raise the file when that image gets a newer
Xcode, and move both workflows together when GitHub makes a newer image.

The signing secrets live in the repo's **`release` environment**, which only `v*` tags can use. A ruleset
("Protect release tags") lets only repo admins create, move or delete `v*` tags, so nobody else can
trigger a signed build. The certificate owner adds the secrets once. Run these yourself; each prompts
for its value or reads the file:

```bash
gh secret set MACOS_CERT_P12_BASE64 --env release --repo lampdotdev/Lamp < <(base64 -i ~/Desktop/DeveloperID.p12)
gh secret set MACOS_CERT_PASSWORD   --env release --repo lampdotdev/Lamp   # the .p12 export password
gh secret set NOTARY_APPLE_ID       --env release --repo lampdotdev/Lamp
gh secret set NOTARY_TEAM_ID        --env release --repo lampdotdev/Lamp
gh secret set NOTARY_PASSWORD       --env release --repo lampdotdev/Lamp   # the app-specific password
```

Then move `DeveloperID.p12` into 1Password and delete it from the Desktop.

Re-run a release (e.g. to rebuild the DMG) against its tag:

```bash
gh workflow run mac-release.yml --ref v0.2.0 -f version=0.2.0
```

## Nightlies

`.github/workflows/nightly.yml` builds, signs, notarizes and publishes **Lamp Nightly** from every push to `main` (and
on demand with `gh workflow run nightly.yml`): a separate app from Lamp, with its own name, icon, bundle id, folders and
update feed ("Lamp Nightly" in docs/development/lamp-dev-and-instances.md), so people who want every change early run
it beside the Lamp they rely on. It's one rolling pre-release, tagged `nightly`: the tag moves to the commit, the
release's `sparkle.json`, title and notes are replaced each time and `Lamp-Nightly-<version>.dmg` is added with the
assets that version fetches (`dist/assets`, each named by the version), so the
release is published once and only edited after that, and whatever listens for releases (the Slack subscription) hears
of it once. The release keeps its newest three DMGs, and the assets of its newest twenty versions (an installed nightly
fetches them for as long as it runs), and the feed names the one it signed
(`/download/nightly/<file>`): the feed is cached for a quarter of an hour and an update window may stay open longer,
and the DMG an offer names must still be there to verify. The version is the last release plus the commits since it as `build.sh` names a build from source
(`0.24.0+37`), and the build number `0.24.0.37`, so Sparkle orders the nightlies among themselves. A push that is a
release tag itself makes no nightly. The notes list the commits since the last release.

Lamp Nightly updates from `https://updates.lamp.dev/nightly/appcast.xml`, which lists that release alone
(`updates/api/appcast.js`, `?stream=nightly`); Lamp's feed and the website's Download never see a nightly. The workflow
uses the `release` environment's secrets, which `main` may use as `v*` tags may; `main` is protected (pull requests and
passing checks only), so a nightly is always a reviewed change. To make one by hand: `FLAVOR=nightly ./release.sh
0.24.0+37`.

## Trying the first run

`scripts/fresh-start.sh begin` quits Lamp Dev, puts your whole setup aside (the Lamp Dev folder in
Application Support, the `dev.lamp.host.dev` defaults and any Keychain items) and opens it as a first-time
user would see it: the welcome screen, the key check, picking an engine, making the first app.
`scripts/fresh-start.sh restore` throws away what the fresh run made and puts your setup back. Nothing is
deleted until you restore. `EDITION=release scripts/fresh-start.sh begin` does the same to the installed
Lamp, which is the one you least want reset by accident, so it isn't the default.

It can't show a Mac without the Command Line Tools, Gatekeeper on a fresh download, or permission prompts
you've already answered. A second macOS user account shows the prompts; a clean VM with the release DMG
shows everything, and is worth doing once for a release that changes setup.

## Updates (Sparkle)

Release builds of Lamp update themselves with [Sparkle](https://sparkle-project.org) 2. Once a day, and from **Lamp → Check for Updates…**, Lamp reads the update feed at `https://updates.lamp.dev/appcast.xml`. When there's a newer release, Sparkle shows its standard window with the release notes and an **Install** button. Builds from source, which have no Apple Team ID, don't check for updates.

- **Signing:** every update is signed with an Ed25519 key. The release workflow runs `scripts/sparkle-sign.swift` on the DMG, using the `SPARKLE_PRIVATE_KEY` secret in the `release` environment, and attaches the result to the release as `sparkle.json`. Sparkle checks the signature against `SUPublicEDKey` in `build.sh`, and it also requires the new app to be signed by the same Developer ID team. The private key is kept in 1Password. Losing the key means shipping a new public key in a release that users install by hand.
- **The feed:** `updates/` is a small Vercel app (project `forge-updates` on the Roo Code team, served at `updates.lamp.dev`; `lamp.dev` itself is kept for the site) that keeps the repo private:
  - `/appcast.xml` builds the feed from the GitHub releases that have a `sparkle.json`, with each release's notes.
  - `/download/<tag>` redirects to GitHub's short-lived download link for that release's DMG; `/download/latest`
    picks the newest published release, which is where the website's Download button points. `/download/<tag>/<file>`
    does the same for a named DMG and for what a Lamp fetches from its own release when it needs it (a starter's
    prebuilt app, `isFetchedName`), since the repository is private.
  - It reads the releases with `GITHUB_TOKEN`, a fine-grained token with **Contents: read-only** on `lampdotdev/Lamp` only.
  - It deploys itself: the Vercel project is connected to this repo with `updates` as its root directory, so a push to `main` that touches `updates/` goes to production and a branch gets a preview, like the website in `site/`. `cd updates && vercel deploy --prod --scope roo-code` still works for a deploy by hand.
- **Only newer releases appear:** releases before the first one with `sparkle.json` aren't in the feed, because Sparkle couldn't verify them. Copies of Lamp from before Sparkle was added need one manual update to a release that includes it.

## Website

`site/` is the page at `lamp.dev`: one static Astro page styled with Tailwind, in its own Vercel project
(`lamp-site` on the Roo Code team). `lamp.dev` is registered through Vercel on that team, with its DNS there
too, and `updates.lamp.dev` belongs to `forge-updates`. The page has nothing release-specific: its Download
button goes to `https://updates.lamp.dev/download/latest`, so a new release needs nothing done here.

- Run it locally with `cd site && npm install && npm run dev`, or `npm run build && npx astro preview` for
  exactly what gets deployed (the dev server can miss styles from a page added while it's running).
- `site/vercel.json` sets the framework, caches the fingerprinted files under `/_astro/` for a year, and adds
  a few security headers. `public/og.jpg` is the 1200×630 card shown where the link is shared.
- The section under the hero that helps a visitor find a first app asks a model through OpenRouter and counts
  what people pick: its setup, model, limits and counts are in [site/FIRST_IDEA.md](site/FIRST_IDEA.md). Under
  `npm run dev` it asks the model with a key from `site/.env.local`.
- Analytics go to PostHog (`site/src/lib/analytics.ts`): page views, clicks, `download_clicked` with where the
  button sits, and the first-idea section's counts as `first_idea_<event>`. No cookies or storage, so no
  consent banner. Set `PUBLIC_POSTHOG_KEY` (the project key, which isn't secret) and, for PostHog's EU cloud,
  `PUBLIC_POSTHOG_HOST` in the Vercel project for Production only; it's read at build time, so redeploy after
  setting it. Without it the page loads no PostHog code at all. In the PostHog project, turn on **Discard
  client IP data**.
- The pictures are real windows taken from Lamp Dev with made-up data (⌘⇧4 then Space, which keeps the
  shadow): `site/src/assets/apps/` holds the app shown beside the chat that changes it. Retake it when Lamp's
  look changes.
- iPhone and iPad apps are the simulator's own screens: set the status bar and language first
  (`xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100
  --cellularBars 4 --wifiBars 3`, and `xcrun simctl spawn booted defaults write -g AppleLocale en_GB`
  then relaunch the app), take each screen with `xcrun simctl io booted screenshot --mask=alpha shot.png`,
  and put them in a frame on the same 2304×1664 canvas with `scripts/phone-frame.swift`
  (`swift scripts/phone-frame.swift out.png 1380 0.16 first.png second.png`: the device height in pixels, the
  screen's corner radius as a fraction of its width, then one or more screens side by side). The icons under
  "No localhost shenanigans" are each app's 512px icon, from `iconutil -c iconset .lamp/AppIcon.icns`.

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
