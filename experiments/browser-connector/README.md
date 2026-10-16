# Apps in Chrome's sidebar

Lamp Dev only, behind **Settings → Experimental → Apps in Chrome**. One Chrome
extension serves every app: each app's sidebar is a small web page of its own
(`Assets/Sidebar/`), which the app serves itself on this Mac, and the extension
frames it beside the page the person is on. The page has no browser powers: it
reaches the person's tab only through the extension, after a click, and its app
for everything else.

## What a person does

1. Asks Lamp for an app whose wish involves web pages ("Keep the recipes I find
   online"). The builder decides the app also gets a sidebar and says so in one
   line; nobody chooses a surface.
2. Connects Chrome once: the setup card's **Install Connection**, then **Load
   unpacked** in Chrome's developer mode (until the extension is in the Chrome
   Web Store).
3. On a page an app is for, Lamp's toolbar icon lights up (a dim icon gets its
   colour and a dot). One click opens that tab's sidebar on the fitting app, whose
   page offers to save it.
4. An app that isn't open is opened when it's chosen. Every installed app with a
   sidebar is listed, open or not. The sidebar works while the app is open,
   whether Lamp is or not (an AI answer opens Lamp in the background, as it does
   for the app's window).

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
- **A right-click item**, when the builder gives an app one (`"menu": "Save to
  Recipe Box"` in `browser.json`): Chrome lists it under Lamp in the page's
  right-click menu, and choosing it opens the tab's sidebar on that app with
  `activeTab`, as the icon does. Choosing it is the person's click for that
  app's page: the sidebar tells the proved page once (`lamp.onMenu`) and lets
  it read once without a click in it, within 15 seconds and only on the
  address the item was chosen on, so the page does what the item says at once.
  Chrome decides where an item shows from the address alone before the menu
  opens, so it shows only on pages a fit names by site (and path) without a
  selector, and Lamp refuses a menu for an app with no such fit. An app that
  fits only by selector is reached through the icon.
- **The page** is served by the app (`LampBrowser.startPage` in LampSupport.swift)
  on this Mac's own address, at a name under `.localhost` (each app its own
  origin, so one app's page can't read another's storage) and a port worked out
  from the app's id (`Template.sidebarPort`), with the next three tried when
  another program has it. Lamp lists the addresses and a key with each app
  (`surface-list`); the extension keeps that list for when Lamp is closed and
  tries the addresses in turn until the page there proves it's the app (the
  key's signature over a fresh nonce and the port, from `/lamp/proof`), and
  only then hands the page its key (`/lamp.js`). The app
  answers only its own name at the port it has (so a website that points a
  name at this Mac, or another program on the first port, gets nothing), its
  data only to calls with the key that no other site sent, and lets only the
  extension frame the page. The page's policy allows scripts only from its own
  files and connections only to its app.
- **The frame** is sandboxed (no popups, no navigating the sidebar). Above it
  the extension keeps the app's name and the consent line the page asks for
  (`data-lamp-reads`), drawn in the page's own colours, which the page
  sends (`look`) and the extension takes only as plain colours. The strip makes
  no offer: the page's own offer row is the only one.
- **The look is Apple's.** `/lamp.css` is Apple's system look for a narrow Mac
  list pane, light and dark, and the page picks one tint among Apple's system
  colours with `<html data-tint="…">`; the app stands out through that tint and
  its own items. The `chrome-sidebar` skill (`Resources/skills`) says how a page
  is built and checked. The app serves its own pictures at `/assets/<file>` and
  SF Symbols at `/symbols/<name>.png`, drawn by the app and used as masks.
- **Reading** happens only when the page's file declares it (`data-lamp-reads`,
  which Lamp reads from the file, never from the page as it runs) and the page
  asks (`lamp.readPage`, `lamp.readSelection`) right after a click in it, once
  per click: Chrome passes the click's activation up to the extension's
  sidebar, which checks it (a press on the sidebar's own parts doesn't count), then reads through
  the `activeTab` grant. After the tab moves to another page the grant is gone
  and the sidebar asks for a click on the icon again. Capture
  (`surface-capture.js`) skips fields, editable and hidden text and frames, and
  stops at 24,000 characters (`truncated`).
- **Per tab**: Chrome keeps one sidebar, and so one page, per tab, and the page
  tells its app which tab a call is from (`call.tab`), so a preview made on one
  page never shows on another.
- **Apps built before pages** publish their sidebar as data instead
  (`LampBrowser.start(surface:handle:)`, title, text, lists, fields and buttons),
  which the extension still draws, per tab with its own revision.
- **Transport**: the extension talks to Lamp through Chrome native messaging.
  `NativeHost.swift` (installed by Lamp as `BrowserNativeHost`) signs each
  message with a secret only it and Lamp can read and posts it to the gateway's
  `/browser/native`; Lamp signs its answer. Apps post `/browser/surface` with
  their token. Websites have no way in: no external or page message listeners,
  and the gateway refuses requests with an Origin.
- **The builder tries it** without Chrome: `look_at_app` and `use_app` with
  `sidebar: true` open the app's page out of sight at the sidebar's width
  (`PagePreview`), show it light, dark and at 200% zoom beside the app's front
  window, say what they measured (contrast, font, small words, missing pictures,
  sideways scrolling, words cut off, parts out of line), list its text and
  controls, and press them by target, handing
  a read the text of a real page (`page`), which Lamp opens out of sight and
  reads with the extension's own capture script; the look says whether the page
  fits `browser.json`. That reader connects only through `PublicOnlyProxy`,
  which looks up every host itself and refuses this Mac, the local network and
  other non-internet addresses, for the page, its redirects and everything it
  loads.

## Not in this milestone

The Chrome Web Store listing, a signed and notarized helper, the sidebar in
release Lamp, a wand in the sidebar, the empty state as a new-app entry point,
and noticing pages beyond declared sites and selectors.
