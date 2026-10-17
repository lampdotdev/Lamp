// Handing the wish to Lamp, so nobody has to paste it. Lamp's side is Sources/Lamp/Wish.swift (and, for a
// starter, Sources/Lamp/Starters.swift): the two must agree on the marks, the links and the limit.

/** Lamp cuts whatever arrives to this many characters. */
export const WISH_LIMIT = 4000;
/** The attribute Lamp looks for in the clipboard's web form. */
export const WISH_MARK = "data-lamp-wish";
/** The attribute that names one of the apps Lamp comes with instead, for Lamp to open rather than make. */
export const STARTER_MARK = "data-lamp-starter";

const tidy = (text) => String(text ?? "").trim().slice(0, WISH_LIMIT).trim();

/**
 * The wish as the clipboard's web form: the same words inside an element carrying Lamp's mark. Browsers keep
 * the attribute when they tidy copied HTML (seen in Safari and Chrome; they drop comments and unknown tags).
 * The plain form beside it is only the words, so pasted anywhere but Lamp nothing shows.
 */
export function wishHTML(text) {
  const escaped = tidy(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  return `<span ${WISH_MARK}="1" style="white-space: pre-wrap">${escaped}</span>`;
}

/** The link that opens Lamp, on a Mac that has it, with the wish in a box. Nothing is sent until they say so. */
export function wishLink(text) {
  const wish = tidy(text);
  return wish ? `lamp://wish?text=${encodeURIComponent(wish)}` : null;
}

/**
 * Copies the wish with Lamp's mark. Resolves "marked" when Lamp will find it by itself, "plain" when only the
 * words could be copied (to paste by hand), and "none" when the browser refused both.
 * Call it straight from a press: Safari only lets a page copy while a press is being handled.
 */
export async function copyWish(text, { clipboard = globalThis.navigator?.clipboard, Item = globalThis.ClipboardItem } = {}) {
  const wish = tidy(text);
  if (!wish || !clipboard) return "none";
  try {
    if (clipboard.write && Item) {
      await clipboard.write([new Item({
        "text/plain": new Blob([wish], { type: "text/plain" }),
        "text/html": new Blob([wishHTML(wish)], { type: "text/html" }),
      })]);
      return "marked";
    }
  } catch {}
  try {
    await clipboard.writeText(wish);
    return "plain";
  } catch {
    return "none";
  }
}

// An example that is one of the apps Lamp comes with (its name in Resources/Starters/<folder>/starter.md) opens
// that app, put back on the desk if it isn't there, with its chat and the changes it suggests: the real thing
// rather than a wish to make it again.

/** The link that opens a starter on a Mac that has Lamp. */
export function starterLink(name) {
  const starter = String(name ?? "").trim();
  return starter ? `lamp://starter?name=${encodeURIComponent(starter)}` : null;
}

/** The starter as the clipboard's web form, for Lamp to open the first time it does. The plain form is its name. */
export function starterHTML(name) {
  const escaped = String(name ?? "").trim().replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  return `<span ${STARTER_MARK}="${escaped}">${escaped}</span>`;
}

/**
 * Copies a starter with its mark, for someone about to download Lamp. Resolves "marked" when Lamp will open it
 * by itself, and "none" otherwise: its name alone pasted into Lamp would make a new app, not open this one.
 * Call it straight from a press, as `copyWish`.
 */
export async function copyStarter(name, { clipboard = globalThis.navigator?.clipboard, Item = globalThis.ClipboardItem } = {}) {
  const starter = String(name ?? "").trim();
  if (!starter || !clipboard?.write || !Item) return "none";
  try {
    await clipboard.write([new Item({
      "text/plain": new Blob([starter], { type: "text/plain" }),
      "text/html": new Blob([starterHTML(starter)], { type: "text/html" }),
    })]);
    return "marked";
  } catch {
    return "none";
  }
}
