import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { cacheTags, findWish, isID } from "./shared-wishes.js";

// The page a shared wish's link opens (lamp.dev/w/<id>), drawn here rather than by Astro: the site is static and the
// wish is only known when the page is asked for. It looks like the site's wish card (WishDialog.astro), as a page of
// its own, and holds to the site's colours and its Download button (DownloadButton.astro). On a Mac it tries to open
// Lamp with the wish at once; with Lamp it's the landing page that downloads it, the wish copied for Lamp to find.

// The hand-off code is the site's own (wish.js), sent with the page so both ways in stay one.
const handOff = readFileSync(new URL("./wish.js", import.meta.url), "utf8");

const escape = (text) => String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
/** A summary for the card and search results: the line, or the start of the words. */
export function summary(wish) {
  if (wish.line) return wish.line;
  const words = wish.words.replace(/\s+/g, " ");
  return words.length > 160 ? `${words.slice(0, 157).replace(/\s+\S*$/, "")}…` : words;
}

const STYLE = `
:root { --page: #ffffff; --ink: #1d1d1f; --muted: #6e6e73; --panel: #f5f5f7; --rule: #d2d2d7; --graphite: #33302e; --link: #b04e0a;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif; color-scheme: light;
  -webkit-font-smoothing: antialiased; }
* { box-sizing: border-box; }
[hidden] { display: none !important; }
body { margin: 0; background: var(--panel); color: var(--ink); min-height: 100dvh; display: flex; flex-direction: column; }
h1, p { text-wrap: pretty; margin: 0; }
.bar { display: flex; justify-content: center; padding: 16px; }
.home { display: inline-flex; align-items: center; gap: 10px; height: 40px; padding: 0 14px 0 6px; border-radius: 999px; color: var(--ink);
  text-decoration: none; font-size: 16px; font-weight: 600; letter-spacing: -0.01em; }
.home:hover { background: rgb(0 0 0 / 0.04); }
.home img { width: 26px; height: 26px; }
main { flex: 1; display: flex; align-items: center; justify-content: center; padding: 8px 16px 48px; }
.wish { width: min(70rem, 100%); background: var(--page); border-radius: 28px; overflow: hidden;
  box-shadow: 0 30px 80px -30px rgb(0 0 0 / 0.3); display: grid; }
.stage { position: relative; overflow: hidden; background: var(--panel); }
.stage .backdrop { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; transform: scale(1.25); filter: blur(40px); opacity: 0.8; }
.stage .picture { position: relative; display: block; width: 100%; height: auto; max-height: 70vh; object-fit: contain; }
.words { padding: 24px; }
.title { display: flex; align-items: flex-start; gap: 16px; }
.title img { width: 64px; height: 64px; flex-shrink: 0; filter: drop-shadow(0 6px 12px rgb(0 0 0 / 0.18)); }
.title div { padding-top: 4px; }
.eyebrow { font-size: 14px; color: var(--muted); margin-bottom: 2px; }
h1 { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 30px;
  line-height: 1.15; font-weight: 700; letter-spacing: -0.02em; overflow-wrap: anywhere; }
.line { margin-top: 6px; font-size: 15px; line-height: 1.35; color: var(--muted); }
label { display: block; margin: 24px 0 10px; font-size: 15px; font-weight: 600; }
textarea { display: block; width: 100%; resize: none; border: 0; border-radius: 12px; padding: 14px; font: inherit; font-size: 17px;
  line-height: 1.6; color: var(--ink); background: var(--page); box-shadow: inset 0 0 0 1px var(--rule); transition: box-shadow .2s; }
textarea:focus { outline: none; box-shadow: inset 0 0 0 2px rgb(207 98 12 / 0.4); }
.finish { margin-top: 24px; display: flex; flex-direction: column; align-items: center; }
.buttons { display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 12px; }
.button { display: inline-flex; align-items: center; height: 52px; padding: 0 36px; border-radius: 999px; border: 0; cursor: pointer;
  font: inherit; font-size: 17px; font-weight: 600; text-decoration: none; white-space: nowrap;
  transition: transform .3s cubic-bezier(.34,1.56,.64,1); }
.button:hover { transform: scale(1.03); }
.button:active { transform: scale(0.98); }
.button:focus-visible { outline: 2px solid var(--link); outline-offset: 4px; }
/* Shaped like the site's Download button: the lamp's bright orange, white words with a faint shadow under them. */
.download { color: #fff; background: linear-gradient(to bottom, #ff8a24, #e65c00); text-shadow: 0 1px 1px rgb(140 50 0 / 0.35);
  box-shadow: 0 1px 3px rgb(0 0 0 / 0.18), inset 0 0 0 1px rgb(255 255 255 / 0.3); }
/* The Mac app's own buttons (Onboarding.swift's accent), for the way in that needs Lamp already. */
.open { color: #fff; background: linear-gradient(to bottom, var(--graphite), #141311); box-shadow: 0 1px 3px rgb(0 0 0 / 0.18); }
.next { margin-top: 12px; font-size: 14px; color: var(--muted); text-align: center; }
.mobile { display: none; }
@media (max-width: 639px), (pointer: coarse) { .desktop { display: none; } .mobile { display: inline; } }
@media (min-width: 640px) { .words { padding: 32px; } }
@media (min-width: 1024px) {
  .wish.pictured { grid-template-columns: 1.3fr 1fr; }
  .stage { display: flex; align-items: center; }
  .stage .picture { box-shadow: 0 20px 50px -20px rgb(0 0 0 / 0.35); }
  .words { padding: 40px; }
  .finish { align-items: flex-start; }
  .finish .buttons { justify-content: flex-start; }
  .finish .next { text-align: left; }
}
.gone { text-align: center; padding: 48px 24px; }
.gone img { width: 96px; height: 96px; opacity: 0.9; }
.gone h1 { margin-top: 24px; font-size: 34px; }
.gone p { margin-top: 12px; font-size: 18px; color: var(--muted); }
.gone a { display: inline-block; margin-top: 32px; color: var(--ink); font-weight: 500; text-underline-offset: 4px; text-decoration-color: rgb(0 0 0 / 0.2); }
.gone a:hover { text-decoration-color: rgb(0 0 0 / 0.6); }
`;

// What the page does: a Mac tries Lamp once as the page opens, since a page can't tell whether Lamp is there, and the
// button does again; Download copies the wish with Lamp's mark, as the site's other Download buttons do.
const SCRIPT = `
const page = document.querySelector("[data-shared]");
const text = page.querySelector("textarea");
const open = page.querySelector("[data-open]");
const download = page.querySelector("[data-download]");
const next = page.querySelector("[data-next]");
const fit = () => { text.style.height = "auto"; text.style.height = (text.scrollHeight + 2) + "px"; };
text.addEventListener("input", fit);
fit();
const mac = /Mac/.test(navigator.platform) && navigator.maxTouchPoints < 2;
open.hidden = !mac;
const go = () => { const link = wishLink(text.value); if (link) location.href = link; };
open.addEventListener("click", () => {
  go();
  next.textContent = "Didn't open? Download Lamp, then open this link again.";
});
// Once per visit to this wish, not again on a reload or on coming back to the page.
const tried = "lamp-shared-" + page.dataset.shared;
let first = true;
try { first = !sessionStorage.getItem(tried); sessionStorage.setItem(tried, "1"); } catch {}
if (mac && first) go();
download.addEventListener("click", () => {
  copyWish(text.value).then((copied) => {
    download.textContent = "Downloading…";
    next.textContent = copied === "marked" ? "Open Lamp when it's ready. Your wish will be there."
      : copied === "plain" ? "Your wish is copied. Paste it into Lamp when it's ready."
      : "Copy your wish, and paste it into Lamp when it's ready.";
  });
});
`;

function document({ title, description, head = "", body, nonce }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<meta name="description" content="${escape(description)}">
<meta name="robots" content="noindex">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<meta name="theme-color" content="#f5f5f7">
${head}<style nonce="${nonce}">${STYLE}</style>
</head>
<body>
<header class="bar"><a class="home" href="/"><img src="/favicon.png" alt="" width="26" height="26">Lamp</a></header>
<main>${body}</main>
</body>
</html>
`;
}

/** The page for a shared wish, with what X, iMessage and Slack read for its preview. */
export function wishPage(wish, { origin, downloadURL, nonce }) {
  const link = `${origin}/w/${wish.id}`;
  const card = `${origin}/w/${wish.id}/card.png?v=${encodeURIComponent(wish.updated ?? "")}`;
  const title = `${wish.name} · A wish for Lamp`;
  const description = summary(wish);
  const head = [
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
  ].join("\n") + "\n";
  const picture = wish.picture && `
<div class="stage">
  <img class="backdrop" src="${escape(wish.picture.url)}" alt="">
  <img class="picture" src="${escape(wish.picture.url)}" width="${wish.picture.width}" height="${wish.picture.height}" alt="A picture of ${escape(wish.name)}">
</div>`;
  const body = `
<article class="wish${picture ? " pictured" : ""}" data-shared="${escape(wish.id)}">${picture || ""}
<div class="words">
  <div class="title">
    ${wish.icon ? `<img src="${escape(wish.icon.url)}" alt="" width="64" height="64">` : `<img src="/apple-touch-icon.png" alt="" width="64" height="64">`}
    <div>
      <p class="eyebrow">A wish for Lamp</p>
      <h1>${escape(wish.name)}</h1>
      ${wish.line ? `<p class="line">${escape(wish.line)}</p>` : ""}
    </div>
  </div>
  <label for="wish-text">Make it yours, then give it to Lamp:</label>
  <textarea id="wish-text" rows="3">${escape(wish.words)}</textarea>
  <div class="finish">
    <div class="buttons">
      <button type="button" class="button open" data-open hidden>Open in Lamp</button>
      <a class="button download" data-download href="${escape(downloadURL)}"><span class="desktop">Download Lamp</span><span class="mobile">Download for Mac</span></a>
    </div>
    <p class="next" data-next>For Macs with Apple Silicon and macOS 14 Sonoma or later</p>
  </div>
</div>
</article>
<script type="module" nonce="${nonce}">
${handOff}
${SCRIPT}
</script>`;
  return document({ title, description, head, body, nonce });
}

/** The page for a link that leads nowhere: never shared, or taken down by the person who shared it. */
export function gonePage({ nonce, unavailable = false }) {
  const body = `
<div class="gone">
  <img src="/apple-touch-icon.png" alt="" width="96" height="96">
  <h1>${unavailable ? "This wish can't be shown right now." : "This wish isn't shared any more."}</h1>
  <p>${unavailable ? "Try again in a moment." : "The link may be mistyped, or whoever shared it took it down."}</p>
  <a href="/">Go to Lamp</a>
</div>`;
  return document({ title: "Lamp", description: "Make the apps you wish you had.", body, nonce });
}

/** The page's own rules: its scripts are only the one it carries, and its pictures come from here or Lamp's store. */
const policy = (nonce) => [
  "default-src 'none'", `script-src 'nonce-${nonce}'`, `style-src 'nonce-${nonce}'`,
  "img-src 'self' data: https://*.public.blob.vercel-storage.com", "base-uri 'none'", "form-action 'none'", "frame-ancestors 'none'",
].join("; ");

export function createPageHandler({ env = process.env, fetcher = fetch, store, downloadURL = "https://updates.lamp.dev/download/latest" } = {}) {
  return async (request) => {
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    const url = new URL(request.url);
    const id = url.searchParams.get("id");
    const nonce = randomBytes(16).toString("base64");
    const wish = isID(id) ? await findWish(id, { env, fetcher, store }) : null;
    const headers = { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": policy(nonce), "X-Robots-Tag": "noindex" };
    if (!wish) {
      return new Response(gonePage({ nonce, unavailable: wish === undefined }), {
        status: wish === undefined ? 503 : 404, headers: { ...headers, "Cache-Control": "no-store" },
      });
    }
    // The CDN keeps it a minute; a change or a removal takes it out at once (`cacheTags`).
    return new Response(wishPage(wish, { origin: url.origin, downloadURL, nonce }), {
      headers: { ...headers, ...cacheTags(wish.id), "Cache-Control": "public, max-age=0, s-maxage=60" },
    });
  };
}
