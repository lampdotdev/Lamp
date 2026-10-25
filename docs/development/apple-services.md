# iCloud, Apple Health, background work, photos, location, weather, music and the home

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

## iCloud

An app with an iPhone half may keep data in iCloud: `{"icloud": true}` in `capabilities.json`
(`Template.Capabilities.icloud`, and `container(for:)`: "iCloud." and the app's bundle id, so an app for both
has one container on both platforms). It becomes the CloudKit entitlements everywhere Apple signs the app
for a team (the phone's and the Mac's `App.entitlements`, the simulator's ad hoc signature in
`Store.finishSimulatorBundle`) and `LampICloudContainer` in each Info.plist, which is how the app knows it was
built for iCloud. A Mac app on its own is refused it: Lamp's signature can't carry iCloud (see "Apps for both").
The data goes through `LampSync` in LampSupport.swift, the one building block for it: collections like
`LampStore`'s, kept on the device in LampStore as well (under `icloud.<name>`), and sent and fetched by
CloudKit's own `CKSyncEngine` in a zone of the app's in the private database, one record per item carrying its
JSON. The later change to an item wins; a sign-in or a zone deleted in iCloud sends everything up again. The
agent is told in `Agent.Rules.icloud` (iPhone and both-kind prompts) when to use it and that the simulator is
usually not signed in. The team must be in the Developer Program: a free account's build fails at signing, so Lamp
says so first, wherever the app is about to be signed for the team: on the person's phone, or as the Mac half
of an app for both (`PhoneTools.xcodeFreeTeams` reads which teams are free). Before Open and Rebuild & Open
and when a phone is chosen it is the setup check (`PhoneSetup.Context.requiresPaidTeam`); a message is never
held for it, since asking the agent is how iCloud is taken out again, so after a request it is one line in
the chat where the build would start (`Devices.membershipProblem`, in `Store.installOnDevice` and
`Store.build`), not sent to the agent as an error to fix. On a phone the turn's change is already built for
the simulator and saved; on the Mac half that build is the turn's only one, so the change stays in the app's
files unsaved, as after any build that fails. In the simulator nothing is signed for a team, so a free
account goes on working there.

## Apple Health

Health data goes through `LampHealth` in LampSupport.swift, the one building block for it: a `Kind` for each
kind of data (steps, calories, heart rate, sleep, weight, what was eaten and drunk) with its HealthKit type,
unit and the unit's name, and calls to authorize, read a day's total or average, daily totals, the latest
sample, samples, last night's sleep and workouts, and to save a sample. It needs `{"healthkit": true}` in
`capabilities.json`, which is the iPhone's entitlement only (`entitlementsPlist(container:platform:)` leaves
it off the Mac half's signature, which couldn't carry it): a Mac has no Health data, `isAvailable` is false
there, and an app for both reads on the iPhone and keeps what the Mac shows in LampSync. The simulator has
HealthKit with no data in it, so the agent is told to save a sample before reading (the iphone-hardware skill).
`HealthTests` compiles the block out of the template and checks every kind's unit.
Apple's Developer Program License Agreement (3.3.3(D)) forbids using iCloud or CloudKit for sensitive,
individually-identifiable health information. The "sensitive" matters: the iCloud rule (`Agent.Rules.icloud`)
keeps what is medical (diagnoses, conditions, symptoms, medications, lab results, clinical records, reproductive or
mental-health entries) on the device, and lets everyday activity and fitness numbers such as step counts sync,
which they aren't. When it's unclear, on the device.

## Work while an iPhone app is closed

`{"background": true}` in capabilities.json means on iPhone what it means on a Mac: the app works while nobody is
looking. A Mac app opens at login and keeps running (`LampBackground`); an iPhone app is woken by iOS to run its
`LampSchedule`s, the same calls as the Mac's (`daily`, `every`), from the iOS copy in LampSupport. Lamp declares
one task for it (`Template.scheduleTask`, "lamp.schedule", with the fetch mode, in `Capabilities.lists`), and the
app's WindowGroup carries `.lampBackground()`, SwiftUI's `backgroundTask(.appRefresh)` running everything due and
asking for the next time (a no-op on the Mac, so an app for both shares the code). iOS ends an app that asks for a
task it has no handler for, so a request is made only once `.lampBackground()` has run and only when the app goes
to the back or after a background run, never as a schedule is made. iOS decides when: near the time, a few times
an hour at most, less for an app rarely opened; the simulator refuses every request, so the work is tried by
running it from the app. Notifications go with it (`LampNotifications`, both platforms): `at:` for later,
`id:`/`cancel` to replace or take one back, `actions:` buttons that work without opening the app, handled by
`LampNotifications.onAction` set at launch, and on iPhone `timeSensitive:` with `{"timeSensitive": true}`, the
entitlement. The rule is `Agent.Rules.iPhoneBackground`, and `Rules.notifications` in both kinds' blocks.

## Photos, location, weather, music and the home

Five more building blocks in LampSupport.swift, each the one place for its framework: `LampPhotos` (Photos: the
library by day and place, albums, a picture at a size, what a picture shows by Vision, saving; the picker is
SwiftUI's), `LampLocation` (CoreLocation: where the person is with a name from the map, watching big moves,
and on the iPhone the visits where they stop, kept in LampStore), `LampWeather` (WeatherKit: now, hours, days),
`LampMusic` (MusicKit: recently played, the library, the catalog, playing; and on the iPhone what the Music app
is playing) and `LampHome` (HomeKit, iPhone only: accessories with their room and state, switching, dimming and
locking). The first four compile on both platforms. Weather and the home are entitlements, declared in
`capabilities.json` as `weather` and `homekit` (`Template.Capabilities`): weather goes to both halves of an app
Apple signs for a team and never to a Mac app on its own (`weather(for:)`), the home to the iPhone's signature
only. Apple also wants WeatherKit and MusicKit turned on for the app under App Services at developer.apple.com,
which automatic signing doesn't do: the blocks' failures say so. The reasons the system shows are in
`iosUsageDescriptions` and, for the Mac, in `Store.deploy` and `universalMacInfoPlist`. The agent is told in
`Agent.Rules.sharedBlocks` (both kinds) and the Home part of `iPhoneBlocks`.
Two of them carry Apple's own terms, which the rules repeat. HomeKit is only for an app whose job is the home,
and what it reads may not leave the phone (3.3.3(I)): not to an AI model, a server, iCloud or the Mac. WeatherKit
(Attachment 8) wants Apple's attribution wherever its weather is shown, which `LampWeatherAttribution` draws
(the Apple Weather mark from `WeatherService.attribution`, linking to its sources page), allows forecasts to be
kept only briefly, and rules out apps for emergencies.

