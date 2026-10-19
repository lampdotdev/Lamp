Kind: dashboard
Look: Naples and a family wedding. The terracotta tint and washes (`Color.terracotta`), the warm, slightly funny
tone, Marco's mother as the one the AI plays, the toast, and the champagne glasses icon. Another place or occasion
gets colours and words of its own.

# Wedding Words

An Italian coach for one occasion: the person's sister is marrying Marco, whose family is from Naples, and they
have to hold a conversation with Marco's mother at the rehearsal dinner and give a toast in Italian. Everything is
rehearsal, not lessons, and the tone is warm and a bit funny. A sidebar with three pages:

- **The wedding**: the countdown in days, four "Can I do it yet?" milestones (introduce myself to Marco's mother,
  small talk at the table, politely survive a third plate, deliver the toast), each with how often it was
  rehearsed and the coach's confidence, and today's phrase with Hear It and a button to practice the weakest
  milestone.
- **At the table**: spoken roleplay. The AI plays Marco's mother in Italian, one short turn at a time, adapting to
  the milestone and the person's score; the person answers by speaking (Italian speech recognition) or typing,
  and gets one gentle correction in English. Her lines are spoken aloud; the reply box appears once she's done
  (Skip Audio stops her). Show English shows the translation.
- **My toast**: a rough English draft and a few stories become short Italian lines with a pronunciation guide
  (AI), rehearsed one line at a time or as a full run-through, each attempt coached. Rebuilding rewrites the toast
  for the person's Italian now.

Settings: the wedding date (three months after the first launch to begin with), the sister's and the mother's
names, and opt-in coaching notifications at an hour.

Feedback is on the words recognized from the voice, not on the sound: the app says so, and the prompts tell the
model not to claim it heard an accent.

## Code

- `App.swift`: the window and the Settings scene; one `WeddingCoach` shared by both.
- `ContentView.swift`: the sidebar, the home page (countdown, milestones, today's phrase) and the `terracotta`
  colour.
- `Coach.swift`: `WeddingState` (everything kept), `WeddingCoach` (milestones, scores, the weakest one, the daily
  phrase, notifications) and `CoachSettings`.
- `Practice.swift`: the roleplay page.
- `TableTalk.swift`: the roleplay's conversation and its AI prompt. Conversations are kept per milestone; a reply is
  saved before her answer is asked for, so when that call fails it stays, and Try again sends it once more.
- `Toast.swift`: the toast page: writing, rebuilding, line and full rehearsal, and their AI prompts.
- `Speech.swift`: `WeddingSpeech` (Italian speech synthesis, and recognition on the device first, online when the
  Italian model isn't installed) and `SpeakingInput`, the speak-or-type field.
- `Intents.swift`: a Shortcuts/Siri action that opens the app to rehearse.

## Data

All in LampStore: `wedding` (`WeddingState`: date, names, the toast's draft, stories and lines, scores and
attempts per milestone, the last practice, the notification settings, today's phrase) and `conversation-<n>`, the
roleplay turns for milestone n. The state is saved on the first launch so the date chosen then stays.

Notifications: `scheduleNotifications` plans up to 60 days ahead (`wedding-<day>`, replaced whenever the person
rehearses or changes Settings): the day's phrase, a check-in after two quiet days, and a full toast run-through
every other day in the last three weeks. A daily `LampSchedule` at 9 asks the AI for a fresh phrase aimed at the
weakest milestone.

## Easy to change

- The language: the `it-IT` locale in `Speech.swift` and the prompts in `TableTalk.swift`, `Toast.swift` and
  `Coach.dailyCoaching`, plus the wording on each page.
- The occasion and people: the milestones in `WeddingCoach.milestones`, the defaults in `WeddingState`, the
  headline words in `ContentView.home`, and who the AI plays in `TableTalk.ask`.
- How hard the coach is: the scoring and correction instructions in the prompts.
- Notification wording and rhythm: `WeddingCoach.scheduleNotifications`.
- Colours: `Color.terracotta` in `ContentView.swift`.
