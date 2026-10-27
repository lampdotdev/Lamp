---
name: tv-design
description: Designing for a TV seen from across the room - type that reads at a distance, the edges a TV may cut off, contrast, focus that's unmistakable, layouts the remote's arrows move through the way they look, what to do instead of typing, glanceable pages, and motion a TV draws smoothly. For any app or game on a TV, web or native. Read before designing or restyling what a TV shows.
---

# Designing for a TV

A TV is watched from a sofa three metres away, by people who aren't holding a mouse and may not be looking closely.
Whatever the app is (a game, a family calendar, a photo album, a scoreboard, a remote for something) and however it's
made, what the TV shows has to read at that distance and be driven with a few keys. Everything here is how to design
for that; the person's own direction wins over any of it. How a page or an app gets its keys, focus and size is the
technical guidance's (the TV rules, lamp.js's opening comment, the web-app skill, a native platform's own focus API):
this skill is about what to do with them.

## Reading at a distance

- Text is large: about 28 px at 1080 lines tall as the smallest anything is (scale it with the screen's height, so
  about 2.6% of it), headings much larger, and the one or two things that matter largest of all. Short lines; no
  paragraphs to read.
- High contrast. A dark background is the default on a TV: it's kinder in a dim room and hides how a TV blooms bright
  areas. Avoid pure white fills and thin light text on a light ground; avoid fine lines, small icons and detail that
  depends on colour alone.
- Keep everything that matters inside a margin of about 5% on every side: many TVs cut off their edges. Backgrounds and
  pictures may run to the edge.
- Less on the screen than on a desktop: a TV shows a few big things, not a dense layout. Where there's a lot, show the
  most important part and let the rest be one step away.

## Glanceable pages

A page that's looked at rather than used (a dashboard, a calendar on the wall, a photo frame, a scoreboard, the day's
weather) reads at a glance: what matters first and largest, details smaller below, nothing that needs choosing to be
understood. It never scrolls as a whole; a long list scrolls inside its own box, or turns its own pages slowly. It
stays on for hours, so avoid anything that flashes, and let content move only when it changes (a slow fade between
photos, a number that updates in place).

## The remote: focus

There's no pointer. The person moves focus with the arrows and presses OK, so:

- What has focus is unmistakable from across the room: a thick outline, or a scale and a glow, never just a slight
  change of colour. Exactly one thing has focus, and something always does when anything can be chosen; when a screen
  opens, put focus on what the person most likely wants.
- Lay things out on a clear grid or in rows, so pressing an arrow moves focus where the eye expects. Avoid scattered
  layouts where "down" is ambiguous.
- Targets are large and spaced apart; nothing depends on hover.
- Back always goes back one step, and from the first screen leaves the app. Don't trap the person anywhere without a
  way out with Back.
- A dialog keeps focus inside itself until it's closed.

## Typing

Typing with a remote is slow and tiring. Avoid text fields unless the app can't work without one: offer choices to
pick from, remember what was typed before, or let a phone do the typing (the phone-controllers and phone-pages skills).

## Games on a TV

Everyone on the sofa sees the same screen: the score, lives and prompts are large and near the edges' safe margin,
not in small corners. Name the controls the way the controller in the players' hands names them. Pause on Back or the
menu button, with focus on Resume.

## Motion and speed

A TV's browser and processor are far slower than a Mac's. Keep animations few, short and on `transform` and `opacity`
in a page; avoid large blurs, shadows over big areas and video behind text. Pictures no larger than they're shown.

## Native apps on a TV

The same rules hold: Apple TV apps use the system's focus (focusable views, `.focusSection()` for rows) and its own
large type styles; an Android TV app uses Compose for TV's focusable cards and rows, keeps everything about 48 dp in
from the sides and 27 dp from the top and bottom, and body text at 16 sp and up with larger titles. Rows or a grid of
large cards suit a TV better than long lists. Let the platform draw focus where it does, and make sure your own views
show it as clearly.
