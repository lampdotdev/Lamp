Run `Tests/PhoneInstall/run.sh` on a Mac. It compiles the production failure classifier and launch waiter
into an isolated executable, without Lamp settings, accounts, certificates or a phone. An optional output
path writes the exact plain-language messages for UI replay. `Fixtures/messages.json` holds the
approved user-facing wording, separately from tool-output fixtures.

`Fixtures/manifest.json` distinguishes each input's source:

- `local-real-output`: captured during the real Lamp phone run on this Mac. The missing-destination
  fixture came from Xcode 27 with cable and phone Wi-Fi off; identifiers were redacted. The local
  launch-security fixture is the captured first-launch refusal, with the signing team redacted.
- `reported-output`: diagnostic excerpts from people reporting actual tool runs. Paths, team IDs and
  names are redacted where noted. The three-app and ten-ID cases are reported Xcode messages, not full
  captured command transcripts. These were not captured on our machine.
- `documentation-derived`: synthetic trust and expired-profile inputs based on Apple documentation.
  They do not prove the exact diagnostic spelling on a device. Seven-day expiry and ten-ID registration
  limits come from [Apple's account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).
  The three-app limit also has a recent report in the linked Apple forum. Trust steps come from
  [Apple's phone trust instructions](https://support.apple.com/en-us/118254).

The actual devicectl security refusal lists signature, entitlements and developer trust as alternatives;
we keep that uncertainty in the message. Capability refusal names the feature, without assuming every
capability needs a paid account.

Launch replays feed saved output through subprocesses with controlled delays/exits and the production
waiter. The acknowledgement came from a real non-console launch; keeping a console alive, delayed
output, zero exit without acknowledgement, cancellation and timeout are simulated. No physical phone,
first-time trust flow, quota recovery, signing renewal, installed app data preservation, or sustained
app health was verified. “Ready” means devicectl acknowledged launching this bundle while its attached
console was still running; it does not prove that a screen was rendered or that the app stays healthy.

VM pictures are real Lamp windows containing seeded fictional chats, not a live phone install. To
reproduce, write messages with the replay runner, run `seed-vm.py messages.json /tmp/phone-replay`, and
push those fictional app folders into the VM's `Library/Application Support/Lamp Dev/Apps`. Install the
ad-hoc build and launch with:

```
lampvm launch 'Lamp Dev' -onboarded YES -engine pi -piProvider ext-ui-replay \
  -piModel.ext-ui-replay ui-replay
```

Those are temporary made-up provider/model preferences to let the signed-out VM show the main window;
there is no server, API key or signed-in builder. Clicking Retry runs the real Store phone path and
reports that the fictional phone is absent. This checks the button and its route, not successful
installation. The fixtures do not include generated-app sources or an installed phone bundle.

After review, `Tests/PhoneInstall/run-store-review.sh` extracts the current Store's actual Stop, Retry,
phone install, notification and turn-completion code into an isolated Swift harness. Device discovery,
build/install/launch, logging storage and the system notifier are inert substitutes. Checks
cover Stop while discovery has no subprocess, stopping before launch acknowledgement, unsuccessful
turn completion, suppressed notifications and normal Mac/simulator/acknowledged-phone completion, and the preparation failure copy and details.
This is regression evidence for Store's control flow, not an end-to-end phone or notification trial.

Agent Details still collapses long output to twelve display lines initially; Show Full Output removes
that limit and Show Less restores it. The revised packaged build compiled this UI. Both available VM
slots were in use during the review follow-up, so the expansion control and a main/PR screenshot pair
were not clicked/captured in that follow-up.

`Tests/PhoneInstall/run-team-replay.sh` generates disposable certificates without touching any keychain.
It checks that a Team ID comes from the certificate subject's organizational unit, not the developer ID
in its common name. An optional path to a locally confirmed Team ID also runs read-only checks against
Xcode's team cache and public certificates. The real-phone run exposed the mismatch on this Mac.

The copy-pass VM screenshots replay the captured real-phone refusal with the production classifier
and a seeded fictional chat in the new packaged build. Show Full Output is clicked in the VM; there
is no new physical phone run. The original hardware evidence remains separate.
