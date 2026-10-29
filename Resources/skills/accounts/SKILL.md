---
name: accounts
description: The person's calendar, reminders, contacts, mail and cloud files through the accounts already on the device, and on a Mac what lives in another app they use (LampComputer). Read before an app reaches any of them, including when a wish names a service such as "my Google Calendar".
---

# The person's own accounts and apps

When a wish needs the person's calendar, reminders, contacts, mail or files, reach first for what the device is
already signed in to, before any service's API, sign-in, key or connector.

## Calendar, reminders and contacts (Mac and iPhone)

They come through the accounts already on the device (iCloud, Google, Exchange, Outlook), with no sign-in or key, from
LampSupport.swift: `LampCalendar.events(from:to:)` / `.add(...)`, `LampReminders.open()` / `.add(...)` /
`.complete(id)`, `LampContacts.search("name")` / `.find(email:)`.

## Mail and files (Mac only)

- Email: `LampMail.inbox(limit:since:before:)` / `.search(text, since:)` / `.body(of:)` / `.draft(to:subject:body:)` (a draft opens in Mail
  for the person to send; nothing is sent by the app).
- Their files in Google Drive, Dropbox, OneDrive or iCloud Drive are folders on the Mac: `LampFolders.synced` lists
  them and `LampFolders.synced("Google Drive")` gives one; read, write and watch them as files.

## What a service's name means

A wish that names a service ("my Google Calendar", "my Gmail", "my Outlook contacts", "my Dropbox") means these:
never call the service's web API, never ask for a key, a sign-in or a developer registration, and don't ask which
service they use. When their account or folder isn't on the Mac, the app says in one line where to add it (System
Settings → Internet Accounts, the service's own Mac app, or Mail) and works once it's there. macOS and iOS ask the
person once per kind of data; each call throws a plain message if refused, so show `error.localizedDescription`.

## Another app the person uses (Mac only)

When the information or the job lives in another app the person uses and the accounts and synced folders above and
`connectors` can't reach it (Slack, Messages, Notes, or a site in their browser such as LinkedIn or a CRM), use
`LampComputer.ask("…")` to read it or `LampComputer.perform("…")` to act there, from LampSupport.swift. It works with
what they're already signed in to, with no API keys or connectors, and returns text (ask for JSON in the task when
the app needs structure). Calls take 10–60 seconds, so run them when the person asks (a button), never on a timer,
and show progress. `perform` asks the person before every click or keystroke. Prefer files, LampText and the web when
they can do the job, and prefer the accounts above to LampComputer for mail, calendar, people and files: they're
instant and free.
