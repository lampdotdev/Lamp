# The website

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

`site/` is lamp.dev (Astro; `site/FIRST_IDEA.md`, `site/BUG_REPORTS.md` and `site/SHARED_WISHES.md` cover its moving
parts; the last is a wish shared as a link, `WishLink` in the app). Its
homepage sells remixable software and is dressed as home video: cream paper, tape labels, and the stripes on their
sleeves. The stripes are the hero's whole field, on the slant, with plain white words kept to the bands they read
on; elsewhere they run between sections and sit beside headings (a tab above each), never on a heading's letters. Apps and games get the same weight on it, and
every example is a real starter (`Resources/Starters`), with the pictures and changes it ships with; the devices it
lists are only those a kind of app or a shipped device integration really reaches. Its Download buttons, and the
menu bar's, are the paper's ink with paper-colored words (the last section's is the stripes' yellow with ink).
The ideas page's Download buttons (`DownloadButton.astro`, in its first-idea section and opened wishes) are the
lamp's bright orange with white words, about 3:1 at their lightest, a faint shadow under the words. That trade-off
was weighed and accepted: the brightness is the point of the button, and the label is large, bold and the same
wherever it appears. About 3:1 is the floor for those buttons, so a change that goes below it is a regression;
everything else on the site, links and small text included, is held to 4.5:1.

