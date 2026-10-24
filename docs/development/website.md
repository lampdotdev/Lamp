# The website

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

`site/` is lamp.dev (Astro; `site/FIRST_IDEA.md`, `site/BUG_REPORTS.md` and `site/SHARED_WISHES.md` cover its moving
parts; the last is a wish shared as a link, `WishLink` in the app). Its
Download buttons (`DownloadButton.astro` and the menu bar's) are the lamp's bright orange with white words, about
3:1 at their lightest, a faint shadow under the words. That trade-off was weighed and accepted: the brightness is
the point of the button, and the label is large, bold and the same on every page. About 3:1 is the floor for
those buttons, so a change that goes below it is a regression; everything else on the site, links and small
text included, is held to 4.5:1.

