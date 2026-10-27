---
name: more-apps
description: Whether a request is for one more app beside the ones the wish has, or a change to an app it has - "never mind, make it a timer instead" versus "I want a second Mac app" - asking the person before adding one, and how to call make_app_for for each (`app` or `another`). Read before adding an app to a wish that has one.
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

## One more app: ask first

When the person seems to want another app beside the ones the wish has ("I want a second Mac app, a journal", "also
make an Android app for my phone", "make me a journal" in a wish that has a timer), ask them before calling
`make_app_for` or writing anything, with `ask`: one question, two answers, in their words. Adding an app is theirs to
choose, so ask even when the request sounds clear; it costs them one click.

- Question, ten words at most: "A second app, or turn the timer into a journal?"
- Answers: "A second app" (one more app beside the one they have) and "Change the timer" (the app they have, changed).

End your turn after asking: their answer is the next message. Don't ask again when the message is already their answer
to that question.

- A second app: `make_app_for` with `another: true` and the devices and make of the new app. It goes in a folder of its
  own (`Mac2/`), with its own name, id and data, and the wish's other apps stay as they are. Calling it again the same
  way in the same request is the same app, not a third.
- A change: the app they have, as above.
- Their own words instead: follow those.

Never answer the question for them, and never add an app for a change of mind.
