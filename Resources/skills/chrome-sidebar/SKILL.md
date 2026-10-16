---
name: chrome-sidebar
description: The app's page in Chrome's side panel on the Mac (Assets/Sidebar/), drawn as if Apple made it - the system look from /lamp.css with one tint, the app's own items, every state from reading to a failed save, and the checks to pass. Read before writing or changing the sidebar page.
---

# A sidebar page that looks as if Apple made it

The page sits in Chrome's side panel on the Mac, 320 to 420 points wide (about 360 most of the time), under Lamp's
strip. Draw it as a Mac app draws a narrow list pane: Apple's grey grouped background, white rounded groups, rows with
hairline separators that start where the words start, SF Pro, and one tint colour, used sparingly. That's the look
for every app. An app stands out only through its tint and its content (its items' pictures, its words, how it
sorts and groups them), the way Notes, Reminders and Podcasts share the system surfaces and are told apart by
theirs. It isn't an iPhone layout and it isn't a copy of the window's own theme.

## What's above the page

Lamp's strip: the app's name, then a line saying what the page reads. It makes no offer: the page's offer row is
the only one, and it uses the verb of browser.json's offer ("Save this recipe to Recipe Box"): the button says
"Save" ("Save…" when a check comes first), not "Read This Recipe", "Add" or "Keep". The page's heading names the
collection ("My Recipes", "Reading List"), not the app, which the strip already names.

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

1. The offer: one `.group.offer` row 12px under the strip (`<div class="page-top"></div>` first): the page's
   item as the app will keep it (its picture or symbol in a `.thumb`, its name, where it's from), and one
   `button.primary.capsule` on the right.
2. A status line (`<p class="status" role="status">`).
3. The collection header: `<div class="collection-header"><h1>My Recipes</h1><span class="count">4 recipes</span></div>`.
4. The items.
5. An empty state for when nothing is saved yet.

The check before saving replaces the offer and the list while it's open (`hidden` on both), so the draft has the
pane to itself.

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
(the right-click item, 8, is the one way that saves without the check step).

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
   it, and that choice is their click and their say-so. It does the whole job at once with the same calls as the
   buttons: Reading…, then for a page that saves, the save itself with no check step (Saving…, then Saved with the
   new row focused, where it opens to change or remove it), and for a page that answers, the answer. A failure
   shows as in 6, with what was read put in the check step so nothing is lost.

Build everything with `createElement` and `textContent`, never `innerHTML` with data: the words came from a web page.

## Words

The app's nouns ("Saved to My Plants"), never Lamp's workings. Title Case for titles and buttons ("Save Plant",
"Water Today"), sentence case for everything else. Short: a status line is one line.

## The parts /lamp.css has

- Page: `.page-top`, `.collection-header` (`h1`, `.count`), `.section-header`, `.section-footer`, `.status`
  (`.error`), `.empty` (`.sym`, `.title`, `p`).
- Lists: `.group`; `.row` with `.has-thumb` or `.has-dot`, holding `.thumb`, `.main` (`.title-line`, `.meta` of
  `span`s, `.clamp-1`/`.clamp-2`), `.trailing`; `.dot`; `.pill` (`.neutral`); `.facts-line` of `span`s (a line of
  facts that wraps between facts, never inside one).
- Pictures: `.thumb` (`--thumb` for its size; `.placeholder` for a symbol on the tint wash), `.grid` of `.card`
  (`.picture`, `.title-line`, `.meta`).
- Controls: `button` (grey), `.primary` (the tint), `.tinted`, `.plain`, `.capsule`; `.segmented` with
  `aria-pressed`; `.field` rows; `.bottom-bar`; `.selectable` on words people may copy (the rest isn't selectable,
  as in a Mac app).
- Type: `h1` the collection (20px bold), row titles 13px semibold, body 13px, meta 12px, nothing under 11px;
  `.secondary`, `.tint`, `.num` for counts and dates.

Large text rearranges by itself: at 200% zoom or a bigger font the offer's button goes under its words, fields put
their label above, trailing values go under the title and a grid becomes one column. Keep your own CSS from undoing
it (no fixed heights, no `white-space: nowrap` on titles, no widths in px wider than 150).

## A page to start from

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
// The right-click item "Save to My Plants": read, check by the app, save, show it saved.
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

## Check it, light, dark and large

`look_at_app` with `sidebar` and a real `page` shows the page light, dark and at 200% zoom side by side, with the
app's window, and lists what Lamp measured: words under 4.5:1 contrast, a face that isn't the system's, words under
11px, pictures that didn't load, sideways scrolling, clipped words at 200%, and a part out of line with the
groups. Fix every one. Then go through
every state with `use_app` (read, check, cancel, read, save, saved, the item in the window), look at each, and judge
the pictures as Apple would:

1. Squint: a Mac list pane (grey ground, white rounded groups) or a web page (borders, boxes in boxes, a coloured
   page, a big button bar)?
2. Under the strip: one action, browser.json's verb, obvious what it saves, little height before the first item?
3. Does every picture show the item it's on? Would a symbol be more honest?
4. Separators start at the words, rows at least 44px, group edges in line with the titles?
5. Each item as the window shows it, the urgent ones first?
6. Dark: neutral grey, no outlines, the tint still readable?
7. At 200%: nothing cut off without an ellipsis, no fact split across lines, the offer's title not squeezed away?
