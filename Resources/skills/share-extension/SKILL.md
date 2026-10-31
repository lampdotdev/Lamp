---
name: share-extension
description: A share extension (Share/) that puts the app in the person's share sheets and takes in links, text, pictures and files without opening it - ShareView, LampShare in the app, signing, and what to tell the person. Read before writing or changing anything in Share/.
---

# A share extension

Write Share/ShareView.swift: `struct ShareView: View { let items: [LampShare.Item]; var body: some View {
LampShareSheet(items: items) } }` shows what's shared with Cancel and Save; a view of your own (a note, a list to file
it in) ends with `LampShare.send(items)` or `LampShare.cancel()`. No `@main` there: Lamp builds the folder as a small
separate program with Share/LampShareSupport.swift, which Lamp writes (never edit it), and nothing from Sources/.

In the app, at launch, `LampShare.onReceive { items in … }` gets each share once, also those made while it was closed:
`item.kind` (.text, .link, .image, .file), `item.text`, `item.url`, `item.name`, `item.image`, `item.data`; save what
you keep there, as the files go after.

You can't open a share sheet: check that it builds, and tell the user in a sentence that the app is in their share
sheet.

- On a Mac it needs Lamp to sign the app for the user's Apple team (`look_at_app` says when it can't), and macOS keeps
  a new one off until the user turns it on once: Edit Extensions… at the foot of a Share menu.
- In an app for the Mac and iPhone it is the iPhone half's: the Mac half has none.
