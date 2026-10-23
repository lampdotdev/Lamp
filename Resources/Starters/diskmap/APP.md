Kind: tool.
Look: system colours, a treemap drawn in Canvas with one colour per top-level folder (`TileColors.palette`).

# Disk Map

Shows where disk space goes. The sidebar has the places to measure (the disk, Home, mounted volumes other than read-only ones such as
disk images, and folders
added with Add Folder… or by dropping them on it), with the disk's free space at its foot. Choosing one measures
everything in it and shows:

- a path bar to jump back up,
- a two-level squarified treemap of the folder (hover for name, size and share in the status line, click to
  select, ⌘-click to add or take away one more, ⇧-click to add, double-click to open a folder or show a file,
  right-click for actions),
- a table of the folder's items with size, share and file count, selecting several the usual way.

The selection is shared by the map and the table (`DiskModel.selection`, a set).

The map and the table fill in while measuring (redrawn every 0.4 s): folders still being measured are dimmed and
show a spinner in the table, and the top of the scan has a dashed "Not measured yet" gap sized from the expected
total (the disk's or volume's used space, or the last finished total for Home and folders). Stop in the status
line keeps what was found so far. Actions, for one item or every selected one: Open (in its app, or a folder in
Finder), Show in Finder, Copy Path(s), Move to Trash (asks once for all of them with their total size; they can be
put back from the Trash). For the disk, space the scan didn't find (the system volume, snapshots, what couldn't
be read) is one "System & other volumes" item. Files under 1 MB are one "small files" item per folder, to keep
memory low.

## What it reads, and what macOS asks

It reads the person's real disk, so there's no example content: the disk is the content. It opens on Home.

- Folders macOS asks the person about before an app looks inside (Desktop, Documents, Downloads, iCloud Drive and
  other cloud drives, other apps' data in Library/Containers and Group Containers, the Music, TV, Photo Booth and
  Photos libraries: `Scanner.asksFirst`) are left
  out at first, so opening the app brings no questions. They're listed in the table with a hand and "—", and the
  status line says which weren't measured, with Measure Them, which turns on `measuresAsking` (saved) and measures
  again; macOS then asks once for each. A folder the person adds is measured whatever it is (they chose it); only
  what's inside it is skipped until then.
- What macOS keeps from apps without Full Disk Access (Mail, Messages, Safari's data…) can't be opened at all:
  those folders get a lock in the table, and the status line counts them with a link to Full Disk Access in
  System Settings.

## Code

- `Sources/App.swift`: the window and the menu commands (`DiskCommands`: Add Folder… ⌘O, Show in Finder ⇧⌘R, Move
  to Trash… ⌘⌫; the Go menu: Enclosing Folder ⌘↑, Open Selected Folder ⌘↓, Rescan ⌘R).
- `Sources/DiskModel.swift`: the one model: locations (`Location`, places, volumes, added folders), scanning state
  and progress, the expected size behind the gap (`pendingSize`, `estimatedSize`), navigation (`open`, `goUp`,
  `go(to:)`), the selection and the actions on it (`openItems`, `reveal`, `copyPath`, `trash`). Results live in
  memory only, one per location.
- `Sources/Scanner.swift`: `Node`, the tree (size, file count, children and completeness behind one lock, since the
  scanner fills it in from many threads while the window draws it; `sortedChildren` takes a snapshot), and the
  scanner: `getattrlistbulk`, which hands back many entries' name, type, device and allocated size in one call
  (a few times faster than `readdir` and a `stat` per file), parallel for the upper levels, staying on one volume,
  skipping links, counting allocated size.
- `Sources/Treemap.swift`: `TreemapLayout` (squarified), `buildTiles` (top level plus one level inside each big
  folder, and the gap), `TreemapView` (Canvas drawing, hover and clicks), `formatBytes`.
- `Sources/ContentView.swift`: the split view, the sidebar (`SidebarView`), the toolbar and the Move to Trash
  confirmation.
- `Sources/BrowserView.swift`: the path bar, the map with the status line, the item table (`ItemTable`, rows
  captured as `ItemRow` so it updates while measuring), the right-click menu (`ItemMenu`, for one item or several),
  icons and share bars.

## Data

LampStore: "folders" (the added folders' paths), "lastLocation", "totals" (each location's last finished size, for
the gap) and "measuresAsking". Nothing else is kept.

## Easy to change

- Colours of the tiles: `TileColors.palette` and `TileColors.color(for:index:)`.
- How the map is drawn (corners, labels, the gap's look): `TreemapView.draw`, `label`, `drawGap`.
- How deep the map goes and how many tiles: `buildTiles` (400 at the top, the rest one "N more items" tile; 150
  inside each, the rest left in the tile's colour; inner level only for tiles bigger than 50×44).
- What counts as a small file: `Scanner.smallFileLimit`. What the scanner records per file (dates, kinds): more
  attributes asked of `getattrlistbulk` in `Scanner.scanFolder` (read back in the order of their bits, ATTR_CMN_ERROR first), kept on
  `Node`.
- Which folders wait for Measure Them: `Scanner.asksFirst`.
- The places in the sidebar: `DiskModel.init` (`places`) and `refreshVolumes`.
