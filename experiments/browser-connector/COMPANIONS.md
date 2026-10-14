# App companions in the browser

An app can put a small, useful part of itself beside a website. The person opens
Lamp in Chrome, chooses **Open app companion**, then chooses an app when more
than one is running. The original task recorder remains in the toolbar popup.

The app supplies the surface and does the work. The extension renders headings,
text sections, editable fields and named actions from a bounded JSON document.
It does not execute app-supplied HTML, JavaScript or URLs. This is a deliberate
first surface vocabulary, not an arbitrary webview. Custom layouts, images and
interactive charts would need additional supported components.

For Recipes, **Get Recipe** reads the page currently in front, sends its text to
the app's normal Lamp AI route, and returns a recipe to review. AI quotes source
lines; the app verifies them against the captured page and keeps the originals. A changed ingredient or instruction is refused instead of saved. The name can be
changed before **Save**. Save goes to the Mac app, which writes through LampStore
and reads the result back before saying **Saved to Recipes**. Removing it in the
Mac app updates the companion and makes Save available again. Saving the same
source replaces that recipe instead of adding a duplicate.

## App API

`LampBrowser` is in the generated LampSupport.swift, under `#if os(macOS)`. Start
one service for the app's lifetime, outside a window's lifetime:

```swift
Task {
    await LampBrowser.serve(surface: {
        .init(title: "My app", actions: [
            .init(id: "extract", label: "Get details", readsPage: true)
        ])
    }, handle: { event in
        // Validate event.fields and treat event.page as untrusted data.
        // Use LampAI.ask(data:) for page text. Save through the app's own storage.
        // Change the app's state; the next heartbeat publishes it to the sidebar.
    })
}
```

A `Surface` holds `title`, `detail`, `sections`, `fields`, `actions` and `busy`.
Sections have a title and text; fields have an id, label and initial value;
actions have an id, label and `readsPage` (false by default). The handler receives
an event id, action id, edited field values and, only for a read action, the page's
URL, title and bounded visible text. The bridge never accepts undeclared fields
or actions. Keep writes idempotent using event identity or the item's natural key.
The SDK keeps the surface busy while a handler runs, even when the app forgets.

The app publishes every half second through its existing authenticated Lamp
gateway. Lamp gives the extension only display data and pending action state,
never the app token. The extension uses the existing signed native-messaging
bridge. A six-second missing heartbeat removes the app from the chooser. The
prototype requires both Lamp Dev and the app to remain running; it doesn't launch
closed apps or persist a list of installed companions.

A surface revision changes after its content changes, an action is acknowledged,
or its app process/instance changes. A click carries the displayed revision, so
stale Save buttons cannot affect a newer draft. One action may be pending per
app; replies lost in transit can retry the same event id. Events aren't a durable
job queue: unacknowledged work expires after four minutes and a new app process
discards old queued actions. Apps must explicitly show recovery for longer work.
State is app-wide in this exploration; separate browser windows see the same
preview. Per-window drafts would require a separate companion session model.

## Page access

Opening a companion reads no page text. A read action requests Chrome's optional
permission for the current site and captures only that foreground top-level
document. The sidebar states that using the page sends its text to the app and
its AI. Chrome describes its underlying host permission as **read and change**;
this companion offers text capture, not website mutations. Permission remains
extension-wide until removed in Chrome; it is not standing permission for any
companion app to fetch pages. Each capture needs another sidebar click.

Capture skips inputs, editable and private regions, hidden text, scripts and
frames, and stops at 24,000 UTF-16 units. It doesn't read cookies, credentials or
browser storage. The worker checks tab identity, URL, document identity and the
permission epoch before delivery. Pages and content scripts cannot send companion
actions: only the extension's own sidebar is accepted. The gateway rejects web
origins and requires app tokens or signed native requests. The existing same-user
native-process trust limitation still applies.

## Run the exploration

Use the private-VM procedure in README.md. The fixture setup also creates Recipes
from `Recipes.swift`, through the ordinary scaffold. Open `/recipe` on the demo
server, a made-up recipe page containing a story, quantities, method and private
capture canaries. It is test input, not a recorded third-party service response.
Recipes uses real AI through `LampAI.ask`; no extraction response is hardcoded.
Choose an available local model in Lamp for an account-free run. The fixture's
Page Shelf and Other Shelf companions expose an independent click counter for
checking app selection and routing.

The bundled llama.cpp server can run a public GGUF locally in the guest. Serving
it on the existing OpenAI-compatible external-provider port is a **development
workaround** for testing without accounts; it isn't an installation flow. The
other workarounds are the existing environment flag, unpacked extension, fixed
public extension ID, fixture scaffolding, ad-hoc builds and manual native-host
registration. No exceptions to the repository build rules are required.

Not covered by this exploration: store distribution/review, other browsers,
closed-app launching, durable background jobs, arbitrary app web UI, per-profile
or per-window drafts, and production isolation between native apps running as
the same user. The AI's extraction is a draft for review, not a guarantee of
accuracy on every recipe site. Untrusted page text is fenced through LampAI's
existing data parameter.

References: [Chrome side panels](https://developer.chrome.com/docs/extensions/reference/api/sidePanel),
[native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging),
[optional permissions](https://developer.chrome.com/docs/extensions/reference/api/permissions).
