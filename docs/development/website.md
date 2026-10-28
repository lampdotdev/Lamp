# The website

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

`site/` is lamp.dev (Astro; `site/FIRST_IDEA.md`, `site/BUG_REPORTS.md` and `site/SHARED_WISHES.md` cover its moving
parts; the last is a wish shared as a link, `WishLink` in the app). Its
homepage sells remixable software and is dressed as home video: cream paper, tape labels, and the stripes on their
sleeves. The stripes are green to magenta, in that order, never blue or purple (the hero widens the deep magentas and
reds under its words). They're the hero's whole field, on the slant, with plain white words kept to the bands they
read on; elsewhere they sit beside headings (a tab above each), never on a heading's letters. "Change it live" shows
the making, not the app in use: a plain Mac window changing as it's asked from Lamp's chat beside it
(`ChangeStory.astro`). New York's sleeve in the hero (its screenshot, where it plays and a "Remix me" button that
goes to its repository on the front, the changes it suggests on the back) and the piles of tapes in "From the shelf"
(every starter in `src/lib/starters.ts`, each with a remix of it on top) are three.js (`src/lib/tapes.ts`), drawn
from canvases in the page's fonts: they're lit with soft shadows, lean toward the pointer and turn over or fly out
to show a screenshot when clicked, on a canvas that runs past its box (so nothing is cropped) and lets the pointer through, over a flat HTML
version kept for screen readers and browsers without WebGL. The device icons are Phosphor's duotone set, with the
fill in the sleeve's colors. Apps and games get the same weight on it, and
every example is a real starter (`Resources/Starters`), with the pictures and changes it ships with; the devices it
lists are only those a kind of app or a shipped device integration really reaches. Its Download buttons, and the
menu bar's, are the paper's ink with paper-colored words (the last section's is the stripes' yellow with ink).
The ideas page's Download buttons (`DownloadButton.astro`, in its first-idea section and opened wishes) are the
lamp's bright orange with white words, about 3:1 at their lightest, a faint shadow under the words. That trade-off
was weighed and accepted: the brightness is the point of the button, and the label is large, bold and the same
wherever it appears. About 3:1 is the floor for those buttons, so a change that goes below it is a regression;
everything else on the site, links and small text included, is held to 4.5:1.

