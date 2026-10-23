---
name: mac-permissions
description: A Mac app that needs Full Disk Access, Screen Recording or Accessibility - LampPermissions' gate, view and live state, asking for the least, and what to say about a permission only the person can turn on. Read before writing anything that needs one.
---

# Full Disk Access, Screen Recording and Accessibility

When the app itself needs Full Disk Access (other apps' data such as notification history, Mail, Messages or Safari;
or scanning the whole disk), Screen Recording (screenshots, recordings, other apps' windows) or Accessibility
(reading or controlling other apps), `LampPermissions` from LampSupport.swift is strongly recommended over a check,
list of steps, System Settings link, Finder reveal or relaunch of your own. Write your own only when you have a reason
it can't meet, such as a design the person asked for, and say so in your reply.

## Using the helper

- Wrap what needs it: `LampPermissionGate(.fullDiskAccess, reason: "Your notifications are in a file macOS
  protects.") { SummaryView() }` shows the contents once the permission is on, and until then a screen that takes the
  person to the switch in System Settings, gets the app into the list there, and ends in Quit & Reopen for Full Disk
  Access (macOS only gives that to an app when it starts) or notices by itself when the others are switched on.
- When only one feature needs it, don't gate the whole app or ask at launch: check
  `LampPermissions.has(.screenRecording)` when the feature is used and show `LampPermissionView(.screenRecording,
  reason: "…") { /* now on */ }` in a sheet.
- `@StateObject var access = LampPermissionState(.accessibility)` gives a live `isOn` for your own controls.

Ask for the least that does the job: a file or folder the person picks or drops needs nothing, and macOS asks by
itself the first time an app reads Downloads, Desktop or Documents.

## What to tell the person

Only the person can turn one of these on (in System Settings, which is the app's own permission and not something
Lamp approves), so when you look at the app you'll see that screen: say plainly that what's behind it is untested and
that they turn it on once. It is once: Lamp signs every build of the app the same way, so a permission stays on
through your changes. Never say a rebuild lost it, and never tell them to remove and re-add the app in System
Settings.
