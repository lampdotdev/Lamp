Kind: tool.
Look: a soft sky of blue, violet and peach glowing behind the catalog (`Theme`, `SkyBackdrop`), rounded bold headings,
white glass cards with each site's real logo on a white tile, and a glossy sky-to-violet capsule for the main button
(`GlowButtonStyle`). The empty catalog shows a glass picture of a browser window turning into an app icon
(Assets/hero.png). Site windows are the page alone, edge to edge.

# Site-to-App

Turns websites that have no Mac app (Google Meet, Gmail, Intercom…) into minimal apps of their own. The catalog is a
grid of the person's sites; each opens in a window with no title bar, and each can be made into its own Dock app in
~/Applications that opens only that site.

- **Adding a site** (`AddSiteView`): an address and a name (suggested from the address). The catalog offers sites to
  start with: the ones the person visits most in their browsers (`BrowserHistory`, read on this Mac only), or, with no
  history to read, a fixed list (`SiteSuggestion.all`). Sites whose makers have a Mac app of their own
  (`SiteSuggestion.hasDesktopApp`: Slack, Notion, Zoom…) are never suggested. The fixed list's logos come from
  Google's favicon service; a suggestion from the person's browsing asks only the site itself (`FaviconCache`), so
  where they go is never sent to anyone else.
- **A site's window** (`SiteWindowView`, `WebModel`, `WebView`): a WKWebView filling the window, with its own
  cookies and storage for each site (a `WKWebsiteDataStore` per site id), Safari's user agent, and the camera and
  microphone allowed without asking for the site's own origin only (its scheme, host and port); any other page asks. The traffic lights and a slim bar come in only while the mouse moves
  near the top (`WindowChrome`), and the bar drags the window. A hairline shows loading. Links that open a new tab on
  another domain go to the default browser; a page's popups (sign-in) get a small window of their own (`WebDelegate`).
  Downloads go to ~/Downloads. A count in the page's title ("(3) Inbox") becomes the Dock badge in a site's own app.
- **Links** (`LinkPill`): when a site's window comes forward with a link to that site on the clipboard, a pill offers to
  open it there. File ▸ Open Link… (⌘L) takes a link or a bare path or code (a Meet code).
- **Dock apps** (`AppMaker`): a copy of this app's own bundle with its Info.plist rewritten (its own bundle id, the
  site's name, `LampSiteURL`, `LampSiteName`, `LampSiteID`, its own data id, the site's icon as SiteIcon.icns), with
  Lamp's chat extension and signature taken out, signed ad hoc for this Mac and registered with Launch Services. At
  launch `SiteMode.site` reads those keys: the copy then shows only that site, and has no wand.
- **Menus** (`PageCommands`): Open Link… ⌘L, Copy Link ⇧⌘C, Open in Browser ⌥⌘B, Reload ⌘R, Back ⌘[, Forward ⌘],
  Home ⇧⌘H, and zoom (⌘+, ⌘-, ⌘0, kept per site).

## Code

- `Sources/App.swift`: the catalog window (or, in a site's own app, that site) and a window group for site windows.
- `Sources/CatalogView.swift`: the catalog grid, the empty state with the hero picture, suggestions, the made-app banner.
- `Sources/AddSiteView.swift`: the sheet for adding a site.
- `Sources/Site.swift`: `Site` (name, address, icon file, where its Dock app is), `SiteSuggestion`, `SiteMode`.
- `Sources/Library.swift`: the one model: the sites, kept with LampStore, and their icons.
- `Sources/SiteIcon.swift`: finds a site's icon (its touch icon, its `<link>` icons, else Google's favicon service) and
  draws it on a Mac app tile; makes the .icns for a Dock app.
- `Sources/SiteWindowView.swift`, `WebModel.swift`, `WebView.swift`: a site's window, its web view and what the page
  may do (new windows, permissions, downloads, the badge).
- `Sources/WindowChrome.swift`: the hidden title bar and the bar that comes in when the mouse moves.
- `Sources/LinkPill.swift`, `PageCommands.swift`: the link pill and Open Link…, and the menus.
- `Sources/AppMaker.swift`: making, revealing and checking for a site's Dock app.
- `Sources/BrowserHistory.swift`: the most visited sites in Chrome, Arc, Brave, Edge, Vivaldi, Chromium and (when the
  app may read it) Safari over the last 60 days, read from a copy of each history file.
- `Sources/Theme.swift`, `Buttons.swift`: the sky, colors and button styles.

## Data

LampStore collection "sites" (`Site`), and each site's icon as a PNG in LampStore.folder/Icons. A site's page zoom is
in UserDefaults. Each site's cookies and sign-ins are in its own WebKit data store. The catalog starts empty; the
suggestions are the example content.

## Easy to change

- The sites offered to start with: `SiteSuggestion.all`; the ones never offered: `SiteSuggestion.hasDesktopApp`.
- The catalog's colors and sky: `Theme` and `SkyBackdrop`; its buttons: `GlowButtonStyle` in Buttons.swift.
- How a site's window looks while the mouse moves: `WindowChrome`.
- What a page may do (open windows, use the camera, download): the delegates in WebView.swift and `WebModel`.
- What a Dock app is given: the Info.plist keys in `AppMaker.build`.
