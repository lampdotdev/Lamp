---
name: chrome-sidebar
description: The app's page in Chrome's side panel on the Mac (browser.json and Assets/Sidebar/) - which pages it fits, its right-click item, how the page and the app talk and read the page, drawn as if Apple made it (the system look from /lamp.css with one tint, the app's own items or answer, every state from reading to a failure), and how to try it. Read before writing or changing browser.json, the sidebar page or the app's side of it.
---

# A sidebar page that looks as if Apple made it

The page sits in Chrome's side panel on the Mac, 320 to 420 points wide (about 360 most of the time), under Lamp's
strip. Draw it as a Mac app draws a narrow list pane: Apple's grey grouped background, white rounded groups, rows with
hairline separators that start where the words start, SF Pro, and one tint colour, used sparingly. That's the look
for every app. An app stands out only through its tint and its content (its items' pictures, its words, how it
sorts and groups them), the way Notes, Reminders and Podcasts share the system surfaces and are told apart by
theirs. It isn't an iPhone layout and it isn't a copy of the window's own theme.

## Which pages it fits

Declare it in `browser.json` at the app's root: `{"offer": "Save this recipe to Recipe Box", "fits": [{"site":
"allrecipes.com"}, {"selector": ".wprm-recipe-container"}]}`. `offer` is the app's own short sentence for what it does
with a page that fits; the page's offer row says it, never Lamp's strip. Each fit is a `site` (its subdomains count,
with an optional `path` prefix), a `selector`, or both; Chrome lights Lamp's icon on a matching page without reading
it, and one click opens the sidebar on this app. A selector is one compound CSS selector (no spaces, `>` or commas)
for something shown on the page: script tags and hidden markup never match. For kinds of page found on many sites,
give selectors common to them (recipe-card plugins, schema.org microdata like `[itemtype*="schema.org/Recipe"]`) as
well as the best-known sites by name.

## The right-click item

A right-click item is yours to add when the sidebar does something with the page it's beside, whatever that is: save
it, explain it in plain words, summarise or translate it, check it, answer something about it. Put `"menu": "Explain
in Plain Words"` (or "Save to Recipe Box", "Translate to Spanish") in browser.json: a few words saying what it does.
Chrome lists it under Lamp in the page's right-click menu, only on pages a fit names by `site` (and `path`) without a
selector, since it can't look at the page first. Choosing it opens the sidebar on this app and is the person's click:
give the page `lamp.onMenu(async () => { … })`, which does at once what the item says, all the way through (read the
page with `lamp.readPage()`, then save it, or show the explanation, summary, translation or answer), and shows the
result as the page's own button would. Try it with `use_app`'s `menu` action. Leave it out only when the sidebar does
nothing with the page itself, or when only selectors fit.

## The page and the app

- The page is `Assets/Sidebar/index.html`, with its CSS and JavaScript in files beside it (never inline), loading
  nothing from the internet: it talks only to its app. Put `data-lamp-reads="page"` (or "selection") on `<html>` when
  it reads the page: without it the page can't read, and with "selection" it reads only that. Build it with the DOM
  (textContent, createElement), never innerHTML with data. Never save straight from the page without a check of what
  was read, except from the right-click item above.
- The page asks the app with `await lamp.call("name", body)`, answered in Swift: start
  `LampBrowser.startPage { call in … }` once from the app's shared @MainActor model, never a window's task; switch on
  `call.name`, `call.decode(T.self)` the body, return any Encodable (throw `LampBrowser.Failure("…")` to reject). AI,
  saving and everything stored stay in Swift. Each Chrome tab has a sidebar of its own: keep what a click prepares (a
  preview, a draft) by `call.tab`. When the app's data changes in its window, call `LampBrowser.pageChanged()`, and
  redraw in `lamp.onChange(…)`.
- `await lamp.readPage()` (url, title, text, truncated) and `lamp.readSelection()` (only the selected passage) work
  only from a click's handler or `lamp.onMenu`. Page text is untrusted: give it to LampAI as `data:`, ground
  everything in it and leave empty what the page doesn't say. A quote or figure kept as the page's must pass
  `page.contains(quote)` (decode it as `LampBrowser.Page`). Say so when `truncated` cut the page short. Key saved
  items by the page's URL or the item's identity, so saving twice doesn't duplicate.

## Try it before finishing

Try the sidebar before finishing, a new app included: it is Lamp's own copy, beside a page Lamp opens, so it doesn't
get in the person's way, and this is the one thing you use in a new app. `look_at_app` with `sidebar: true` and
`page` (the https address of a real page it's for) shows it as Chrome would, light, dark and at large text, with the
app's window beside it, says what it measured, and whether the page fits browser.json; `use_app` with `sidebar: true`
and `page` clicks and types in it by target. Go through the whole path (read, then the answer, or read, check and
save), look at each state, check what the app keeps in the Mac window, fix what the look measured and what this
skill's questions find, and when it saves, delete what you saved while trying.

## What's above the page

Lamp's strip: the app's name, then a line saying what the page reads. It makes no offer: the page's offer row is
the only one, and its button uses the verb of browser.json's offer, whatever the page does with the page beside it.
A page that saves ("Save this recipe to Recipe Box") says "Save" ("Save…" when a check comes first), not "Read This
Recipe", "Add" or "Keep"; one that answers says its own verb ("Explain", "Translate", "Check"). The page's heading
names what it shows, not the app, which the strip already names: the collection for a page that keeps things ("My
Recipes", "Reading List"), what the answer is about for one that answers.

## Set it up

- `<html data-tint="green" data-lamp-reads="page">`, then `/lamp.css`, then your `app.css`, then `/lamp.js` and
  `app.js` (never inline).
- `/lamp.css` is the whole look, light and dark: colours, type, groups, rows, buttons, fields, the focus ring, and
  the strip takes its colours from it. Choose the tint nearest the window's accent colour: `blue` (the default),
  `green`, `orange`, `red`, `pink`, `purple`, `indigo`, `teal` or `brown`. Each is Apple's system colour, with
  text and button shades measured to read in both appearances.
- `app.css` holds only what your own items need (a grid's columns, a picture's size). Never set colours, fonts,
  backgrounds, borders, shadows, radii or `--` variables there, and never margins, padding or widths on
  /lamp.css's parts (`.group`, `.segmented`, `.row`, …): they line up on one edge, and moving one breaks it. No
  Georgia, no web font, no gradient, no coloured page, no card shadows, no hover effects, no hand cursor.

## Lay out the page, top to bottom

1. The offer: one `.group.offer` row 12px under the strip (`<div class="page-top"></div>` first): what the page
   will work on (for a page that saves, the item as the app will keep it: its picture or symbol in a `.thumb`, its
   name, where it's from), and one `button.primary.capsule` on the right.
2. A status line (`<p class="status" role="status">`).

A page that keeps things then has:

3. Its settings, when the items are judged against something the person sets (see below): one line.
4. The collection header: `<div class="collection-header"><h1>My Recipes</h1><span class="count">4 recipes</span></div>`.
5. The items.
6. An empty state for when nothing is saved yet.

The check before saving replaces the offer and the list while it's open (`hidden` on both), so the draft has the
pane to itself. So does editing the settings.

A page that answers (explains, summarises, translates, checks) has the answer in their place: a heading for what it's
about, then the answer in `.group`s (paragraphs, or rows for a list of points), hidden until there is one, and
before the first answer one sentence in the empty state on what the button does.

The pane is short and the items or the answer are what it's opened for: the first shows within the top third of the
pane, and nothing that stays on the page is taller than the list beside it.

## Settings are one line with Edit

What the person sets once and the app uses after (limits, a budget, servings, a start time, units) is glanced at, not
worked in. Show it as one line, never as a form that stays open:

```html
<div class="section-header"><span>My Space</span><button class="plain" id="edit">Edit</button></div>
<div class="group"><div class="row"><p class="facts-line num" id="summary"></p></div></div>
```

The line gives each value short, with its unit (`W 30 in`, `D 12 in`, `$100`), one `span` each; a value not set yet
is left out, and with nothing set the line says so ("No limits set") and the button says "Set…". Edit puts the
fields in place of the offer and the list, as the check before saving does: a `.collection-header` naming them, a
`.group` of `.field` rows (a choice such as inches or centimetres is a `.segmented` above them, part of the settings,
not a control of its own on the page), and a `.bottom-bar` with Cancel and Done. Done saves, redraws the line and the
verdicts, and puts the list back.

## Draw the items as the app's window does

Same facts in the same order, same sorting and grouping, same symbols. Choose the container by the content:

- **Rows** (`.group` of `.row.has-thumb`) for things with a status or a schedule (plants, tasks, orders): a 44px
  picture or symbol tile, a semibold name, a `.meta` line, and a trailing value or `.pill`. Put urgency into the
  structure: sections such as "Water Today" and "Coming Up", sorted by date, as Reminders does, never a list
  where today and next month look the same.
- **Reading rows** (`.row.has-dot`) for text people come back to: the unread `.dot`, a two-line title, a two-line
  summary and a `.meta` line (site, read time). Add a thumbnail only for an item that has its own picture, and
  leave no space when it hasn't. "Unread | All" goes in a `.segmented` control above the list.
- **Cards** (`.grid` of `.card`) only when nearly every item has a good picture of its own and people pick by it.
  Otherwise rows.

A row's `.meta` gives the facts people choose by, from the item itself, in the units they set: a product's size and
price (`31.5 × 11 × 79.5 in`, `$79`), a recipe's time and servings, a place's hours. When the app judges the item,
these are the facts it judged, so the verdict can be checked without opening the row. Then where it's from.

## One verdict per item, the problem loudest

When the app judges each item (fits or not, over budget, in stock, due), the row shows one verdict, in `.trailing`,
with `.verdict` and one of `.bad`, `.good` or `.unknown`:

```html
<div class="trailing"><span class="verdict bad"><span class="sym" style="--sym:url(/symbols/xmark.png)"></span>Too Wide</span></div>
```

- Several checks make one verdict, the worst: any that fails names it ("Too Wide", "Over Budget"; with more than
  one, the whole: "Too Large", "Doesn't Fit"), else any unknown ("Height Unknown"), else all well ("Fits").
- What needs the person is what stands out: a problem is red (`.bad`, `xmark`), all well is the tint (`.good`,
  `checkmark`) or nothing at all, unknown is grey (`.unknown`, `questionmark`). Never a grey or faint problem beside
  a bold or coloured "Fits", and never two badges saying the same thing.
- The check by check breakdown is not the row's: it's where the row opens (the window). Never a line per check in
  the row.

`.facts-line` puts a "·" between its spans and breaks between them: give it short plain facts (a size, a price, a
site), never symbols, verdicts or sentences, and never type a "·", "|" or "/" of your own between things.

No chevrons unless a row opens a detail view. A row that does something (opens the item in the app) is
`role="button"` with `tabindex="0"`, Enter and Space, never a link to `#`. No search field on a short list.

## Pictures show the actual item, or a symbol

A picture goes on an item only when it is that item: this recipe's photo, this plant's photo. Never a picture of
something nearby (a monstera on a fiddle-leaf fig, a coffee on a latte recipe), a stock photo, an illustration
standing in for it, or decoration. The page loads nothing from the internet, so a picture comes from the app:
`/assets/<file>` for the app's own files, or a picture the app keeps with the item (fetched in Swift from the
page's own image of that item, such as a recipe's photo, stored with the item, and handed to the page as a
`data:` URL). Without one, use the item's symbol on a tint wash: `<span class="thumb placeholder"><span class="sym"
style="--sym:url(/symbols/fork.knife.png)"></span></span>`, chosen by kind (`fish.fill` for a fish recipe,
`sunrise.fill` for breakfast, `leaf.fill` for a plant), else the app's one symbol.

Symbols are SF Symbols the app draws: `/symbols/<name>.png` used as a mask, `<span class="sym"
style="--sym:url(/symbols/drop.fill.png)"></span>`, sized by `font-size` and coloured by `color`, so one black
picture works in light, dark and any tint. Don't add `?color=`: a colour baked in is wrong in the other appearance.

## Every state, in the page

A page that saves goes through all of these, an article or a link too: nothing is saved straight from the offer
(choosing the app's right-click item, 8, is the one way past the check step). A page that explains, summarises,
translates or answers has Reading, its answer in place of 3 to 5, and a failure as in 6.

1. **Ready**: the offer row, and the list (or the empty state: a symbol, a title such as "No Recipes Yet", and one
   sentence on how to fill it).
2. **Reading**: only after a click (`lamp.readPage()` works only then). The button says "Reading…" and is disabled.
3. **Check before saving**: what was read, in a `.group` of `.field` rows (`<label>` beside its `<input>`), only the
   meaningful fields (name, schedule, ingredients), never ones the app fills in itself (the date saved). A
   `.bottom-bar` with Cancel and the prominent Save. Focus goes to the first field. Cancel writes nothing and puts
   the offer and list back.
4. **Saving**: the button says "Saving…"; it and Cancel are disabled until the write settles, so a slow save can't
   land on top of another draft. One write at a time.
5. **Saved**: only after the app says it saved. One confirmation, in the status line ("Peace lily saved to My
   Plants."), and the item in the list, where its row opens it, with focus on that row. Never a disabled "Saved"
   button and a "Saved" message both. The offer goes back to "Save…": the sidebar stays open while the tab moves on
   to other pages and isn't told when it does, so the offer must always be ready to save the next one. The app
   keeps one copy per item (by its URL or identity), so saving the same page again updates it.
6. **Failed save**: the app's message in the status line with `.error`, everything typed kept, focus back on Save to
   try again.
7. **Changed elsewhere**: `lamp.onChange(show)` redraws when the window or another tab changed the items.
8. **From the right-click item** (only when browser.json has a `menu`): `lamp.onMenu(…)` runs when the person chose
   it, and that choice is their click and their say-so. It does whatever the item says, at once, with the same calls
   as the page's own button: Reading…, then the job. An explanation, summary, translation or answer shows as the
   button shows it. A save goes through with no check step (Saving…, then Saved with the new row focused, where it
   opens to change or remove it). A failure shows as in 6; for a save, what was read is put in the check step so
   nothing is lost.

Build everything with `createElement` and `textContent`, never `innerHTML` with data: the words came from a web page.

## Words

The app's nouns ("Saved to My Plants"), never Lamp's workings. Title Case for titles and buttons ("Save Plant",
"Water Today"), sentence case for everything else. Short: a status line is one line.

## The parts /lamp.css has

- Page: `.page-top`, `.collection-header` (`h1`, `.count`), `.section-header`, `.section-footer`, `.status`
  (`.error`), `.empty` (`.sym`, `.title`, `p`).
- Lists: `.group`; `.row` with `.has-thumb` or `.has-dot`, holding `.thumb`, `.main` (`.title-line`, `.meta` of
  `span`s, `.clamp-1`/`.clamp-2`), `.trailing`; `.dot`; `.pill` (`.neutral`); `.verdict` (`.bad`, `.good`,
  `.unknown`: a symbol, then a word or two); `.facts-line` of `span`s (a line of facts that wraps between facts,
  never inside one).
- Pictures: `.thumb` (`--thumb` for its size; `.placeholder` for a symbol on the tint wash), `.grid` of `.card`
  (`.picture`, `.title-line`, `.meta`).
- Controls: `button` (grey), `.primary` (the tint), `.tinted`, `.plain`, `.capsule`; `.segmented` with
  `aria-pressed`; `.field` rows; `.bottom-bar`; `.selectable` on words people may copy (the rest isn't selectable,
  as in a Mac app).
- Type: `h1` the collection or the answer's subject (20px bold), row titles 13px semibold, body 13px, meta 12px, nothing under 11px;
  `.secondary`, `.tint`, `.num` for counts and dates.

Large text rearranges by itself: at 200% zoom or a bigger font the offer's button goes under its words, fields put
their label above, trailing values go under the title and a grid becomes one column. Keep your own CSS from undoing
it (no fixed heights, no `white-space: nowrap` on titles, no widths in px wider than 150).

## A page to start from

This one keeps things (a plant care app); a page that answers comes after it.

```html
<!doctype html><html lang="en" data-tint="green" data-lamp-reads="page"><head><meta charset="utf-8">
<link rel="stylesheet" href="/lamp.css"><link rel="stylesheet" href="app.css">
<script src="/lamp.js"></script><script src="app.js" defer></script></head><body>
<div class="page-top"></div>
<div class="group offer" id="offer">
  <span class="thumb placeholder" id="offer-picture"><span class="sym" style="--sym:url(/symbols/leaf.fill.png)"></span></span>
  <div class="main"><p class="headline clamp-2" id="offer-title">This plant</p><p class="facts-line" id="offer-detail"></p></div>
  <button class="primary capsule" id="save">Save…</button>
</div>
<p class="status" id="status" role="status"></p>
<section id="check" hidden aria-label="Check before saving">
  <div class="collection-header"><h1>New Plant</h1></div>
  <div class="group">
    <div class="field"><label for="name">Name</label><input id="name"></div>
    <div class="field"><label for="every">Water every</label><input id="every"></div>
  </div>
  <p class="section-footer">Read from this page. Change anything that’s wrong before you save.</p>
  <div class="bottom-bar"><button id="cancel">Cancel</button><button class="primary" id="keep">Save Plant</button></div>
</section>
<section id="list">
  <div class="collection-header"><h1>My Plants</h1><span class="count" id="count"></span></div>
  <div class="group" id="saved"></div>
  <div class="empty" id="empty" hidden><span class="sym" style="--sym:url(/symbols/leaf.png)"></span>
    <p class="title">No Plants Yet</p><p>Save a plant from its care guide and it shows up here.</p></div>
</section>
</body></html>
```

```js
// app.js: the calls ("list", "preview", "save", "open") are this app's own, answered by LampBrowser.startPage.
const $ = id => document.getElementById(id);
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
const sym = name => { const s = el("span", "sym"); s.style.setProperty("--sym", `url(/symbols/${name}.png)`); return s; };
let draft = null;

function picture(item) {   // the item's own picture, else its symbol
  if (item.picture) { const img = el("img", "thumb"); img.alt = ""; img.src = item.picture; return img; }
  const p = el("span", "thumb placeholder"); p.append(sym(item.symbol || "leaf.fill")); return p;
}
function row(item) {   // as the window draws the item
  const r = el("div", "row has-thumb"), main = el("div", "main"), meta = el("span", "meta"), fact = el("span");
  fact.append(sym("drop.fill"), "Every " + item.every); meta.append(fact);
  main.append(el("span", "title-line clamp-1", item.name), meta);
  r.append(picture(item), main, el("div", "trailing", item.due));
  r.setAttribute("role", "button"); r.tabIndex = 0; r.dataset.id = item.id;
  r.onclick = () => lamp.call("open", {id: item.id});
  r.onkeydown = e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); r.click(); } };
  return r;
}
async function show() {
  const saved = await lamp.call("list");
  $("saved").replaceChildren(...saved.map(row));
  $("count").textContent = saved.length ? saved.length + (saved.length === 1 ? " plant" : " plants") : "";
  $("saved").hidden = !saved.length; $("empty").hidden = !!saved.length;
}
function status(text, error) { $("status").textContent = text; $("status").classList.toggle("error", !!error); }
function checking(on) { $("check").hidden = !on; $("offer").hidden = on; $("list").hidden = on; }

$("save").onclick = async () => {
  const b = $("save"); b.disabled = true; b.textContent = "Reading…"; status("");
  try {
    draft = await lamp.call("preview", await lamp.readPage());
    $("name").value = draft.name; $("every").value = draft.every;
    checking(true); $("name").focus();
  } catch (e) { status(e.message, true); }
  b.disabled = false; b.textContent = "Save…";
};
$("cancel").onclick = () => { draft = null; checking(false); $("save").focus(); };
$("keep").onclick = async () => {
  const b = $("keep"), cancel = $("cancel"); if (b.disabled) return;
  b.disabled = cancel.disabled = true; b.textContent = "Saving…"; status("");
  try {
    const item = await lamp.call("save", {...draft, name: $("name").value, every: $("every").value});
    draft = null; checking(false);
    await show();
    status(item.name + " saved to My Plants.");
    document.querySelector(`[data-id="${CSS.escape(String(item.id))}"]`)?.focus();
  } catch (e) { status(e.message, true); b.focus(); }
  b.disabled = cancel.disabled = false; b.textContent = "Save Plant";
};
// A right-click item "Save to My Plants" would do the button's whole job at once: read, save, show it saved.
lamp.onMenu(async () => {
  const b = $("save"); b.disabled = true; b.textContent = "Reading…"; status("");
  try {
    draft = await lamp.call("preview", await lamp.readPage());
    b.textContent = "Saving…";
    const item = await lamp.call("save", draft);
    draft = null; checking(false); await show();
    status(item.name + " saved to My Plants.");
    document.querySelector(`[data-id="${CSS.escape(String(item.id))}"]`)?.focus();
  } catch (e) {
    status(e.message, true);
    if (draft) { $("name").value = draft.name; $("every").value = draft.every; checking(true); }
  }
  b.disabled = false; b.textContent = "Save…";
});
lamp.onChange(show);
show();
```

A page that answers instead of keeping things is shorter. For "Explain in Plain Words", the page's own button and its
right-click item run the same function, which reads the page, asks the app (which asks its AI, given the page as
`data:`) and shows the answer:

```js
async function explain() {
  const b = $("explain"); b.disabled = true; b.textContent = "Reading…"; status("");
  try {
    const answer = await lamp.call("explain", await lamp.readPage());
    $("answer").replaceChildren(...answer.paragraphs.map(p => el("p", null, p)));
    $("answer-group").hidden = false;
  } catch (e) { status(e.message, true); }
  b.disabled = false; b.textContent = "Explain";
}
$("explain").onclick = explain;
lamp.onMenu(explain);
```

## Check it, light, dark and large

`look_at_app` with `sidebar` and a real `page` shows the page light, dark and at 200% zoom side by side, with the
app's window, and lists what Lamp measured: words under 4.5:1 contrast, a face that isn't the system's, words under
11px, pictures that didn't load, sideways scrolling, clipped words at 200%, and a part out of line with the
groups. Fix every one. Then go through
every state with `use_app` (a page that saves: read, check, cancel, read, save, saved, the item in the window; a page
that answers: read, the answer, a failure; with a right-click item, also `use_app`'s `menu`), look at each, and judge
the pictures as Apple would:

1. Squint: a Mac list pane (grey ground, white rounded groups) or a web page (borders, boxes in boxes, a coloured
   page, a big button bar)?
2. Under the strip: one action, browser.json's verb, obvious what it does with the page, little height before the
   first item or the answer?
3. Does every picture show the item it's on? Would a symbol be more honest?
4. Separators start at the words, rows at least 44px, group edges in line with the titles?
5. Each item as the window shows it, the urgent ones first, its row giving the facts people choose by?
6. One verdict per row, and a problem the first thing the eye lands on, not the faintest?
7. Settings a line with Edit, not an open form? Nothing kept on the page taller than the list?
8. Dark: neutral grey, no outlines, the tint still readable?
9. At 200%: nothing cut off without an ellipsis, no fact split across lines, the offer's title not squeezed away?
