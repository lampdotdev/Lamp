# Plan: Android TV onboarding with as little done by hand as Android allows

Status: plan, revised after review, no code yet. Written against origin/main 32b73db7. The files it touches
(AndroidWiFi.swift, Android.swift, Device.swift, Store.swift) are unchanged on main since then.

## How it works today

- Try On → **Connect a TV Over Wi‑Fi…** opens `AndroidWiFi`, one window for phones and TVs alike: three lines of
  instructions, an address field, a code field, and the hosts `adb mdns services` sees, polled every 3 s.
- The person turns on Developer options and Wireless debugging on the TV, opens Pair device with pairing code,
  picks or types the address, types the code and clicks Pair and Connect. Fire TV: ADB debugging on, no code, Lamp
  connects on 5555 and the TV asks to allow this Mac.
- Lamp then lists the TV like any adb device (`Adb.devices`, `Device.from(adb:)`, a TV by its leanback feature), and
  the person chooses it under Try On.

## What a real Google TV shows (captured during review)

A Google TV streaming device on Android 14, already paired with both Lamp and Lamp Dev:

- **adb reconnects it by itself.** Lamp's server lists it under its mDNS name,
  `adb-<serial>-<suffix>._adb-tls-connect._tcp`, with no `adb connect` from Lamp. adb discovers paired TLS devices
  and connects to them, including when its server starts.
- **Lamp Dev lists it twice**: under that mDNS name and as `<ip>:<port>`, the second from the window's own
  `adb connect`. Two selectors for one TV get past Lamp's one-launch-per-device queue.
- **It offers two transports at once**: `_adb-tls-connect` on a random port and legacy `_adb._tcp` on 5555.
  `networkServices()` writes both into one `connectPort`, so whichever line comes last wins. In the capture that's
  5555, the unencrypted legacy transport.
- On the network it also announces `_androidtvremote2._tcp` and `_googlecast._tcp`, under different instance names
  and `.local` hostnames, both resolving to the same address. The Cast TXT carries the friendly name (`fn`) and the
  model (`md`). No pairing service was showing, since nobody had the pairing screen open.

## What's wrong today

1. **Identity is adb's current selector.** `Device.id` is the adb serial (`ip:port` or the mDNS name), and
   `project.device` stores it. `installOnAndroid` passes it straight to adb as `-s`, and so does Stop's fallback.
   The port changes each time Wireless debugging is turned on and after a restart, so a saved choice goes stale and
   Play says "Plug it in…".
2. **One TV, two rows**, as above.
3. **Transports are merged.** TLS-connect and legacy 5555 are one port, and after a TLS pairing the code falls back
   to 5555 when discovery is slow.
4. **The device model assumes every Android device is set up and present.** `isSetUp` is true for `.android`,
   `isAway` leaves Android out, `refreshAndroidDevices()` replaces every Android row with adb's current listing (a
   TV adb can't see right now disappears), and `setup()`, `AndroidTools.check` and `Adb.advice` speak of USB
   debugging and "Plug in your Android device".
5. **The manual path can't work without mDNS.** Pairing and connecting use different ports, but the window takes
   one address.
6. **Lamp doesn't know a TV is there** until adb does, and the person drives every step of the window.

## What can't be automated (the person presses these on the TV)

No supported API does any of these without a debugging connection. (The TV's remote protocol works before
developer mode, but it only sends key presses and app links: see Workarounds.)

| Step | Google TV / Android TV with Wireless debugging | Fire OS |
|---|---|---|
| Developer options | Settings → System → About → select "Android TV OS build" 7 times | Settings → My Fire TV → About → select the device name 7 times, when Developer options is hidden |
| Debugging | Developer options → Wireless debugging → On, then Allow on this network | Developer options → ADB debugging → On |
| Let this Mac in | Pair device with pairing code, then type the 6-digit code into Lamp. A TV has no camera, so there's no QR pairing | "Allow USB debugging?" → Always allow → Allow |
| Later | When Wireless debugging is off again (after a restart or a Wi‑Fi change, behavior to be measured), turn it back on. No new code unless the TV revoked this Mac | Nothing measured yet |

Android's docs give Android 13 and later for wireless pairing on a TV (11 on phones), and makers differ, so Lamp
goes by what the TV announces, not by its version number. Each Lamp edition has its own adb key: pairing Lamp
doesn't authorize Lamp Dev. adb installs don't need "Install unknown apps".

## What Lamp would automate

### 1. A TV's saved identity, apart from its live adb selector (fixes 1–4)

- **A kept Android TV record**, like `TVs.kept`: a local id (`android-tv:<uuid>`), the verified `ro.serialno`, maker
  and model, the mDNS instance names seen for it, the transport it was authorized on (TLS or Fire OS legacy), and
  the last address. The address is only a hint for connecting, never proof of identity. A serial that's empty, a
  placeholder, or shared by two live devices isn't used as identity: that TV is kept by its record id and confirmed
  by asking the person.
- **`project.device` stores the record id.** One resolver, `AndroidTVs.selector(for:)`, gives the current
  authorized adb selector for a record: the live device whose serial matches, preferring adb's mDNS TLS selector,
  never a legacy 5555 one for a TLS-paired TV. Every path that talks to adb goes through it: Play (`installOnAndroid`),
  Stop and its fallback, `AndroidTools.check`, `use_app`'s key presses and screenshots, logs, the running-app
  record, and the per-device launch queue, keyed by record id so two selectors can't race.
- **One row per TV.** `Adb.devices()` folds the selectors that read the same serial into one device. Lamp stops
  running `adb connect ip:port` for a TV adb already lists under its mDNS name, which ends the duplicate at its source.
- **Kept TVs stay listed while adb can't see them**: `refreshAndroidDevices()` merges kept records back in as away,
  and `isAway` and `setup()` say so in TV words ("Turn Wireless debugging back on"; Fire OS: "Check ADB debugging is
  on"). Phones over USB, phones over Wi‑Fi, and the emulator keep today's behavior. This doesn't reuse `kind.isTV`,
  which means Samsung and LG web-app TVs.
- **Connecting.** First Lamp reads adb's listing, waits briefly for its own discovery, and runs `adb connect` only
  when the kept TV still isn't there: to the TLS port it announces, or to `<address>:5555` for a Fire OS record.
  That's one attempt in flight per TV, with backoff, and never every 3 seconds.
- **Ready** means authorized (`device`), the serial matches the record, and a `getprop` answers. A "connected to"
  line from `adb connect` isn't enough.
- **Old choices.** A `project.device` that's still an `ip:port` or an mDNS name is adopted only if a live, authorized
  device answers on exactly that selector right now. That match is safe because the port is random each session,
  unlike a match by address alone, which DHCP can reuse. Its serial goes into a new record. Anything else stays as
  the saved choice, shown as "Choose your TV again" under Try On, and is never matched by address alone. Adopting is
  idempotent.

### 2. Setup by state, in a window per TV (fixes 5 and 6)

The window has rows for Developer options, Wireless debugging and this Mac allowed. It doesn't run them in a fixed
order: on every look it starts from what the TV shows now.

- **Already authorized** (listed as `device`, serial matches): Ready. Pairing is skipped even when a pairing service
  is showing.
- **Pairing service showing, not authorized**: only the code field, "Type the code your TV shows". Six digits submit
  once per code and per pairing endpoint. Leading zeros are kept, and a second request can't start while one is in
  flight. A wrong code ("wrong password") and a timeout or an expired screen get different words. After pairing,
  connect over TLS, and if discovery doesn't show the connect port, ask for it (below) rather than trying 5555.
- **TLS-connect showing, not authorized**: this Mac isn't paired (or was revoked). Ask for the pairing screen.
- **Fire OS** (legacy only, no TLS service): connect on 5555, then "Choose Allow and tick Always allow", and wait
  for `unauthorized` to become `device`.
- **Nothing showing**: the Developer options and Wireless debugging steps, in words for the kind of TV when Lamp
  knows it (part 3).
- **Manual, for when mDNS is blocked**: "Pairing address and port" plus the code, then "Connection address and
  port" from the main Wireless debugging screen. Two fields, because they're two ports. The same window says when
  macOS's Local Network permission is what's missing (the existing `localNetworkSettings` link).
- Late answers can't resume anything: a selection generation, as `TVSetup` has, and Play goes on only if its project
  and turn still own the request.
- The existing window stays for phones over Wi‑Fi.

### 3. Find the TV before developer mode (last, and smaller)

- A host that announces `_androidtvremote2._tcp` and `_googlecast._tcp` **at the same resolved address** is listed
  as an Android TV that isn't set up yet, named by Cast's `fn`. `HomeNetwork` keeps only a few model TXT keys today,
  so it gets a narrow, length-limited `fn`. Either service alone, or neither, still allows setup by address: this is
  a hint, not a requirement.
- A found TV is shown as possible, not as yours (a neighbor's on shared Wi‑Fi). It's kept only once it's authorized,
  and Lamp never connects to found TVs on its own.
- Fire TV recognition waits for a recorded Fire TV fixture. `_amzn-wplay` stays unconfirmed until then.

### 4. Words and docs

Try On gets "Set Up <TV>…" for a TV that isn't ready, with "Connect a TV Over Wi‑Fi…" as the fallback. The Over
Wi‑Fi section of docs/development/android.md and devices.md (what counts as set up) describe the records and the
resolver. No agent tool or prompt changes, so the three engines stay as they are.

## Workarounds (each left out of v1)

- **Pressing the remote for the person** over the Android TV Remote protocol (`_androidtvremote2`). It's Google's
  private protocol, known only through reimplementations. It sends key presses and app-link launches, not arbitrary
  intents, so there's no proven way to open Developer options. The presses would be blind, because Lamp can't see
  the screen, and Settings menus differ by maker. Left out for scope and reliability.
- **A helper app on the TV that turns Wireless debugging back on at boot** (granted `WRITE_SECURE_SETTINGS` over
  adb, writing `adb_wifi_enabled`). It's unproven on any TV, and it leaves debugging on the network after every
  restart without the person choosing it.
- **`adb tcpip 5555` on a Google TV.** It switches to the unencrypted legacy transport, doesn't survive a restart for
  sure, and would hide the transport-selection bug rather than fix it.
- Fire OS's `adb connect <ip>:5555` is not a workaround: it's Amazon's documented route once ADB debugging is on.

## Where I disagree with the review

- **Old choices.** The review says to compare retained identifying information before adopting a saved selection.
  Saved choices today keep nothing but the selector, so there's nothing to compare. I'd adopt on an exact live
  selector match (address and session port, or the mDNS name) and ask in every other case. That's safe, because the
  port changes every session, and it costs the person one click at most.
- **Proof.** The review lists about a dozen scenarios (revoked authorization, missing serial, cancellation and late
  callbacks, wrong-device migration…) plus an isolated Lamp UI run and a reboot test. Per the brief, proof stays
  light: targeted tests where a captured output or a seen bug decides the answer, and one coordinated check on the
  real TV at the end. The rest are design requirements in this plan, checked in code review, not each a test.
- **The LG rule** ("Lamp never presses the remote's buttons") is LG's, as the review says. I quoted it as if it
  covered Android. It doesn't, and the remote-button route is now left out on its own merits.
- I agree with the rest: adb's own reconnect, the duplicate rows, separate transports, the resolver everywhere,
  setup by state, the two-port fallback, discovery as a hint, and the version table.

## Proof when coding (kept light)

- Targeted `swift test`, from the outputs captured on the real TV (identifiers replaced, capture date kept):
  - `networkServices()` keeps TLS-connect and legacy apart. This test is shown failing on main first, where 5555
    overwrites the TLS port.
  - `Adb.devices()` folds the two selectors of one serial into one device. Also shown failing first.
  - The resolver: a saved record still resolves after the port changes, and never to a 5555 selector for a
    TLS-paired TV.
  - Adopting an old choice: exact live match → adopted, address-only match → not adopted.
- Existing suites: `AndroidKitTests` and the Android device-record tests in Tests/Regression. Build: `swift build`.
- **One coordinated check on the real TV at the end**, with Dan, in Lamp Dev: connect through the new window
  (already paired, so it should go straight to Ready), Play and Stop one small TV app, and turn Wireless debugging off
  and on to change the port, then Play again on the same saved choice. Existing pairings stay as they are. No
  revoking, no reboot test. The rest is "not run live".

## Size

About three days: part 1 (a day and a half: the record, the resolver at every adb call site, dedupe, merge and
words), part 2 (a day), part 3 (half a day). Parts 1 → 2 → 3 is the order: part 1 alone fixes the lost choice and the
duplicate row.
