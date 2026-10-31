---
name: finder-files
description: A Mac app that takes files or folders from Finder - dropped on its icon, Open With, a Quick Action - with what it declares in capabilities.json, how to try it, and Quick Actions that survive a move. Read before writing any of it.
---

# Files and folders from Finder

An app that takes files or folders from Finder (dropped on its icon, Open With, a Quick Action) says what it opens in
`capabilities.json` at the app's root: `{"opens": ["folder", "png", "public.image"]}`, with "folder", "file" for any
file, file extensions or type identifiers. Lamp declares them for the app; without that macOS hands it nothing. It is
only ever offered for a kind another app opens, never put in that app's place; a kind nothing else opens (your own
extension) is the app's to open.

To try it, make test files in the app's folder or a temporary folder and hand them over with the `open` command
`look_at_app` then gives you, which does what Finder does.

A Finder Quick Action is a workflow the app writes into ~/Library/Services, and it stores the app's full path: it
stops working when the app is moved or renamed, until the app runs again and rewrites it. So have the app write it at
every launch from `Bundle.main.bundlePath`, never once.
