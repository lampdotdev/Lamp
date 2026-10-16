Kind: tool, with a menu bar timer beside the window.

# Hours

Time tracking that turns into invoices. A menu bar item starts a timer for a client in one click (starting
another stops the first); while one runs, the menu bar shows the client's color dot and the time so far, and the
panel under it takes a short note and has Stop. The window lists the week's time entries by day (previous and next
week in the toolbar), editable, with each client's hours and earnings for the week and the month above them; time
can be added by hand. Each client has a name, an hourly rate, a currency and a color. Make Invoice picks a client
and a month and shows the invoice as a page, with lines by day or by note, which saves as a PDF or prints. Tidy
Line Items (optional AI, through `LampAI`) rewrites the raw notes as clear invoice lines; without AI the button is
disabled with a short reason and everything else works. The person's own details for invoices (name, address,
payment details, payment terms, next invoice number) are in Settings.

## How the code is organized

- `Sources/App.swift`: the scenes (the window, default 900×600, minimum 720×460; `LampMenuBar` with
  `dockIcon: true`; `Settings`) and the Timer menu (`HoursCommands`: ⇧⌘T stop, ⇧⌘N new entry, ⌥⌘N new client,
  ⇧⌘I make invoice, Clear Examples).
- `Sources/Model/Client.swift`: `Client` (name, rate per hour, ISO currency code, color name), `ClientColor`
  (the system colors a client can have) and `Currencies` (the currency menu's list).
- `Sources/Model/TimeEntry.swift`: `TimeEntry`. The running timer is the entry whose `end` is nil; there is at
  most one.
- `Sources/Model/Profile.swift`: `Profile`, the person's own details, and the invoice number format (`INV-0001`).
- `Sources/Model/HoursModel.swift`: the one shared `@MainActor` model. Loads and saves everything, starts and
  stops the timer, works out totals (`seconds(for:in:)`, `amount(for:in:)`; the running timer counts up to now),
  deletes, and clears examples. `sheet` says which sheet the window shows, so the toolbar, menus and context
  menus all open sheets the same way. `Ticker` ticks once a second only while a timer runs, for the menu bar.
- `Sources/Model/Invoice.swift`: `Invoice.make` builds an invoice from finished entries (a running timer isn't
  billed), grouped `byDay` or `byNote`; `Invoice.months` lists the months a client has work in.
- `Sources/Model/SampleData.swift`: the examples (see below).
- `Sources/Format.swift`: how durations, hours and money are written everywhere, and week/month intervals.
- `Sources/Views/ContentView.swift`: the split view, sidebar (Time Entries, then clients with this week's
  hours), toolbar, sheets and the delete-client confirmation. The sidebar choice is kept in `@SceneStorage`.
- `Sources/Views/WeekView.swift`: the week's entries by day (`EntryRow`), the totals grid (`TotalsGrid`) and
  week navigation (kept in `@SceneStorage("weeksBack")`).
- `Sources/Views/ClientDetailView.swift`: one client's week and month totals and this month's entries.
- `Sources/Views/EntryEditor.swift`: `EntryEditor` (add or edit an entry; an end before the start means past
  midnight) and `ClientEditor`.
- `Sources/Views/InvoiceSheet.swift`: Make Invoice: client, month and grouping pickers, the page preview, Tidy
  Line Items, Print and Save as PDF (which moves the invoice number on).
- `Sources/Views/InvoicePage.swift`: the invoice page itself, black on white at US Letter width.
- `Sources/Views/InvoiceExport.swift`: the page to PDF (`ImageRenderer`), the save panel and printing.
- `Sources/Views/MenuBarPanel.swift`: `MenuBarLabel` (the icon, or dot and elapsed time) and the panel.
- `Sources/Views/SettingsView.swift`: the person's details.

## Data

Saved with LampStore: clients in the `clients` collection, entries in `entries`, the person's details as the
`profile` value. Totals and invoices are always worked out from the entries, never stored.

## Examples and Clear Examples

On first launch `SampleData.addOnce` writes three clients (Crumb & Co. Bakery and Night Shift Podcast in USD,
Studio Fern in EUR) and about five weeks of weekday entries up to now, all marked `isExample: true`. The
`examplesAdded` value records that it ran, so examples never come back. Clear Examples (Timer menu, and a link
at the foot of the week's list while examples remain) deletes the entries marked as examples and the example
clients nobody has tracked their own time for; an example client with the person's own entries is kept, unmarked.
A sample entry or client the person edits loses its mark (`HoursModel.save`), so it's theirs and stays. The person's details start empty; the invoice sheet points to Settings
until they're filled in.

## Easy to change

- Invoice look and contents: `InvoicePage` (header, table columns, footer wording). A logo would be an image
  file kept in `LampStore.folder`, its name in `Profile`, drawn in `InvoicePage.header`.
- Invoice lines and rounding: `Invoice.lines(for:grouping:rate:)`; rounding each entry would go there and in
  `TimeEntry.duration` if totals should match.
- Invoice number format and payment terms: `Profile`.
- Client colors and currencies: `ClientColor`, `Currencies.common`.
- What the menu bar shows: `MenuBarLabel`; the panel's layout: `MenuBarPanel`.
- Reminders (such as no timer running): `LampSchedule` plus `LampNotifications`, started from `HoursModel`.
