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
const escapeHTML = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/**
 * With a remix's origin, the mark's value says what to start from as a link's query would ("starter=newyork"), since the
 * mark is the attribute browsers are known to keep (`Wish.markedRemix` in Lamp); otherwise it's "1".
 */
export function wishHTML(text, origin = null) {
  const value = origin ? remixParams(origin).toString() : "1";
  return `<span ${WISH_MARK}="${escapeHTML(value)}" style="white-space: pre-wrap">${escapeHTML(tidy(text))}</span>`;
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
export async function copyWish(text, { clipboard = globalThis.navigator?.clipboard, Item = globalThis.ClipboardItem, origin = null } = {}) {
  const wish = tidy(text);
  // A remix is worth copying with no words: Lamp still opens on a copy of what it starts from. Lamp only looks at a
  // copy that has both forms, so the plain one is a space, which it trims to no request.
  if ((!wish && !origin) || !clipboard) return "none";
  try {
    if (clipboard.write && Item) {
      await clipboard.write([new Item({
        "text/plain": new Blob([wish || " "], { type: "text/plain" }),
        "text/html": new Blob([wishHTML(wish, origin)], { type: "text/html" }),
      })]);
      return "marked";
    }
  } catch {}
  if (!wish) return "none";
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
  return `lamp://wish?${query({ file: String(file), text: request })}`;
}

/**
 * What a remix starts from, read off a link (`?starter=newyork`, or `?repo=https://github.com/owner/name&commit=…`, beside
 * `ask`): a published page's Remix panel names it when the page is a starter's or a wish on GitHub (`RemixLink.Origin` in
 * Lamp). Only a starter's plain id, or an https github.com repository with a full 40-digit commit (a shallow fetch takes no abbreviation); null for anything else, and
 * for both at once. Lamp checks it all again (`Wish.remix`).
 */
export function remixFrom(search) {
  const params = new URLSearchParams(search ?? "");
  const starter = params.get("starter"), repo = params.get("repo"), commit = params.get("commit");
  if (starter !== null && repo === null) {
    return commit === null && /^[a-z0-9][a-z0-9-]{0,39}$/.test(starter) ? { starter } : null;
  }
  if (repo !== null && starter === null) {
    const found = /^https:\/\/github\.com\/([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9_][A-Za-z0-9_.-]{0,99})\/?$/.exec(repo);
    if (!found || (commit !== null && !/^[0-9a-fA-F]{40}$/.test(commit))) return null;
    const name = found[2].replace(/\.git$/, "");
    if (!name) return null;
    const origin = { repo: `https://github.com/${found[1]}/${name}`, owner: found[1], name };
    return commit === null ? origin : { ...origin, commit: commit.toLowerCase() };
  }
  return null;
}

/** A remix's origin as the parameters Lamp reads, in its link and in the mark's value. */
export function remixParams(origin) {
  return new URLSearchParams(origin.starter ? { starter: origin.starter } : { repo: origin.repo, ...(origin.commit ? { commit: origin.commit } : {}) });
}

/**
 * The link that opens Lamp, on a Mac that has it, on a fresh copy of what the remix starts from, with the request in its
 * chat's box (`lamp://wish?starter=…&text=…`). The request may be empty: the copy opens with an empty box.
 */
export function remixLink(origin, text) {
  if (!origin) return null;
  const request = tidy(text);
  return `lamp://wish?${query({ ...Object.fromEntries(remixParams(origin)), ...(request ? { text: request } : {}) })}`;
}

/** A query with spaces as %20, as `wishLink` writes one: Lamp reads "+" as a space too, but nothing need rely on it. */
const query = (pairs) => Object.entries(pairs).map(([key, value]) => `${key}=${encodeURIComponent(value)}`).join("&");

/**
 * The pictures a repository may show of itself, in the order to try them: the preview and drawn icon a starter's
 * repository keeps in .github/, then the icon a wish's shared file puts at its root (Put on GitHub). Only for an origin
 * `remixFrom` checked; raw.githubusercontent.com serves a public repository's files.
 */
export function repoPictures(origin) {
  if (!origin?.repo) return [];
  const base = `https://raw.githubusercontent.com/${origin.owner}/${origin.name}/${origin.commit ?? "HEAD"}/`;
  return [
    { src: `${base}.github/preview.png`, fit: "cover" },
    { src: `${base}.github/icon/icon.png`, fit: "contain" },
    { src: `${base}icon.png`, fit: "contain" },
  ];
}
