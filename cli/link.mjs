// lamp.dev's API for a shared link (site/lib/shared-wishes.js, which the limits here are read from), for lamp's own
// `share` and for Lamp's app's Share Link card alike: a link made or changed, what it has now, its file or its playable
// page sent in parts, the ideas people send, and taking it down. Only the link's secret changes it; the secret is
// whoever shared it's alone, and is kept by whoever asks, never here.

import { FILE_LIMITS, LIMITS } from "../site/lib/shared-wishes.js";
import { Problem } from "./state.mjs";

/** The site links are made on: lamp.dev, or another given for trying this against a copy of the site. */
export const siteOrigin = () => (process.env.LAMP_SITE || "https://lamp.dev").replace(/\/+$/, "");

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const megabytes = (bytes) => `${(bytes / 1_000_000).toFixed(bytes < 10_000_000 ? 1 : 0)} MB`;

// What the site says when it turns something down, in plain words.
const REFUSALS = {
  invalid_wish: `the site didn't take the link's words or picture (a name of at most ${LIMITS.name} characters, words of at most ${LIMITS.words}, a line of at most ${LIMITS.line})`,
  invalid_page: "the site didn't take the page: it needs index.html at its top",
  invalid_part: "the site didn't take a part of the page",
  parts_missing: "a part of the page didn't reach the site: share again",
  file_too_large: `the page is more than the ${megabytes(FILE_LIMITS.total)} a link carries, packed`,
  rate_limited: "the site has taken as many as it takes for now: try again in a while",
  service_unavailable: "the site can't keep it just now: try again in a moment",
  not_found: "the link is no longer there",
};

/** The site couldn't be reached at all: offline, or the site is down. */
export class Unreachable extends Problem {}

/**
 * One request to the site. A request that's the same however often it arrives is tried again, `tries` times in all,
 * a little later each time, when the site can't be reached or can't answer just now; any other is sent once. A refusal
 * carries the status the site gave it. No redirect is followed: a link's secret goes to the site and nowhere else.
 */
export async function call(method, url, { secret, json, bytes, tries = 1 } = {}) {
  const headers = {
    ...(secret ? { authorization: `Bearer ${secret}` } : {}),
    ...(json ? { "content-type": "application/json" } : bytes ? { "content-type": "application/octet-stream" } : {}),
  };
  for (let attempt = 0; ; attempt++) {
    let answer = null;
    try { answer = await fetch(url, { method, headers, body: json ? JSON.stringify(json) : bytes, redirect: "manual", signal: AbortSignal.timeout(120_000) }); } catch {}
    if (answer && answer.status < 500) {
      const said = await answer.json().catch(() => null);
      if (answer.ok) return { status: answer.status, said: said ?? {} };
      const problem = new Problem(REFUSALS[said?.error] ?? `the site answered ${answer.status}`);
      problem.status = answer.status;
      throw problem;
    }
    if (attempt >= tries - 1) {
      if (answer) { const problem = new Problem(REFUSALS.service_unavailable); problem.status = answer.status; throw problem; }
      throw new Unreachable(`couldn't reach ${new URL(url).host}`);
    }
    await sleep(600 * 2 ** attempt);
  }
}

/** An address the site gave, only when it's on the site itself. */
function onSite(site, address) {
  try { const url = new URL(address), home = new URL(site); return url.protocol === home.protocol && url.host === home.host ? url.href : null; } catch { return null; }
}

/**
 * Makes the link, or changes what it shows (`earlier`: its id and secret), with `body` as the site takes it (its
 * name, line, words, who it's by, the questions its page asks, its shape, picture and icon). A link the site no longer
 * has is made again. Answers its id, its address and its secret.
 */
export async function publishLink({ site = siteOrigin(), body, earlier }) {
  if (earlier) {
    try {
      const { said } = await call("PUT", `${site}/api/wishes?id=${encodeURIComponent(earlier.id)}`, { secret: earlier.secret, json: body });
      // A change keeps the link; its address follows the name, so a rename shows in it (the old one still works).
      return { id: earlier.id, url: onSite(site, said.url) ?? earlier.url ?? null, secret: earlier.secret };
    } catch (error) { if (error.status !== 404) throw error; }
  }
  const { said } = await call("POST", `${site}/api/wishes`, { json: body });
  const url = onSite(site, said.url);
  if (typeof said.id !== "string" || typeof said.secret !== "string" || !url) throw new Problem("the site's answer couldn't be read");
  return { id: said.id, url, secret: said.secret };
}

/**
 * What a followed link has now: its name, who it's by (null for nobody), its file's version (0 with no file), and the
 * file's address, only from where the site keeps them. Null when it can't be asked, or is gone. Asks with nothing of
 * the person's.
 */
export async function latestOf({ site = siteOrigin(), id }) {
  let said;
  try { ({ said } = await call("GET", `${site}/api/wishes?id=${encodeURIComponent(id)}`)); } catch { return null; }
  if (said.format !== 1 || !Number.isInteger(said.version)) return null;
  let file = null;
  try { const url = new URL(said.file); if (url.protocol === "https:" || (url.protocol === "data:" && new URL(site).protocol === "http:")) file = url.href; } catch {}
  const by = typeof said.by === "string" ? said.by.trim().slice(0, LIMITS.by) : "";
  return { name: typeof said.name === "string" ? said.name : null, by: by || null, version: said.version, file };
}

const fileAddress = (site, id, more = "") => `${site}/api/wish-file?id=${encodeURIComponent(id)}${more}`;

/**
 * Sends the link's file in parts, and has the site put them together in place of any it had: the wish's file, or with
 * `page` its playable page, which the site unpacks and serves on the link's page. A part is the same whenever it's
 * sent, so one whose connection dropped goes again. Answers the version the site gave it.
 */
export async function sendFile({ site = siteOrigin(), link, bytes, page = false, said = () => {} }) {
  if (bytes.length > FILE_LIMITS.total) throw Object.assign(new Problem(`it's more than the ${megabytes(FILE_LIMITS.total)} a link carries`), { status: 413 });
  const what = page ? "&what=page" : "", count = Math.max(1, Math.ceil(bytes.length / FILE_LIMITS.part));
  for (let n = 0; n < count; n++) {
    said(`Sending ${page ? "the page" : "the file"}: part ${n + 1} of ${count}`);
    await call("PUT", fileAddress(site, link.id, `${what}&part=${n}&of=${count}`), { secret: link.secret, bytes: bytes.subarray(n * FILE_LIMITS.part, (n + 1) * FILE_LIMITS.part), tries: 4 });
  }
  return (await call("POST", fileAddress(site, link.id, what), { secret: link.secret })).said.version ?? null;
}

/** Takes the link's file away, which keeps showing the idea, and its page with it; with `page` only the page. */
export async function removeFile({ site = siteOrigin(), link, page = false }) {
  try { await call("DELETE", fileAddress(site, link.id, page ? "&what=page" : ""), { secret: link.secret, tries: 3 }); }
  catch (error) { if (error.status !== 404) throw error; }
}

/** The ideas sent to the link that are still open, oldest first: each with its number. Only the link's secret reads them. */
export async function ideasOf({ site = siteOrigin(), link }) {
  try { return (await call("GET", `${site}/api/wish-ideas?id=${encodeURIComponent(link.id)}`, { secret: link.secret })).said.ideas ?? []; }
  catch (error) { if (error.status === 404) return []; throw error; }
}

/** Lets an idea go: with `built` it's in, and the site first writes to whoever asked to hear. Whether it did. */
export async function removeIdea({ site = siteOrigin(), link, n, built = false }) {
  try {
    const { said } = await call("DELETE", `${site}/api/wish-ideas?id=${encodeURIComponent(link.id)}&n=${Number(n)}${built ? "&built=1" : ""}`, { secret: link.secret });
    return { notified: said.notified === true };
  } catch (error) { if (error.status === 404) return { notified: false }; throw error; }
}

/** Takes the link down, with its page and the ideas sent to it. A link the site no longer has is down already. */
export async function removeLink({ site = siteOrigin(), link }) {
  try { await call("DELETE", `${site}/api/wishes?id=${encodeURIComponent(link.id)}`, { secret: link.secret }); }
  catch (error) { if (error.status !== 404) throw error; }
}
