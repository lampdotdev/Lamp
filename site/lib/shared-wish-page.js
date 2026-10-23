import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { cacheTags, findWish, isID } from "./shared-wishes.js";

// The page a shared wish's link opens (lamp.dev/w/<id>): the ideas page with that wish's card open on it, the same
// card the homepage's and the ideas page's wishes open in (WishDialog.astro), so a shared wish takes the site's one
// way into Lamp: Download copies it with Lamp's mark, and on a Mac the link under it opens Lamp with it (the card
// also tries that once as the page opens). Closed, the card leaves the visitor among more ideas. The site is static
// and the wish is only known when the page is asked for, so the page is the built ideas page (vercel.json bundles
// it with the function) with the wish and its preview put in here.

const escape = (text) => String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** A summary for the card and search results: the line, or the start of the words. */
export function summary(wish) {
  if (wish.line) return wish.line;
  const words = wish.words.replace(/\s+/g, " ");
  return words.length > 160 ? `${words.slice(0, 157).replace(/\s+\S*$/, "")}…` : words;
}

/** The built ideas page, read once. Null where there's none (`npm run dev` asks its own server instead). */
let built;
export function builtIdeasPage() {
  if (built === undefined) {
    try { built = readFileSync(new URL("../dist/ideas/index.html", import.meta.url), "utf8"); } catch { built = null; }
  }
  return built;
}

/** What X, iMessage and Slack read for the link's preview, in place of the ideas page's own. */
function previewTags(wish, origin) {
  const link = `${origin}/w/${wish.id}`;
  const card = `${origin}/w/${wish.id}/card.png?v=${encodeURIComponent(wish.updated ?? "")}`;
  const title = `${wish.name} · A wish for Lamp`;
  const description = summary(wish);
  return [
    `<title>${escape(title)}</title>`,
    `<meta name="description" content="${escape(description)}">`,
    `<meta name="robots" content="noindex">`,
    `<link rel="canonical" href="${escape(link)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Lamp">`,
    `<meta property="og:url" content="${escape(link)}">`,
    `<meta property="og:title" content="${escape(title)}">`,
    `<meta property="og:description" content="${escape(description)}">`,
    `<meta property="og:image" content="${escape(card)}">`,
    `<meta property="og:image:type" content="image/png">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta property="og:image:alt" content="${escape(`${wish.name}: ${description}`)}">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${escape(title)}">`,
    `<meta name="twitter:description" content="${escape(description)}">`,
    `<meta name="twitter:image" content="${escape(card)}">`,
  ].join("");
}

/** The ideas page with the shared wish's card open on it. Null when the page isn't the shape this expects. */
export function wishPage(template, wish, { origin }) {
  if (!template || !template.includes("</head>") || !template.includes("</body>")) return null;
  // Only the head's own: the page's icons carry titles of their own.
  const end = template.indexOf("</head>");
  const head = template.slice(0, end)
    .replace(/<title>[\s\S]*?<\/title>/, "")
    .replace(/<meta (?:name|property)="(?:description|og:[^"]*|twitter:[^"]*)"[^>]*>/g, "")
    .replace(/<link rel="canonical"[^>]*>/, "") + template.slice(end);
  // The card's own shape (WishDialog's Idea), its words kept from closing the script early.
  const card = JSON.stringify({
    id: wish.id, name: wish.name, about: wish.line, wish: wish.words,
    picture: wish.picture?.url ?? "", icon: wish.icon?.url ?? "",
  }).replace(/</g, "\\u003c").replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");
  return head
    .replace("</head>", () => `${previewTags(wish, origin)}</head>`)
    .replace("</body>", () => `<script type="application/json" id="shared-wish">${card}</script></body>`);
}

/** The page for a link that leads nowhere: never shared, or taken down by the person who shared it. */
export function gonePage({ nonce, unavailable = false }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lamp</title>
<meta name="robots" content="noindex">
<link rel="icon" type="image/png" href="/favicon.png">
<style nonce="${nonce}">
body { margin: 0; min-height: 100dvh; display: flex; align-items: center; justify-content: center; background: #fff; color: #1d1d1f;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif; -webkit-font-smoothing: antialiased; }
main { text-align: center; padding: 48px 24px; }
img { width: 96px; height: 96px; opacity: 0.9; }
h1 { margin: 24px 0 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-size: 34px; font-weight: 700; letter-spacing: -0.02em; text-wrap: pretty; }
p { margin: 12px 0 0; font-size: 18px; color: #6e6e73; }
a { display: inline-block; margin-top: 32px; color: #1d1d1f; font-weight: 500; text-underline-offset: 4px; text-decoration-color: rgb(0 0 0 / 0.2); }
a:hover { text-decoration-color: rgb(0 0 0 / 0.6); }
</style>
</head>
<body>
<main>
  <img src="/apple-touch-icon.png" alt="" width="96" height="96">
  <h1>${unavailable ? "This wish can't be shown right now." : "This wish isn't shared any more."}</h1>
  <p>${unavailable ? "Try again in a moment." : "The link may be mistyped, or whoever shared it took it down."}</p>
  <a href="/ideas">See ideas for wishes</a>
</main>
</body>
</html>
`;
}

const gonePolicy = (nonce) => `default-src 'none'; style-src 'nonce-${nonce}'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;

/**
 * `template` gives the ideas page as built: by default the one bundled with the function; `npm run dev` passes its
 * own server's.
 */
export function createPageHandler({ env = process.env, fetcher = fetch, store, template = async () => builtIdeasPage() } = {}) {
  return async (request) => {
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    const url = new URL(request.url);
    const id = url.searchParams.get("id");
    const wish = isID(id) ? await findWish(id, { env, fetcher, store }) : null;
    const page = wish && wishPage(await template(url.origin), wish, { origin: url.origin });
    if (!page) {
      const nonce = randomBytes(16).toString("base64");
      const unavailable = wish !== null;
      return new Response(gonePage({ nonce, unavailable }), {
        status: unavailable ? 503 : 404,
        headers: { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": gonePolicy(nonce), "X-Robots-Tag": "noindex", "Cache-Control": "no-store" },
      });
    }
    // The CDN keeps it a minute; a change or a removal takes it out at once (`cacheTags`).
    return new Response(page, {
      headers: { "Content-Type": "text/html; charset=utf-8", "X-Robots-Tag": "noindex", ...cacheTags(wish.id), "Cache-Control": "public, max-age=0, s-maxage=60" },
    });
  };
}
