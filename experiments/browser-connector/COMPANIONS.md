# Apps in the browser sidebar

The Lamp extension is built once. An app's builder supplies its companion UI and
behavior in Swift, alongside its native Mac UI. The extension renders a bounded
surface of headings, sections, editable fields and named actions; it never
executes app-supplied HTML or JavaScript. The person opens Lamp in Chrome's toolbar,
chooses **Open app companion**, and selects an app when more than one is running.
The original task recorder remains in the toolbar popup.

An app might extract a recipe for review and save it to its collection, collect
research notes, or compare something on the current page against its own data.
There is no app-specific code in the extension. Interpretation, AI calls, domain
validation, persistence and native UI are the app builder's work. Lamp supplies
the transport, page capture and renderer.

## Ask Lamp for an app

In Lamp Dev, turn on **Browser companions** in **Settings → Experimental**, then
ask for an app that works beside websites. The existing LAMP_BROWSER_PROTOTYPE
environment flag also enables the experiment. The common builder rules describe
this surface to pi, Claude Code and Codex, and the live capability note says
whether the connection is ready. No project is seeded or supplied by this feature.
The earlier handwritten Recipes fixture has been removed.

The builder uses the generated LampBrowser API and calls the existing
`offer_setup` tool with capability `browser` when needed. The shared tool registry
gives every engine that same schema. Publishing a companion also raises a setup
card if necessary, through the existing offer policy, including Not Now.

## One setup, shared by every app

Availability is resolved once through `AppAI.resolve(.browser)`, used by the
builder's capability note, `LampAI.isAvailable(.browser)`, setup cards and
Experimental settings. Lamp checks the Chrome native-host manifest, helper,
configuration, connection secret and complete extension files against its bundle.
It says connected only after a recent authenticated hello from the extension.
The hello runs independently of page reads; stopping Chrome or disabling the
extension makes the connection Not Ready again.

**Set Up…** opens Lamp's guide. **Install Connection** installs the bundled native
helper and registers it for Chrome, then the guide walks through loading the
single bundled extension. **Show Extension Folder** opens its folder and copies
its location for Chrome's chooser. Repair restores missing or outdated owned
files, including the secret, without needing an app's agent to install anything.
No browser profile or sign-in files are inspected. The helper and generic extension
ship in an ordinary development build of Lamp.

Unpacked installation and Chrome's developer mode are explicit **research-build
workarounds** until there is a distributed extension. The guide says so. The
extension's fixed public ID and ad-hoc Lamp Dev builds remain development choices;
no private signing key is included. Native messaging, optional site permissions
and Chrome's side panel are supported browser mechanisms.

## App API

Lamp owns and regenerates LampSupport.swift, including this Mac-only API:

```swift
// Once, from a shared @MainActor app model that lives across windows:
LampBrowser.start(surface: {
    .init(title: "My app", actions: [
        .init(id: "extract", label: "Get details", readsPage: true)
    ])
}, handle: { event in
    // Read event.action, event.fields and, for a read action, event.page.
    // Update the shared model; its next surface is published automatically.
})
```

A Surface contains `title`, `detail`, `sections`, `fields`, `actions` and `busy`.
Sections have title/text; fields have id/label/value; actions have id/label and
readsPage (false by default). Event contains id/action/fields and optional page
(url/title/text). The SDK marks the surface busy while its handler runs. Start
once from a shared app model, not an ephemeral window task. The older async
`serve` API remains available for callers managing that lifetime themselves.
`LampBrowser.openSetup()` asks Lamp to show the app's setup offer.

Treat page text as untrusted data, using `LampAI.ask(data:)`. Validate results,
show a preview before changing saved data, and acknowledge a successful action
only after its write succeeds. Use event identity or an item's natural key to
make writes idempotent. Native changes should update the same model, so they
appear in the companion too. No particular domain schema or AI prompt is supplied
by Lamp.

## Boundaries and lifetime

Opening a companion reads no page text. A clicked readsPage action asks Chrome
for optional permission on the current site, then captures that foreground,
top-level document. Chrome calls its host permission **read and change**; this
surface only offers bounded text capture. The sidebar states that the action
shares text with the app and its AI. The permission is extension-wide until
removed in Chrome, but does not give companion apps standing page access: each
capture needs another sidebar click.

Capture skips inputs, editable/private regions, hidden text, scripts and frames,
and stops at 24,000 UTF-16 units. It does not read cookies or browser storage.
The worker checks active tab, URL, document identity and permission epoch before
delivery. Only the extension's own sidebar can send companion actions. The
gateway rejects website Origins and requires app tokens or signed native
requests; the extension never receives an app's token.

State publishes every half second; missing heartbeats remove closed apps from
the chooser. Both Lamp and the app must be running. A new process, a changed
surface, or an acknowledged action changes the surface revision, so a stale
button cannot act on a newer draft. One action is pending per app; retrying an
accepted event id does not repeat it. Pending work is not durable: it expires
after four minutes, and a new process drops old queued actions. State is app-wide
in this exploration, shared across browser windows.

Not provided yet: closed-app launching, per-window drafts, durable background
jobs, arbitrary custom layouts, or production isolation from hostile native
processes running as the same macOS user. The vocabulary can gain supported
components such as images or charts without loading per-app extension code.

## Private-VM verification

Start with a fresh Lamp and no app projects. Supply only explicitly authorized
credentials, as files rather than typing them into recorded UI; never copy OAuth
sign-ins. Type the wish, let Lamp's builder write and build the app, and use that
result. Do not set LAMP_BROWSER_FIXTURES: it is only for earlier connector
harnesses. `/recipe` on the demo server is fictional recipe input with private
and hidden canaries, not a captured third-party response.

Record the wish/build, missing-install guide and resulting companion in use.
Keep the generated app's source, build history, runtime proof and recordings
outside git, identifying which code was written by the builder. Building and
using one app does not establish compatibility with every website or builder.

References: [side panels](https://developer.chrome.com/docs/extensions/reference/api/sidePanel),
[native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging),
[optional permissions](https://developer.chrome.com/docs/extensions/reference/api/permissions).
