# Talking to a page: `LampVoice` and `LampAI.hear`

Status: built for pages, transcribed by OpenRouter's Scribe. It goes with [act.md](act.md): `hear` turns what was said
into text, and `act` does it.

## Who does what

**The app around the page records.** It's `LampPageVoice` in each host, answering `LampVoice` in lamp.js:

- **Mac, iPhone and iPad:** `LampPageVoice` in `LampPage.swift`, recording with AVAudioEngine.
- **Android and Android TV:** `LampPageVoice` in `LampPageGateway.kt`, recording with AudioRecord's voice-recognition
  source. On an Android TV box that source takes the remote's microphone, which was seen on one Google TV box. A
  screen's manifest asks for RECORD_AUDIO.
- **Everywhere else** (TV browsers, the Xbox, Lamp's preview, an older host): `status` says there's no voice, and Ask is
  typed.

How a host records:

- **Format:** both hosts convert to 16 kHz mono signed 16-bit little-endian PCM in a WAV.
- **When it ends:** after 1.2 s of quiet that follows speech, or at 15 s (`cap`). At 6 s with no speech it ends as
  `nothing` if no sound came, and otherwise sends what it has to be transcribed. Speech is a level three times the
  room's: the quietest it has been lately, which follows a dip at once and rises back over a couple of seconds. So
  speech from the first moment counts once its first pause shows the room. The limits run on the clock, so a
  recording whose audio stops coming still ends. This is a rule of thumb on levels, not a way of telling speech from a
  television.
- **One at a time:** each recording has its own stop. A new one, a cancel or a page load ends the one before, which
  answers only the page that asked for it.
- **What reaches the page:** levels go to the page tagged with the page's session.
- **Asking:** `status` never prompts; only `listen` asks for the microphone.
- **Closing:** a page reload, or the app leaving the screen, cancels a recording whether the page says so or not.
- **Reading out:** speech is read with AVSpeechSynthesizer on Apple devices and TextToSpeech on Android, and resolves when
  it's finished.

**The page transcribes it with `LampAI.hear`, at `/ai/hear` (`AppHear.swift`):**

- **Checked first:** before anything is paid for, the gateway checks the audio is a WAV in that exact format, 0.3 to
  15 s long, with exactly the 44-byte header the hosts write and nothing else in the file. Its body limit is its own,
  about 650 KB.
- **The call:** `elevenlabs/scribe-v2` through OpenRouter, with `provider.options.elevenlabs.no_verbatim`, using the
  key Lamp keeps on the Mac. The device never holds the key.
- **The bill:** the `usage.cost` OpenRouter reports is recorded as the app's. The OpenRouter account set up in Lamp pays.
- **Errors, each in words the person can act on:** no key (501, `needs: text`), a key OpenRouter doesn't accept, no
  credit, OpenRouter busy, network failure.
- **Paid once:** lamp.js and the Android relay try each way to the Mac once, and not again after a moment. Each
  recording carries its own id, so one that reaches Lamp by two ways is transcribed and charged once (Lamp keeps the
  answer for five minutes per app). A request that times out on the device may still have been paid for.
- **Availability:** `isAvailable('hear')` asks the route through the host, so an older host answers false.

## Home HQ's Ask

- **One deliberate press:** Ask on the rail, reached with the arrows. Opening it listens straight away, with the level
  showing and focus on **Stop**.
- **OK keeps its meaning:** it is never a global key.
- **The opening press can't stop it:** Stop ignores presses in the first 0.7 s and repeated keys, so the press that
  opened Ask can't also end the recording.
- **What happens next:**

  | Recording ended | Then |
  |---|---|
  | `quiet` or `stopped` | Transcribed ("Working out what you said…"), then `act`. |
  | `cap` | Never acted on: it asks the person to say it again, shorter. |
  | `nothing` | Says so, and says whether any sound reached the microphone at all. |
  | `denied` | Says so and opens typing. |

- **Typing:** "Type instead" is in every voice sheet, and the typed form shows wherever there's no voice. Ask never
  hides for lack of a microphone.
- **Typing or talking again:** "Type instead", a typed question or another recording drops a transcription still on
  its way.
- **Cancelling:** Back, closing or the page hiding ends the session. The recording is cancelled, and a recording,
  transcript or answer that comes back later is dropped, so no write follows. A question back is listened for only once
  the reply has been read out to the end.

## Not in this change

- LG, Samsung and Xbox voice, and the phone as the microphone.
- On-device recognition: `act` needs OpenRouter anyway.
- Streaming transcription.
