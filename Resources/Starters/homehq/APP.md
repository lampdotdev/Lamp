Kind: screen, a family dashboard for the kitchen wall, at home on the Mac and shown on an iPad, an Android tablet or
photo frame, a TV or an Xbox once it's put there.
Look: warm paper (#F2EEE6) and black ink, condensed Archivo for labels and numbers, Instrument Serif for titles, one
bright color per person; a narrow rail of sections down the left with the clock at its foot.

# Home HQ

Based on photo-frame-dashboard by Wes Bos (MIT, `Web/LICENSE-photo-frame-dashboard`,
https://github.com/wesbos/photo-frame-dashboard), his family dashboard for a hacked Android photo frame, ported to a
Lamp screen: the same page and look, without its build step, its hosting or its demo-only smart home and AI-usage
views. The credit stays on the page (the settings drawer's last line), in about.json and in credits.json.

- **Today** (`views/home.js`): a huge clock and the date, the weather now with the next hours and a line of advice
  ("Rain from 4 PM. Pack a rain jacket for soccer."), each person's state from the calendar (what they're at, or free
  till when), **Next up** (the next event today, minutes to go, and "Leave in…" from its travel time), a lane per person
  with the rest of their day, the photo tile, chores for this part of the day as rings, the shopping count, and
  tomorrow at a glance.
- **Calendar** (`views/calendar.js`): day, week and month, an event's sheet, and New event (who, when, how long).
- **Chores** (`views/tasks.js`): a lane per person and Anyone, for the morning, after school or the evening; ticking one
  off gives a kid its stars, with Undo. Ticks start again each day.
- **Shopping** (`views/shopping.js`): the list by aisle and by store, add from usuals and suggestions, tick off, clear.
  An item the catalog doesn't know goes in its aisle by `LampAI.choose` (the AI set up in Lamp, remembered 90 days), and
  stays in Other without AI.
- **Photos** (`views/photos.js`): a slideshow with Auto, Cover, Pair, Collage and Polaroid layouts, and favorites,
  which come round more often.
- **Photo frame and night clock** (`views/ambient.js`): after two minutes untouched it goes back to Today and then to a
  slideshow with the time and the next event, or at night (10 PM to 6 AM) a dim clock; a touch wakes it.
- **First run** (`views/setup.js`): a screen that isn't set up opens on a welcome: Set up my family, or Show me an
  example. The examples are only a first look: the moment anything is the family's own (their people or chores, their
  calendar, place or album, an event or shopping item they added) they go for good, everywhere, keeping what the family
  changed (`DATA.ownsSomething`, `DATA.clearExamples`); empty pages then say what goes there. The setup asks who's at home (people and pets, who earns stars), where they live, the family's shared
  calendar, an album, and a few chores to start; finishing takes the examples away for good, and every other
  copy of the screen follows. A family already made in the editor, and a calendar or album already chosen, are where
  the setup starts. A look at a fresh copy shows the welcome over the example family (`App.setup`,
  `DATA.isSetUp`, `settings.example`).
- **Family and Chores** (from Settings, `views/editor.js`): the family (a name, a color each, Stars for those who
  earn them, and pets, with a picture instead of a color) and the chore list by part of the day (a picture, who, how many stars), changed on the screen and saved as
  they're changed. The editor's own picture and color lists are at its top.
- **Settings** (Settings on the rail, the clock below it, or D): the weather's place, the family's own calendars and photos
  (only where the app around the page can read them: the Mac, iPhone and iPad), Set up my family while the example shows, the photo frame and
  night clock, and the credit. Keys: 1–5 the sections, A the photo frame, N the night clock, Escape or Back closes.
  A remote's arrows move between the buttons and OK presses one (`Web/lamp.js`).

## Code

- `Web/index.html`: the stage, the rail and an empty section per view; loads Lamp's `lamp.js` first, then the
  dashboard's scripts in order (each adds to `window.App`). Plain ES5, no modules and no build step, so it runs in a
  TV's browser. Its viewport is the device's width: the page fills whatever it's on.
- `Web/js/data.js`: `window.DATA`, the family and everything shown (shape below), and its saving.
- `Web/js/app.js`: `App`: the time, formatting, people's colors (`App.pstyle`, `App.avatar`), calendar helpers
  (`App.timedOn`, `App.allDayOn`, `App.nextEvent`, `App.leaveBy`), weather helpers (`App.weatherNow`, `App.hourly`,
  `App.deg` for °C or °F by the screen's language), the router (`App.register`, `App.go`; views are built once and
  rebuilt when `App.emit('data')` says the data changed), toasts, sheets, idle and modes, and `fit()`, which says
  the screen's shape (below).
- `Web/js/system.js`: the example pictures (`App.img`, a landscape drawn as SVG from a seed), banners (`App.banner`)
  and the settings drawer.
- `Web/js/sync.js`: the family's data the same on every copy of the screen (below).
- `Web/js/views/editor.js`: the Family and Chores sheets.
- `Web/js/views/setup.js`: the welcome and the first-run setup.
- `Web/js/live.js`: the real weather (Open-Meteo, open data with no key: `App.findPlaces`, `App.loadWeather`), and the
  family's calendars and photos through `LampNative` (`App.loadCalendars`, `App.loadPhotos`).
- `Web/js/slideshow.js`: `App.Slideshow`, used by Photos, the Today tile and the photo frame.
- `Web/js/icons.js`: the stroke icons (`App.icon('calendar', 24)`).
- `Web/css/tokens.css` (colors, type sizes, the fonts in `Web/fonts/`), `Web/css/base.css` (the stage, rail, cards,
  sheets, the settings drawer, focus), and one file per view in `Web/css/views/`.
- `Sources/Native.swift`: what the page asks of the Mac, iPhone or iPad: `calendars`, `events`, `albums` and `photos`
  (JPEGs at 1600 px as data URLs). Each runs only once the person turns it on in Settings, so the system asks for
  access then.

## Any screen, any size

The page is responsive, not a picture scaled to fit: it fills a TV, a Mac window of any size, a photo frame, an iPad
either way up and a phone, and reflows for each.

- **Sizes** are all in rems (`App.rem(px)` in script), drawn as pixels of the 1280×800 frame the dashboard was made
  for, a sixteenth of a rem each. The rem follows the screen (`html { font-size }` in `css/base.css`): on a wide screen
  the lesser of 1/80 of its width and 1/50 of its height, so a 16:10 screen looks as the original did and a wider one
  gets more room; on a tall one 1/50 of its width, never under 13 px. Borders of 1–2 px stay pixels.
- **Shape**: `fit()` in `app.js` puts `tall` on `<html>` when the screen is less than 1.15 times as wide as it is
  tall (an iPad upright, a phone, anything near square), and `narrow` when it's also under 44 rems across (a phone);
  `App.tall` and `App.narrow` say the same to script, and a view is drawn again when either changes. Wide keeps the
  rail at the left and everything on one screen, lists scrolling inside their boxes. Tall puts the rail along the
  bottom, lets a view scroll, and stacks what was side by side: each view's CSS file ends with its `.tall` and
  `.narrow` rules (Today one column of cards, Chores' lanes wrapping, Shopping's list under what to add, the
  calendar opening on the week, a list of days, on a phone).
- New things follow the same rules: sizes in rems, grid and flex that share out the space, and a `.tall` (and if
  need be `.narrow`) rule for when there isn't the width. Look at a change at several shapes (`look_at_app`'s
  `shape`: 1920x1080, 1280x800, 820x1180, 390x844).

## Data

`DATA` in `Web/js/data.js`:

- `people`: `{ id, name, color, rgb, ink, age?, pet?, emoji? }` (an `age` makes someone who earns stars; `pet` one
  with no day in the calendar, drawn with its `emoji`). `ALL` is the ids of everyone but the pets (`DATA.humanIds`,
  `App.humans`), as an event for the whole family has them; `family` is everyone's color.
- `events`: `{ id, title, start, end (Dates), people: [ids], allDay?, loc?, notes?, travel? (minutes to get there) }`;
  `ex` marks an example, `cal` one from the family's shared calendar, which is everyone's: who goes is in its title for the
  family to read, never guessed. With the calendar on, Today shows the rest of the day as one list for everyone, and the
  example events are hidden (`App.events`).
- `routines` (morning, after school, evening by hour), `chores`: `{ id, r, who (a person or 'any'), title, emoji,
  stars, done, doneBy?, overdue? }`, `stars` and `week` (each kid's last seven days).
- `stores`, `catOrder` (aisle order per store), `groceries`: `{ id, name, cat, qty, store, done, note }`, `catalog`
  and `usuals` for adding.
- `weather`: the 24 hours of today, `t` (°C), `c` ('sun', 'moon', 'partly', 'cloud', 'rain'), `p` (chance of rain, %),
  with `hi` and `lo`; `example` until a place is chosen.
- `photos`: `{ seed or src, o ('l' or 'p'), date 'YYYY-MM-DD', place, from (a person), tag (photos taken together),
  fav }`.
- `settings`: `place` ({ name, lat, lon }), `calendars` (null off, or the family's calendar as `[id]`, its
  EventKit identifier, with its name in `calendarName`; a name or [] all, from before, still works), `album` (null off, or its id), `example` (this screen chose the example family over the welcome; not shared).

Examples are made afresh on each device at each launch, relative to today, until the family is set up; they're never
shared. What the family changes is the same on every copy of the screen (the Mac, the kitchen tablet, the TV, the
frame) through the wish's own shared collections, merged item by item (`Web/js/sync.js`,
`LampStore.shared(name, { wish: true })` in lamp.js), so another app of the wish (an iPhone app beside the screen, a
Mac app) reads and changes the same family, chores, list and calendar by asking for the same names with `wish: true`:
`people`, `chores`, `groceries`, `events`, `ticks` (one per chore per day), `stars`, `settings` (one item per
setting), `favs`, and what a copy that can read them publishes for the others: `calendar` (the chosen calendars'
events) and `photos` (the album, its pictures in `LampStore.sharedFiles('photos', { wish: true })`). A change on any copy reaches
the others at once while they're on the same Wi‑Fi, and when they next meet otherwise. The views change `DATA` and
call `App.emit('data')`: that's what saves and shares a change, so every change must call it. An example changed is
kept as the family's; one taken away is kept, marked `gone: true`, so it stays away. Each device also keeps its own
copy with `LampStore` under "homehq" (`DATA.save`, `DATA.snapshot`, `DATA.restore`). Only add fields to what's saved
or shared, never rename one.

## Where it's shown

It's one page everywhere (a screen): the Mac app, an iPhone or iPad, a Samsung or LG TV, the Xbox, and an Android tablet
or photo frame, each given with `make_app_for` as the screen's `places`. Nothing in the page changes for a place: it
fills any screen shape, and the remote moves focus.

### Putting it on a photo frame

An Android photo frame shows it once Lamp can reach the frame with adb: the screen's place "android", which installs
Lamp's own small Android app around the page (full screen, kept awake), as Wes Bos's kiosk app does. Getting adb on a
frame is the person's to do, by following Wes Bos's guides for their model:
https://github.com/wesbos/photo-frame-dashboard#which-frame-do-you-have and its device index,
https://github.com/wesbos/photo-frame-dashboard/blob/main/docs/devices.md. Once `adb devices` lists the frame (over USB,
or Try On's Connect Over Wi‑Fi…), it's chosen under Try On like any Android device. Lamp never roots or flashes a
frame and never runs the guides' scripts: point the person to them, and say what they'll see on the frame (an "Allow
USB debugging?" prompt) rather than doing any of it.

## Easy to change

- The family and chores: the person changes them on the screen (Family and Chores in Settings); the examples are in
  `data.js` beside the events and groceries. The family's own are in the shared collections and win over the
  examples once changed.
- The sections: the rail in `index.html`, a view in `js/views/` registered with `App.register`, its CSS in
  `css/views/`; Today's cards are in `views/home.js` (`.h-side` holds the photo, chores, shopping and tomorrow).
- A countdown (to school, a trip, a birthday) or the week's chores at a glance: a card on Today, a date in `data.js`.
- Colors and type: `css/tokens.css`. When the photo frame and night clock come on: `App.idle` in `app.js` and
  `App.isNight`.
