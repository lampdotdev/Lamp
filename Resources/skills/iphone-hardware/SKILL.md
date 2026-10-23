---
name: iphone-hardware
description: What the phone itself offers an iPhone app - motion, the camera and scanning, location, haptics, Face ID, Bluetooth and nearby phones, Apple Health, NFC, AR and music - with the frameworks to use, and the capabilities.json declarations Lamp signs the app for. Read before using any of them.
---

# The phone's own hardware, and Health

The phone itself is the app's best material: use what it has, without being asked, whenever it fits what the user
wants.

## What to use for each

- Motion: `LampMotion` from LampSupport.swift (tilt, gravity, acceleration, rotation, compass heading, today's
  steps, a shake count) for anything that tilts, steers, shakes or counts.
- Camera: AVFoundation's AVCaptureSession in a UIViewRepresentable for live capture, UIImagePickerController or
  PhotosPicker to take or choose a picture, VisionKit's DataScannerViewController to read text and codes live and
  VNDocumentCameraViewController to scan documents.
- Location and maps: CoreLocation (ask for when-in-use) and MapKit. Notifications at a place:
  UNUserNotificationCenter with a location trigger.
- Haptics: `.sensoryFeedback` for taps and successes, CoreHaptics for patterns.
- Face ID or Touch ID: LocalAuthentication.
- Bluetooth devices: CoreBluetooth; nearby phones without a network: MultipeerConnectivity.
- NFC tags: CoreNFC.
- Siri and Shortcuts: App Intents. AR: ARKit with RealityKit. Music: MusicKit or MediaPlayer.

## Health

`LampHealth` from LampSupport.swift, after `{"healthkit": true}` in capabilities.json: `authorize(read:write:workouts:)`
once, then `total(.steps)` (today's; a day's sum, or its average for heart rate and the like),
`dailyTotals(.activeCalories, days: 7)`, `latest(.weight)`, `samples(.heartRate, days:)`, `sleep()` (hours, last
night), `workouts(days:)`, and `save(.caloriesEaten, 350)` to log what the person tells it; `Kind` lists steps,
distance, calories, heart rate, sleep, weight, water, protein and the rest, each with `unitName`.

- The simulator has no Health data of its own: save a sample there to have something to read, and only there. Never
  write test data on a person's own phone, where it would join their real record; what the app logs for them is only
  what they told it.
- A Mac has none at all (`LampHealth.isAvailable` is false): an app for both reads on the iPhone and keeps what the
  Mac shows in LampSync, if it's activity and fitness that may go to iCloud (see the iCloud rule); medical data stays
  on the iPhone.

## Permissions and declarations

The app already declares why it wants each of these (microphone, speech, camera, photos, location, motion,
Bluetooth, Face ID, health, NFC, Siri, nearby devices, music), so just request authorization before use and handle
denial in the interface.

Health, NFC, Siri, nearby phones and background work need a declaration first: write `capabilities.json` at the app's
root, e.g. `{"healthkit": true, "nfc": true, "siri": true, "weather": true, "homekit": true, "timeSensitive": true,
"backgroundModes": ["audio", "location"], "bonjourServices": ["_myapp._tcp", "_myapp._udp"], "backgroundTasks":
["com.example.refresh"]}`, and Lamp signs the app for them and declares them.

- Modes: audio, location, fetch, processing, remote-notification, bluetooth-central, bluetooth-peripheral.
- `bonjourServices` are the service types MultipeerConnectivity browses for (both _tcp and _udp of the same name, up
  to 15 characters).
- `backgroundTasks` are the identifiers BGTaskScheduler registers, needed with the fetch and processing modes.
