---
name: icloud-sync
description: Keeping the person's data the same on every device signed in to their iCloud account with LampSync - declaring it, the API, signing, what the simulator shows, and what may never sync. Read before an app keeps data in iCloud.
---

# The same data on every device

To keep the person's data the same on every device signed in to their iCloud account (the Mac and the iPhone, or an
iPhone and an iPad), declare `{"icloud": true}` in `capabilities.json` and keep that data with `LampSync` from
LampSupport.swift instead of LampStore:

- `@StateObject private var notes = LampSync.collection("notes", of: Note.self)` in the view that owns the list (one
  object per name, shared by every view that asks), then `notes.items`, `notes.put(note)`, `notes.delete(id)`,
  `notes.get(id)`; the view follows changes made anywhere.
- Items are Codable and Identifiable, and the same rules as LampStore's apply to changing a saved type.
- Use it for the data people would expect everywhere; settings for one device stay in LampStore.

## Signing and status

Lamp signs the app for iCloud with the person's Apple team, which must be in the Apple Developer Program (a free
account can't use iCloud; the build then fails at signing, and you say so plainly). Sync needs the device signed in
to iCloud; the simulator usually isn't, so what you see there is the data kept on that device, and
`LampSync.shared.status` says why. Offer the status in the app's settings.

## What never syncs

Apple's terms forbid keeping sensitive health information about a person in iCloud: what is medical (diagnoses,
conditions, symptoms, medications, lab results, clinical records, reproductive or mental-health entries) stays on the
device, in LampStore, never in LampSync. Everyday activity and fitness numbers (steps, distance, active calories,
workouts, water) aren't that, and may sync. When it's unclear which a kind is, keep it on the device.
