# Apps in Chrome's sidebar

Lamp Dev only, behind **Settings → Experimental → Apps in Chrome**. One Chrome
extension serves every app: each app draws its own sidebar as data (title, text,
lists, fields, buttons) in Swift, next to its Mac window, and handles the clicks.
The extension never runs an app's HTML or JavaScript.

## What a person does

1. Asks Lamp for an app whose wish involves web pages ("Keep the recipes I find
   online"). The builder decides the app also gets a sidebar and says so in one
   line; nobody chooses a surface.
2. Connects Chrome once: the setup card's **Install Connection**, then **Load
   unpacked** in Chrome's developer mode (until the extension is in the Chrome
   Web Store).
3. On a page an app is for, Lamp's toolbar icon lights up (a dim icon gets its
   colour and a dot). One click opens that tab's sidebar on the fitting app, with
   the app's own sentence ("Save this recipe to Recipe Box").
4. An app that isn't open is opened when it's chosen. Every installed app with a
   sidebar is listed, open or not.

## How it fits together

- **`browser.json`** at an app's root, written by the builder, says where the
  app fits: `{"offer": "…", "fits": [{"site": "…", "path": "…", "selector": "…"}]}`.
  Lamp reads it (`BrowserCompanions.Declaration`) to list the app and passes the
  fits to the extension, which hands them to Chrome as `declarativeContent`
  rules. Chrome matches URLs and CSS selectors itself; the extension reads
  nothing to notice a page. A selector must be one compound selector for
  something shown on the page (Chrome's rule).
- **The click** on Lamp's icon (`chrome.action.onClicked`) opens a side panel
  for that tab only and grants `activeTab`. With it the worker asks whether each
  declared selector is on the page (yes or no, nothing else) to choose the app.
  The extension has no host permissions at all.
- **Reading** happens only when a sidebar button with `readsPage` or
  `readsSelection` is clicked, through the same `activeTab` grant. After the tab
  moves to another page the grant is gone and the sidebar asks for a click on
  the icon again. Capture (`surface-capture.js`) skips fields, editable and
  hidden text and frames, and stops at 24,000 characters (`truncated`).
- **Each app's look**: a surface carries the app's `look` (its accent, its
  background and its type design, each color as it shows in light and dark).
  Lamp turns it into every color the sidebar uses, keeping text readable on
  them (`BrowserLook`), and the extension only sets those finished colors and
  one of four type designs. Without one, the color comes from the app's icon,
  which is also shown beside its name.
- **Per tab**: Chrome keeps one sidebar per tab. What's typed is kept per tab
  (`chrome.storage.session`), and the app is told which tabs are open on it and
  draws a surface for each (`LampBrowser.start(surface: { tab in … })`), so a
  preview made on one page never shows on another. Each tab's surface has its
  own revision: a button drawn on one tab can't act on another's.
- **Transport**: the extension talks to Lamp through Chrome native messaging.
  `NativeHost.swift` (installed by Lamp as `BrowserNativeHost`) signs each
  message with a secret only it and Lamp can read and posts it to the gateway's
  `/browser/native`; Lamp signs its answer. Apps post `/browser/surface` with
  their token. Websites have no way in: no external or page message listeners,
  and the gateway refuses requests with an Origin.
- **The builder tries it** without Chrome: `look_at_app` and `use_app` with
  `sidebar: true` draw the same surface in Lamp (`BrowserPreview`), list it as
  text, and press its buttons as one more tab. `page` names a real page, which
  Lamp opens out of sight and reads with the extension's own capture script, and
  the look says whether the page fits `browser.json`. That reader connects only
  through `PublicOnlyProxy`, which looks up every host itself and refuses this
  Mac, the local network and other non-internet addresses, for the page, its
  redirects and everything it loads.

## Not in this milestone

The Chrome Web Store listing, a signed and notarized helper, the sidebar in
release Lamp, a wand in the sidebar, the empty state as a new-app entry point,
richer parts (choices, images, progress), and noticing pages beyond declared
sites and selectors.
