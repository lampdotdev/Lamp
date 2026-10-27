---
name: more-apps
description: Whether a request is for one more app beside the ones the wish has, or a change to an app it has - "never mind, make it a timer instead" versus "also an Android app" - asking the person before adding one, why a second app of a kind the wish has (two Mac apps) can't be added yet, and how to call make_app_for for each (`app` or `another`). Read before adding an app to a wish that has one.
---

# One more app, or a change to the one the wish has

A wish that has an app (made, or still waiting to be made) never gets another by accident: `make_app_for` refuses a
call that names neither `app` nor `another`. Which one you give is the person's choice, read from what they asked.

## A change to the app they have

Most requests are this. The person changes their mind or wants something else in its place:

- "Actually never mind, make it a pomodoro timer instead."
- "Make it do X instead." "Turn it into a game." "Can it be for my iPhone too?"

Change the app the wish has. When only what it does changes, change its code: no `make_app_for` at all. When what it's
made for changes (other devices, web or native), call `make_app_for` with its folder in `app` ("." for the app in the
wish's own folder). It keeps its folder, its saved data and its place among the wish's apps. Never add an app for a
change of mind, and never take the old one away to make room: the person didn't ask for either.

## One more app, of another kind: ask first

A wish can have one more app beside the ones it has only when it's of another kind: an Android app beside a Mac app,
a TV app beside an iPhone app. Two apps of one kind (two Mac apps, two iPhone apps) can't
be in one wish yet, and `make_app_for` refuses one, nothing changed; a device's own app (a Roku's) is one per wish.

When the person seems to want another app of a kind the wish doesn't have ("also make an Android app for my phone",
"a web game to go with it"), ask them before calling `make_app_for` or writing anything, with `ask`: one question,
ten words at most, two answers in their words. Adding an app is theirs to choose, so ask even when the request sounds
clear; it costs them one click.

- Question: "An Android app as well, or make this one Android?"
- Answers: "A second app" (one more app beside the one they have) and "Change this one" (the app they have, changed).

End your turn after asking: their answer is the next message. Don't ask again when the message is already their answer
to that question.

- A second app: `make_app_for` with `another: true` and the devices and make of the new app. It goes in a folder of its
  own, with its own name, id and data, and the wish's other apps stay as they are.
- A change: the app they have, as above.
- Their own words instead: follow those.

## Another app of the same kind

When they ask for another app of a kind the wish already has ("I want a second Mac app, a journal" in a wish with a
Mac app), don't offer a second app: it can't be added yet. Tell them so in a sentence, and offer what can be done
with `ask`: change the app they have into it, or make it a separate wish of its own (from Lamp's desk). Never add it
by changing what it's made for so it slips in as another kind, unless that's what they asked for: a web app where
native is what fits (the web-or-native skill) only to get around this limit is never the answer.

Never answer the question for them, and never add an app for a change of mind.
