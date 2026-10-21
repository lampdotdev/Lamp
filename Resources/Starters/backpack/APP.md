Kind: companion, in the menu bar.
Look: system colours and SF Symbols, a backpack in the menu bar; each kind of thing to do has its own colour
(forms blue, payments green, things to bring orange, events purple, tasks grey), and red is kept for what's late.

# Backpack

A menu bar app that reads school emails in Mail and lists what they ask of the person: forms to sign, money to
send, things to bring or wear, days that are different (pajama day, early dismissal) and tasks (book a
conference). The icon is a backpack, with the number of things due in the next three days beside it when there
are any.

A click opens a panel:

- **Read My Mail**: until the person asks it to, Backpack only shows examples, under a card that says what it
  will read and that the AI they use in Lamp reads the school emails. The button reads the last two months of the
  inbox; once that has worked the examples go and Mail is checked from then on. A read that fails leaves the card
  and the examples, with why it stopped.
- **The list**, in groups: Late (in red), This Week, Coming Up, No Date. Each row has a circle to tick it off,
  the kind's symbol, the title, when it's due ("Tomorrow", "Thu", "Oct 30", "3 days late"), the child and the
  sender. A click opens the row: the sentence in the email it came from, the email's subject and date, Add to
  Reminders, Add to Calendar (when it has a date) and Delete. The same actions are on its right-click menu.
- **Done**, folded: what was ticked off in the last two weeks.

The header says when Mail was last checked, or what a check is doing ("Reading 3 of 12 school emails…"), with a
button to check now and Lamp's wand. At the foot, Settings and Quit. Once reading, it checks Mail every 15
minutes and notifies the person of what new emails ask for.

Settings has the children's first names (so each thing says who it's for), senders always read as school
(addresses, or a whole domain written "@school.org"; senders the AI was sure about are added here), senders never
read as school, how far back the first read goes (1 to 3 months), notifications, Open at Login, Clear Examples,
and Start Over (forgets the list and every email read, and reads again).

## Code

- `App.swift`: the `LampMenuBar` scene (the panel, the icon with the count) and the Settings scene.
- `Model/Todo.swift`: `Todo` (one thing to do, with its email's sender, subject, date and quote, and the ids of
  the reminder and event made from it), `Todo.Kind` (symbol, colour, name), `SeenEmail` (an email already read),
  `BackpackSettings`, and `Sender` (a sender line's name and address, and matching it against the person's lists).
- `Model/Backpack.swift`: `Backpack`, the one model: the list and its groups for the panel, ticking off (which
  ticks off the reminder too), Reminders and Calendar, clearing examples, starting over, and `check()`, run every
  15 minutes by `LampSchedule` once `settings.readsMail` is on. After the first read, what it finds is announced
  with `LampNotifications`.
- `Model/MailReader.swift`: reading Mail. New inbox emails since the last check (`LampMail.inbox(since:)`, with a
  day's overlap; emails already in `emails` are skipped) are sorted into school or not: the person's lists first,
  then the decision model (`LampAI.isTrue … each:`, on sender, subject and first lines), or the text AI forty at a
  time when there's no decision model. Each school email's whole text (`LampMail.body`) goes to the text AI
  (`LampAI.ask(as:)`) with the children's names and what's already on the list, and comes back as items. An email
  that couldn't be read isn't marked, so the next check tries it again.
- `Model/Examples.swift`: the example family (Maya and Leo at Oakwood Elementary), dated from the first launch.
- `Format.swift`: how due dates read in a row, and the look-back in words.
- `Views/PanelView.swift`: the panel: header, the Read My Mail card, the groups, Done, the examples line, footer.
- `Views/TodoRow.swift`: one row, opened and closed with a click.
- `Views/SettingsView.swift`: Settings.
- `capabilities.json`: a background app, so it opens at login and keeps checking Mail.

## Data

All in LampStore: the `todos` and `emails` collections, and the values `settings`, `lastChecked` and
`examplesAdded`. Examples are marked `isExample` and go when the person first reads their Mail or clears them;
`examplesAdded` keeps them from coming back. Nothing from the emails is kept but each one's sender, subject and
date, and the quote each thing to do came from.

## Easy to change

- What counts as school: `MailReader.question`, the thresholds in `MailReader.sort` (0.6 to count, 0.9 to
  remember the sender), and the person's lists in Settings. For another part of the inbox (a sports team, a
  club, bills), change the question, the instructions, the kinds and the examples together.
- What's pulled out of an email, and how titles are written: `MailReader.instructions` and `Found`.
- The kinds of things to do, their symbols and colours: `Todo.Kind`.
- The groups and what counts as soon: `Backpack.groups`, `Backpack.soon`.
- How often it checks: the schedule in `Backpack.init`. The notification wording: `Backpack.announce`.
- A summary at a time of day: a `LampSchedule.daily` beside the one in `Backpack.init`, with
  `LampNotifications.send`.
- The panel's layout: `PanelView`; a row: `TodoRow`.
