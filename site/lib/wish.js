// Handing the wish to Lamp, so nobody has to paste it. Lamp's side is Sources/Lamp/Wish.swift: the two must
// agree on the mark, the link and the limit.

/** Lamp cuts whatever arrives to this many characters. */
export const WISH_LIMIT = 4000;
/** The attribute Lamp looks for in the clipboard's web form. */
export const WISH_MARK = "data-lamp-wish";

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

/** The most a request from an app's remix panel carries; the panel cuts there too (`RemixLink.askLimit`). */
export const ASK_LIMIT = 1000;

/**
 * A request brought by a link from an app's remix panel (`?ask=…`): what the person typed beside an app on a Mac
 * without Lamp, or on a published page. Null when the link brings none.
 */
export function askFrom(search) {
  const ask = new URLSearchParams(search ?? "").get("ask");
  const words = String(ask ?? "").trim().slice(0, ASK_LIMIT).trim();
  return words || null;
}

/** The wish's words with the request after them, as one wish for Lamp, within what Lamp takes. */
export function withAsk(wish, ask) {
  const words = tidy(wish), request = String(ask ?? "").trim().slice(0, ASK_LIMIT).trim();
  if (!request) return words;
  if (!words) return tidy(request);
  return tidy(`${words}\n\nThen: ${request}`);
}

/**
 * The link that opens Lamp, on a Mac that has it, on the exact shared wish (its file's address) with a request in the
 * box: what a shared wish's page offers when a request came with its link. Null without a file, or without a request.
 */
export function exactWishLink(file, ask) {
  const request = String(ask ?? "").trim().slice(0, ASK_LIMIT).trim();
  if (!file || !request) return null;
  const params = new URLSearchParams({ file: String(file), text: request });
  return `lamp://wish?${params}`;
}
