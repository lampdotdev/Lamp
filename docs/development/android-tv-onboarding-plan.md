# Plan: Android TV onboarding with as little done by hand as Android allows

Status: plan for review (Codex), no code yet. Written against origin/main 32b73db7.

## How it works today

- Try On → **Connect a TV Over Wi‑Fi…** opens `AndroidWiFi` (Sources/Lamp/AndroidWiFi.swift), one generic window
  for phones and TVs alike.
- It shows three lines of instructions (Google TV/Android TV path, Fire TV path, "select the build seven times"), an
  address field, a pairing-code field, and every host `adb mdns services` sees offering `_adb-tls-pairing` or
  `_adb-tls-connect` / `_adb._tcp`, polled every 3 s while the window is open.
- The person: turns on Developer options on the TV (seven presses on the build), turns on Wireless debugging, opens
  Pair device with pairing code, picks or types the address in Lamp, types the code, clicks Pair and Connect.
  Fire TV / older TV: turns on ADB debugging, leaves the code empty, Lamp connects on 5555, the TV asks "Allow USB
  debugging?" and the person chooses Allow.
- Lamp then lists the TV like any adb device (`Adb.devices`, `Device.from(adb:)`, a TV by its leanback feature),
  and the person chooses it under Try On.

What's wrong with that, beyond the work on the TV:

1. **The choice doesn't last.** A Wi‑Fi device's id is adb's serial, `192.168.1.20:37123`. Wireless debugging's
   connect port changes each time it's turned on (and after the TV restarts), and Lamp's own adb server
   (`Edition.androidPorts`) forgets the connection when it restarts. Nothing connects again by itself, so the next
   Play says "Lamp can't see the Android device chosen under Try On. Plug it in…" (`Store.installOnAndroid`) and
   the person goes back through the window.
2. **Words meant for phones.** A TV that's chosen but not connected gets "Plug in your Android device"
   (`AndroidTools.check`), and `Adb.advice` says "USB debugging" / "About phone → Build number".
3. **Lamp doesn't know the TV is there** until adb does. A Google TV or Fire TV is on the network long before
   developer mode, but it isn't in Your Devices or Try On, so the person has to know to open the Wi‑Fi window.
4. **The person drives the window.** They pick an address, type a code and press a button, even though Lamp can
   see when the TV's pairing screen is open and which port it's on.

## What can't be automated (the person presses these on the TV)

Android's security model makes each of these a press on the TV itself. Without a debugging connection Lamp has no
way in, and no supported API exists for any of them.

| Step | Google TV / Android TV 11+ | Fire TV / older Android TV |
|---|---|---|
| Turn on Developer options | Settings → System → About → select "Android TV OS build" 7 times | Settings → My Fire TV → About → select the device name 7 times (on newer Fire OS, when Developer options is hidden) |
| Turn on debugging | Developer options → Wireless debugging → On, and "Allow on this network?" → Allow | Developer options → ADB debugging → On |
| Let this Mac in | Wireless debugging → Pair device with pairing code, then type the 6-digit code into Lamp (a TV has no camera, so the QR pairing phones use doesn't exist) | "Allow USB debugging?" → tick Always allow → Allow |
| After the TV restarts or changes Wi‑Fi | Wireless debugging is off again: turn it back on (no new code; the Mac stays paired) | Nothing: ADB debugging stays on |

Not needed, so not asked for: "Install unknown apps" (adb installs don't go through it).

Not yet checked on a real TV (none on hand): whether a Google TV with a profile PIN asks for it when Developer
options turns on, and exactly when wireless debugging turns itself off on Google TV 12–14.

## What Lamp would automate

### 1. Find the TV before developer mode (new)

Recognise Android TVs from what they announce on the network anyway, in the look Lamp already makes
(`HomeNetwork`, `Integrations.Scan`), and list each as a TV that still needs setting up: in Your Devices, on the
desk shelf and under Try On's Android TV section as "Set Up Living Room TV…".

- Google TV / Android TV: `_androidtvremote2._tcp` (the TV's remote service) together with `_googlecast._tcp`
  (its name in `fn`, model in `md`). `_googlecast` alone also matches Chromecasts and Nest speakers, so a host is
  a TV only with `_androidtvremote2` too.
- Fire TV: `_amzn-wplay._tcp`.
- The service tells Lamp which steps to show: Google/Android TV's or Fire TV's. No more three generic lines.
- Fixtures: the TXT records have to be **recorded from real TVs, with the date**, before this ships (see "What I
  need" below). I won't write them from memory.

### 2. One setup window per TV that moves forward by itself (replaces Connect Over Wi‑Fi for TVs)

Built the way `TVSetup` already does Samsung and LG: a row per step, each checked by Lamp, the next one shown with
what to do on the remote. Lamp moves to the next step once it sees the last one done:

1. **Developer options and Wireless debugging.** Lamp can't see these happen, so this step waits until it sees the
   TV's address offering `_adb-tls-pairing` or `_adb-tls-connect` (Google TV), or until `adb connect <ip>:5555`
   gets an answer (Fire TV, retried every few seconds while the window is open).
2. **Pair.** As soon as the TV's pairing screen is open, Lamp knows its port. The window shows only the code field
   ("Type the code your TV shows") and pairs when six digits are in. No address and no button. A wrong code says
   so and clears.
3. **Connect.** Done by Lamp right after pairing, on the port the TV announces. On the Fire TV path: "Choose Allow
   on the TV, and tick Always allow". Lamp sees `unauthorized` turn into `device` and moves on.
4. **Ready.** Play, if it was waiting, goes on (`then:`, as `TVSetup.show(_:then:)` does).

The existing window stays for phones over Wi‑Fi, and as "Type an address instead…" when a TV isn't found (another
subnet, or mDNS blocked).

### 3. Remember the TV and connect again without asking (new; fixes problems 1 and 2)

- Keep each TV that has connected once (like `TVs.kept`), by a **stable id**: `ro.serialno` read over adb, plus the
  name adb's mDNS instance carries (`adb-<serial>-<suffix>`), and its last address. `project.device` stores that id,
  never `ip:port`. Projects that already store `ip:port` are matched by address once, then saved with the new id.
- On every device look, and before each Play on a kept TV, Lamp connects quietly: to the port the TV announces on
  `_adb-tls-connect` (already paired, so there's no code and no prompt), or to `<last address>:5555` on the Fire TV
  path.
- When it can't connect, Play says what to do on the TV rather than "plug it in": "Turn Wireless debugging back on
  in Developer options. Living Room TV stays paired." The words come from the kept record's kind (Google TV or
  Fire TV).
- `Adb.advice` and `AndroidTools.check` get TV wording for a device whose kept record or leanback feature says it's
  a TV.

### 4. Words and docs

- Try On: "Set Up <TV>…" for a found TV that isn't ready. "Connect a TV Over Wi‑Fi…" becomes the fallback.
- docs/development/android.md (Over Wi‑Fi) and devices.md (what counts as set up) describe the new flow.
- No agent tool or prompt changes, so the three engines stay as they are. One line in `androidTVTry` only if the
  agent needs to tell the person how to reconnect, which I don't expect.

## Workarounds (flagged, and why I'd leave each out of v1)

- **Pressing the remote for the person** through the Android TV Remote protocol (`_androidtvremote2`, port 6466/6467).
  After a remote-pairing code, Lamp could send D-pad presses through Settings to the build number and Wireless
  debugging. **Workaround:** the protocol is Google's private one, written down only by people who reverse-engineered
  it. The presses would be blind (Lamp can't see the screen before adb), menus differ by maker and version, and it
  adds a second code rather than saving one. The LG guide also sets "Lamp never presses the remote's buttons for the
  person" as a rule (Resources/skills/lg-developer-mode). **Recommendation:** don't. A smaller variant, opening the
  Settings screen through the same protocol's app-link launch, would also need a real TV to prove and is still
  unofficial. Not in v1.
- **Keeping Wireless debugging on across restarts** with a helper app on the TV that's granted
  `WRITE_SECURE_SETTINGS` over adb (`pm grant`) and turns `adb_wifi_enabled` back on at boot. **Workaround, and a
  security cost:** it leaves debugging open on the network after every boot, without the person turning it on.
  **Recommendation:** don't. Say plainly what to turn back on (part 3).
- **`adb tcpip 5555` on a Google TV** so it also listens on the fixed old port. **Workaround:** it lasts only until
  the restart that causes the problem, and it opens unauthenticated-transport adb on the LAN. **Recommendation:**
  don't. Part 3 already copes with the moving port.
- The IP-address fallback window is kept on purpose. It's a fallback for networks where mDNS doesn't get through,
  not a workaround in the code.

## Tests and proof (when coding)

- Targeted `swift test`: parsing recorded `adb mdns services` output and recorded TXT records into found TVs; Google
  TV vs Fire TV steps; the window's step order from given states (no pairing service → step 1, pairing service →
  step 2, `unauthorized` → step 3); stable-id migration of a stored `ip:port`; quiet reconnect choosing the
  announced port. A test for problem 1 (choice lost when the port changes) is shown failing on main first.
- Existing Android suites: `AndroidKitTests` and the Android/device record tests in Tests/Regression.
- One short lampvm run (no cua-driver on the Mac): Lamp Dev built from the branch, the setup window opened for a TV
  with the steps shown, a screenshot of each step. A macOS guest can't run the Android TV emulator (no nested
  virtualisation) and has no TV on its network, so **the real pairing can't be shown in the VM.** That part is
  "not run live" until someone runs it with a real TV.

## What I need from Dan

- Is there a Google TV / Chromecast with Google TV, or a Fire TV, on the network? With one, a 10-minute recording
  (`dns-sd -B _androidtvremote2._tcp`, `_googlecast._tcp`, `_amzn-wplay._tcp` and their TXT, plus
  `adb mdns services` with the pairing screen open) gives the real fixtures, and a live pairing proves parts 2–3.
  Without one, part 1 waits, and parts 2–3 ship on adb's own output only.

## Size

About a day and a half: part 3 and the wording (half a day, no fixtures needed), part 2 (half a day), part 1
(half a day once the fixtures exist). Parts 3 → 2 → 1 is the order: each is useful alone, and part 3 fixes what
hurts today.
