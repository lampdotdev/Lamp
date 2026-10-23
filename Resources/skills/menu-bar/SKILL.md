---
name: menu-bar
description: A Mac app that lives in the menu bar (LampMenuBar) - a panel, a menu, or one thing the icon turns on and off, with its Settings and Quit, Lamp's wand, and how it stays within reach. Read before writing or changing a menu bar app or a menu bar icon.
---

# A Mac app in the menu bar

Use `LampMenuBar` from LampSupport.swift as the app's scene, instead of `MenuBarExtra`:
`LampMenuBar("Focus Timer", systemImage: "timer") { PanelView() }`, or `LampMenuBar { PanelView() } label: { … }` for
an icon or text that changes, with `.commands { LampCommands() }` on it and a `Settings` scene beside it.

It gives the app an icon with a panel and no Dock icon, and keeps it within reach: it opens the panel as a normal
window when the icon is hidden (a full menu bar, the notch), shows the panel when the app is opened again, and puts
the app in the Dock while one of its windows is open. So never call `NSApp.setActivationPolicy` or add a window just
to make the app reachable.

## The panel

- Such an app has no Dock icon and no menus, so the panel needs its own Settings button, which calls
  `LampMenuBar.openSettings()` (never `SettingsLink` or `openSettings`: from a menu bar app those open the window
  behind other apps, where it gets lost), and its own Quit button (`NSApp.terminate(nil)`).
- `LampMenuBar.close()` closes the panel after an action in it.
- Put `LampPanelWand()` beside the panel's own buttons, at the right of its header (or of its footer, beside Settings
  and Quit, when the header has none), as a window has Lamp's wand in its title bar (without it, Lamp gives it a
  strip of its own above the panel).
- Give the panel a fixed width, and hand it its model inside the braces (`{ PanelView().environmentObject(model) }`),
  never with a modifier on the scene, which crashes the panel.
- Pass `dockIcon: true` only when the app also has a main window.

## A menu, or a switch

- For a menu instead of a panel: `LampMenuBar(menu: "Clipboard", systemImage: "list.clipboard") { Button(…);
  Toggle(…); Divider() }`, which adds Settings… and Quit itself (`settings: false` when there's no Settings scene).
- For one thing the app turns on and off: `LampMenuBar("Keep Awake", isOn: $model.awake, on: "cup.and.saucer.fill",
  off: "cup.and.saucer") { more menu items }`, where a click flips it and a right-click shows the menu; keep that
  state in the App (@StateObject or @State) so the icon follows it.
