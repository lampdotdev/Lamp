# The website

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

`site/` is lamp.dev (Astro; `site/FIRST_IDEA.md`, `site/BUG_REPORTS.md` and `site/SHARED_WISHES.md` cover its moving
parts; the last is a wish shared as a link, `WishLink` in the app). Its
homepage sells remixable software and is dressed as home video: cream paper, tape labels, and the stripes on their
sleeves. The stripes are green to magenta, in that order, never blue or purple (the hero widens the deep magentas and
reds under its words). They're the hero's whole field, on the slant, with plain white words kept to the bands they
read on; elsewhere they sit beside headings (a tab above each), never on a heading's letters. "Change it live" shows
the making, not the app in use: a plain Mac window changing as it's asked from Lamp's chat beside it
(`ChangeStory.astro`). New York's sleeve in the hero and the stack of sleeves in "From the shelf" are one sleeve
(`src/lib/tapes.ts`, filled from `src/lib/starters.ts`), three.js drawn from canvases in the page's fonts: its
screenshot shown whole (an original's reel playing over it, below), where it plays and, side by side, a "Try it" ("Play it" where it plays in a browser, `page` in `starters.ts`, which goes there) and a "Remix it" that opens the remix dialog on the front (a remix's change in
marker and a "Remix me" there instead), what it is and the changes its starter suggests on the back, and the screenshot, the name (or a
remix's change) and the stripes on its spine. On the shelf the sleeves lie flat, spines out, each original with a
remix of it under it, and a blank one at the bottom whose back is about Lamp, with a Download for Mac; one that's
clicked stands up as the hero's does. They're lit with soft shadows, lean toward the
pointer and turn over when clicked (an arrow round the right side shows which way while the pointer is on one), on a canvas that runs past its box (so nothing is cropped) and lets the pointer
through, over a flat HTML
version kept for screen readers and browsers without WebGL. An original's reel (a starter's `reel.mp4`, "A starter's reel" in the desk guide) comes straight from its repository on
raw.githubusercontent.com, muted and looping, on a plane over the screenshot while the sleeve shows its front: the
hero's from when someone first reaches for it, since New York's is by far the largest, and the shelf's while it
stands up. Nothing is fetched before that, the screenshot stays until a frame has played and for good if there's no
reel, and where less motion is asked for it doesn't play there. An expand button on it, and a button a keyboard
reaches, open it large (`watchReel`). The device icons are Phosphor's duotone set, with the
fill in the sleeve's colors. Apps and games get the same weight on it, and
every example is a real starter (`Resources/Starters`), with the pictures and changes it ships with; the devices it
lists are only those a kind of app or a shipped device integration really reaches. Its Download buttons, and the
menu bar's, are the paper's ink with paper-colored words (the last section's is the stripes' yellow with ink).
A link from a Remix panel or a repository's README (`?ask=`, with `starter=` or `repo=` and `commit=` when it names
what it's a copy of, and `from=` where it was pressed) opens the homepage's remix dialog (`RemixDialog.astro`, "Remixing a published page" in the wishes guide), as does the
sleeve's "Remix it" (`lamp:remix`), and a sleeve's "Try it" opens it to try the starter (`lamp:try`): "Try" over the name, no box, and the same buttons, with Lamp opening the starter itself, before any setup ("Starters" in the desk guide). It's a slab in 3D with real thickness that rises in from the bottom and
leans toward the pointer (the tapes behind it hold still while it's open), with the stripes up its left edge, the
starter's picture and description on the dark on its left (a repository's own picture, its preview or else its icon,
from raw.githubusercontent.com, `repoPictures`; or a blank label with the name in marker), its title as
"Remix" in marker over the name and its maker, the request in the page's sans-serif in its box, and the page's
buttons (Open in Lamp in ink, on a Mac; Download for Mac in the stripes' yellow). A page can't ask whether Lamp is
installed, so Open in Lamp watches whether Lamp answered: if the browser keeps its focus for two seconds, the
dialog turns to getting Lamp, with Download first, and turns back should Lamp open late. Closed, it takes its
parameters out of the address, so a reload doesn't bring it back. The ideas page keeps its own card
(`WishDialog.astro`). The ideas page's Download buttons (`DownloadButton.astro`, in its first-idea section and opened wishes) are the
lamp's bright orange with white words, about 3:1 at their lightest, a faint shadow under the words. That trade-off
was weighed and accepted: the brightness is the point of the button, and the label is large, bold and the same
wherever it appears. About 3:1 is the floor for those buttons, so a change that goes below it is a regression;
everything else on the site, links and small text included, is held to 4.5:1.

