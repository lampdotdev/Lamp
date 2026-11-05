# The website

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

`site/` is lamp.dev (Astro; `site/FIRST_IDEA.md`, `site/BUG_REPORTS.md` and `site/SHARED_WISHES.md` cover its moving
parts; the last is a wish shared as a link, `WishLink` in the app). It reads as an open source project's site, not
a company's: plain and lo-fi, on cream paper (`--color-paper`) with ink (`--color-tape`) and a lighter ink for words
said in passing (`--color-muted-ink`, 4.5:1 on the paper), a tight grotesque for words and a mono for the menu,
labels, lists and small print, thin rules between parts, small corners and soft shadows only (nothing has a hard,
offset shadow). There's one kind of button, ink with paper-colored words (`.ink-button` in `global.css`); a second
choice beside it is an ink outline. The menu bar is GitHub, Changelog and Download (the ideas page is still there, but not in the menu for now); the footer is the project's
links (source, releases, changelog, contributing, security, issues) and the MIT license line, with no company sign-off. Lamp's mark is its icon
with "Lamp" beside it (`LampLockup.astro`), in the menu bar and wherever the site names Lamp as a mark. The stripes
(green to magenta, in that order, never blue or purple) are kept for Lamp's own things: its mark, and the light that
runs along a part of the homepage as it's added.

The homepage is itself a demo of changing something by asking. It opens as only a headline and the lines under it,
beside Lamp's chat, and each request in the chat adds a part of the page while you watch: what Lamp is, the starters,
what it runs on, how to get it (the download, the newest version, and building from source), answers to common
questions and what's new; "Make it dark" swaps the paper and the ink for the page's content alone (`.home[data-theme=dark]`; the site around it and the chat stay as they are). Nothing asks a model:
each request is written in advance with the part it adds, a request of one's own is answered with where it can be
done (Lamp), and Undo takes back the newest change. Without the script, and for search engines, every part is on the
page in order. The chat is drawn as Lamp draws the chat beside an app (LampSidebarKit), from the same colors
(`Paper.swift`) and shapes: a title bar with the red light (it puts the chat away; Lamp's mark at the corner brings it
back), Lamp's mark, "Editing Lamp Homepage" and Undo; what's asked in ink bubbles and what Lamp says in paper ones, both with Messages' tail;
the requests as outlined tiles whose gray icons (Phosphor's bold set) take their own color
under the pointer; and the round message box with the round ink Send. Where there's room the page itself is an app's window (a title bar with the window's lights and "Lamp Homepage", the page
scrolling inside it, and scrolling anywhere outside it scrolls it; the headline stands in its middle until a part is
added), the chat titled "Editing Lamp Homepage" beside it at the same height, with the project's links as one line under both
(`Footer` compact). The chat is a window of its own
down the right edge of the page's width (`--frame`, 80rem: on a wider window the menu bar, content, footer and chat
keep to the middle together), off the window's edges with round corners and a window's shadow; on a phone it's pinned to the foot of the
window over the page, never more than about two fifths of it, so what it adds stays in sight above it: the requests
as small pills that wrap, and only the latest exchange of the conversation. The red light puts it away into Lamp's mark at
the corner; the mark brings it back. The page keeps room under its footer as tall as whatever covers the window's foot (the
chat, or the mark), so all of it, the footer included, can be scrolled clear of it, and each part that comes in is scrolled to, all the way down: its end just above the chat (or the window's
foot). Until one's been picked, a soft light
passes over the requests in turn every few seconds (not where less motion is asked for). It follows the Mac's light or dark appearance, as Lamp does, whatever the page beside it looks like. Every starter shown is a real one (`Resources/Starters`, listed in `src/lib/starters.ts` with the
pictures and changes it ships with), each with one of its changes under it to ask for; the devices listed are only
those a kind of app or a shipped device integration really reaches. The newest version and what's new come from
`RELEASE_NOTES.md` at the top of the repository, read when the site is built (`src/lib/releases.ts`), as does the
changelog page (`/changelog`), so release notes are written in one place; a build without them leaves those out and
points to GitHub's releases.

A link from a Remix panel or a repository's README (`?ask=`, with `starter=` or `repo=` and `commit=` when it names
what it's a copy of, and `from=` where it was pressed) opens the homepage's remix dialog (`RemixDialog.astro`,
"Remixing a published page" in the wishes guide), as does a starter's "Change it" (`lamp:remix`), and a starter's "Try
it" opens it to try the starter (`lamp:try`): no box, and the same buttons, with Lamp opening the
starter itself, before any setup ("Starters" in the desk guide). It's a plain card on the paper with a thin ink edge,
rising a little into place: the starter's picture and description on the dark on its left (a repository's own
picture, its preview or else its icon, from raw.githubusercontent.com, `repoPictures`; or a blank label with the
name), then the name and its maker, a line that it opens as it is with the change waiting in Lamp's chat, the change
in a box marked optional, Open in Lamp in ink (on a Mac) beside Download for Mac in outline, and, where the starter
plays in a browser (`page` in `starters.ts`), a link to play it there. It's about getting the thing, not changing it
first, and the word "remix" isn't shown anywhere on the site (the code keeps it). A page can't ask whether Lamp is installed, so Open in Lamp watches
whether Lamp answered: if the browser keeps its focus for two seconds, the dialog turns to getting Lamp, with Download
first and in ink, and turns back should Lamp open late. Closed, it takes its parameters out of the address, so a
reload doesn't bring it back. The ideas page keeps its own card
(`WishDialog.astro`). A wish shared as a link has a page of its own (`src/pages/w/index.astro`, SHARED_WISHES.md),
is for playing it, and Lamp and remixing stay out of the way. It's on the same paper and ink as the rest of the site,
in its type (the name in the heavy grotesque, "Made with Lamp" in the mono), with thin rules and no stripes or color
of its own, so nothing competes with the wish. A header has the wish's name and who it's by on the left, then "updated <date>" for a link with releases (a sparkle and
darker words until opened, opening what's new), and "Made with Lamp" in the lighter ink on the right, then the thing someone made fills the rest of the window, only as big as it is (a playing page in the shape Lamp
sends with the link, else 16:9, the stage a web game is drawn on). What it does isn't on the page (it's in the link's
preview). Making one's own is a slim band at the foot: a box that reads as a prompt box, with the changes Lamp suggests
turning in it as its placeholder and a send button that opens Remix with what's written, or else the change it shows.
A chevron at the window's right, centered on the band, slides it and the header out of the window together (remembered in that
browser), the wish growing to the whole window on black, and from the same place brings both back. The change dialog is a plain card on the paper: the change, one line on Lamp, and
Get Lamp and Open in Lamp (on a Mac). As the page opens the wish fades up and the band after it; the wish's frame is
black until the page in it draws; where less motion is asked for, it's simply there. The ideas page is on the same paper: the categories as plain tabs, the ideas as flat cards with
a thin edge, and its first-idea section a plain ink card. An opened idea (`WishDialog.astro`) says what it is, that it's an
idea for Lamp to make (waiting when Lamp opens), and how to get it. What Lamp is asked stays out of sight; only words
a link brought, the person's own, are shown in a box to change. Its Download buttons (`DownloadButton.astro`, in that section
and in opened ideas) are the site's ink button. Everything on the site, links and small text included, is held to
4.5:1.
