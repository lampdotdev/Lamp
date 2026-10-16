Kind: collection, drawn as a real bookcase (wooden shelves in code, books standing as spines or facing out).

# Shelves

A collection that looks like a real shelf. The window has shelves in the sidebar ("Books" to begin with; more
can be added, the first one offered as "Want to Read") and draws the chosen one as a bookcase: wooden planks
with the books standing on them as coloured spines of different heights and thicknesses, title down the spine,
and a few turned to show their cover. A book being read has a red ribbon out of its top; one lent out is a faint
outline where it stood. Clicking a book opens a card over it with its cover, title, author and year, and what
the person keeps about it: a rating, a status (want to read, reading, read, lent out with who has it), the
shelf, tags and notes. Right-click turns it cover out or spine out, moves it to another shelf, or removes it;
books can also be dragged onto a shelf in the sidebar. The toolbar adds a book (⇧⌘N) and sorts the shelf by
author (surname), by colour or by recently added; search filters the shelf by title, author, tags or borrower.

Adding a book: hold its barcode up to the Mac's camera (any camera, including an iPhone used as the Mac's
camera through Continuity Camera, picked from the camera menu), type its ISBN (10 or 13 digits), or search by
title or author. Details and covers come from Open Library (free, no key). Covers are kept in the app's data
folder; a spine takes its colour from its cover the first time the cover arrives. Without a cover or a
connection, a cover is drawn in code in the book's colour. No AI is used.

## How the code is organized

- `Sources/App.swift`: the window (default 900×600, minimum 680×440) and the menu commands (Add Book ⇧⌘N,
  New Shelf ⌥⌘N, Clear Examples). The window lends its actions to the menu through `ShelfActions`.
- `Sources/ItemKind.swift`: every word that names the kind of thing kept (Book, Books, Author, ISBN, the first
  shelf's name, the wish shelf's name, the status labels, the SF Symbol).
- `Sources/Model.swift`: `ShelfItem` (one thing on a shelf, with general fields: title, creator, year, code,
  cover, notes, rating, tags, status, lentTo, shelf, added, facesOut, look, isExample), `ItemStatus`,
  `SpineLook` (colour and size on the shelf; random when added, recoloured from the cover; the spine's ink),
  `Shelf`, `ItemDetails` (what a lookup found) and `ShelfOrder` (the three sorts).
- `Sources/Library.swift`: the one `@MainActor` model, shared through the environment. Loads and saves shelves
  and items, adds, moves, removes, Clear Examples, and fetches missing covers in the background.
- `Sources/BookLookup.swift`: the only file that knows the items are books: ISBN checking and ISBN-10 to
  ISBN-13, Open Library search by ISBN or by text, and cover addresses.
- `Sources/Covers.swift`: the cover files (download, cache, remove) and the spine colour picked from a cover.
- `Sources/Examples.swift`: the twelve example books written on first launch (real ISBNs, so covers load).
- `Sources/ContentView.swift`: the split view, sidebar of shelves (rename, take down, drop to move), toolbar,
  search, empty state, the "These are examples" line, and the new/rename shelf alert.
- `Sources/ShelfView.swift`: the bookcase: `rows(of:width:)` fills rows to the window's width, `Plank` and the
  `Wood` colours (light oak, dark walnut in dark mode), hover lift, the detail popover and the right-click menu.
- `Sources/BookViews.swift`: `StandingItem` (spine or cover, lent and reading marks), `Spine`, `CoverView` and
  `DrawnCover` (the cover drawn in code).
- `Sources/DetailCard.swift`: the card for one book, `Stars` and `TagsField`. Edits save as they're made.
- `Sources/AddItemSheet.swift`: the add sheet with its three ways in (Scan Barcode, ISBN, Search), results with
  Add buttons, "Add by Hand" when nothing is found, and the shelf to add to.
- `Sources/BarcodeScanner.swift`: the camera (AVFoundation) and barcode reading (Vision, EAN-13/EAN-8/UPC-E,
  five looks a second, the same number twice before it's believed), and `CameraPreview`, mirrored.

## Data

Everything is in LampStore: the collection "shelves" (`Shelf`) and the collection "items" (`ShelfItem`). Cover
pictures are files in `Covers/` inside LampStore's folder, named by the item's id. The window keeps the chosen
shelf and sort in `@SceneStorage`; the add sheet remembers the last way in (`addWay`).

## Examples

On the very first launch `Library` writes the "Books" shelf and the twelve books in `Examples.swift`, marked
`isExample`, and saves `examplesWritten` so they are never written again. Clear Examples (in the File menu, and
the quiet "These are examples" line under the shelf while any are on it) removes only items marked `isExample`,
with their covers; shelves and the person's own books stay.

## Easy to change

- Another kind of collection (records, games, figurines): the words in `ItemKind.swift`, a new lookup in place
  of `BookLookup.swift` returning `ItemDetails` (for records, a free source such as MusicBrainz by barcode), the
  examples in `Examples.swift`, and the size of things on the shelf in `SpineLook.random` and
  `StandingItem` (records stand square and the same height).
- Lending: `ItemStatus.lent` and `ShelfItem.lentTo`; a "lent on" date would be a new optional property.
- Look of the bookcase: `Wood` and `Plank` in `ShelfView.swift`; spines and drawn covers in `BookViews.swift`.
- Sorts: `ShelfOrder` in `Model.swift`.
