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
3. On any page, one click on Lamp's toolbar icon opens that tab's sidebar. On a
   page an app is for, it opens on that app, with the app's own sentence ("Save
   this recipe to Recipe Box"). The icon looks the same on every page: with many
   apps, lighting it where one fits would light it almost everywhere.
4. An app that isn't open is opened when it's chosen. Every installed app with a
   sidebar is listed, open or not. The sidebar works while the app is open,
   whether Lamp is or not (an AI answer opens Lamp in the background, as it does
   for the app's window).

## How it fits together

- **`browser.json`** at an app's root, written by the builder, says where the
  app fits: `{"offer": "…", "fits": [{"site": "…", "path": "…", "selector": "…"}]}`.
  Lamp reads it (`BrowserCompanions.Declaration`) to list the app and passes the
  fits to the extension, which uses them only when Lamp's icon is clicked (below).
  The extension reads nothing to notice a page. It keeps the `declarativeContent`
  permission only to remove, once on install or update, the page rules an earlier
  version gave Chrome to light its icon.
- **The click** on Lamp's icon (`chrome.action.onClicked`) opens a side panel
  for that tab only and grants `activeTab`. With it the worker asks whether each
  declared selector is on the page (yes or no, nothing else) to choose the app.
  The extension has no host permissions at all.
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
  the extension keeps the app's name, its offer and the consent line the page
  asks for (`data-lamp-reads`). `/lamp.css` gives the page the Mac window's
  look, which the app makes its own with its colour and its items.
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
  (`PagePreview`), list its text and controls, and press them by target, handing
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
