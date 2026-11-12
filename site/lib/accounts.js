// A maker's account: a username and the email they confirmed, which their links go under (lamp.dev/<username>/<app>).
// There are no passwords. Asking for one (`POST /api/accounts`, from Lamp's Share Link card or `lamp account`) answers
// a key the asker's Lamp keeps and sends an email with a link; once that's opened, the key is the account's, and a share
// sent with it (`X-Lamp-Account`) is its maker's. Asked again with an address that has an account already, it's a
// sign-in: another Lamp, on another computer, gets a key of its own the same way. The browser the email's link is opened
// in is signed in too (`ACCOUNT_COOKIE`), so ideas sent from it are by the username. Someone who sent an idea with their
// address is asked to confirm it the same way (`askToConfirm`): its link signs them in, or makes them an account with a
// username they choose, and only then do emails about their ideas go to it.

import { randomBytes } from "node:crypto";
import { isIP } from "node:net";
import { reserve } from "./quota.js";
import { accountOf, cloudStore, cookieKey, hashSecret, newSecret, sendMail, signInCookie, signOutCookie } from "./shared-wishes.js";

/** A username: 2 to 30 lowercase letters, digits and dashes, starting and ending with a letter or digit. */
const USERNAME = /^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])$/;
/** What the site's own addresses use, and words that would read as Lamp's. */
const RESERVED = new Set(["w", "api", "ideas", "changelog", "install", "download", "about", "help", "docs", "blog", "login", "signin",
  "signup", "account", "accounts", "settings", "admin", "lamp", "lampdev", "support", "terms", "privacy", "security", "status",
  "new", "play", "app", "apps", "games", "explore", "_astro", "static", "assets", "public", "favicon-ico", "robots-txt"]);
export const isUsername = (name) => typeof name === "string" && USERNAME.test(name) && !RESERVED.has(name) && !name.includes("--");

const EMAIL = /^[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[^\s@<>()",;:]+$/;
// A handful an hour from one place, and a ceiling overall.
export const ACCOUNT_QUOTAS = [
  { name: "account-ip", perIP: true, limit: 10, seconds: 3600 },
  { name: "account-day", limit: 2000, seconds: 86400 },
];

const reply = (status, body) => Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
const page = (status, words, headers = {}) => new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Lamp</title>`
  + `<body style="font:16px/1.5 -apple-system,system-ui,sans-serif;max-width:32rem;margin:15vh auto;padding:0 1rem;color:#2b2622;background:#f6f1e7">`
  + `<p>${words}</p></body>`, { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Robots-Tag": "noindex", ...headers } });
/** A username from what someone called themselves, or their address: "Sam Rivera" → "sam-rivera". */
export const suggestedUsername = (name, email = "") => {
  const from = (text) => String(text ?? "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30).replace(/-+$/, "");
  const name1 = from(name);
  return isUsername(name1) ? name1 : from(email.split("@")[0]);
};
const escaped = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** The confirm link's page for someone who sent an idea: sign in to the address's account, or choose a username. */
function confirmPage(token, waiting, existing, problem = "") {
  const action = `/api/accounts?confirm=${token}`;
  const button = 'style="font:inherit;padding:.5rem 1rem;border:0;border-radius:8px;background:#2b2622;color:#f6f1e7;cursor:pointer"';
  return page(problem ? 400 : 200, existing
    ? `Confirm <b>${escaped(waiting.email)}</b> to hear back about your ideas, signed in as <b>${escaped(existing)}</b>.</p>`
      + `<form method="post" action="${action}"><button ${button}>Confirm</button></form><p>`
    : `Confirm <b>${escaped(waiting.email)}</b> to hear back about your ideas. Choose a username: it shows with the ideas you send.</p>`
      + (problem ? `<p style="color:#a33">${problem}</p>` : "")
      + `<form method="post" action="${action}" style="display:flex;gap:.5rem;flex-wrap:wrap"><label style="flex:1 1 12rem">`
      + `<input name="username" required minlength="2" maxlength="30" pattern="[a-z0-9-]+" autocapitalize="none" spellcheck="false" aria-label="Username"`
      + ` value="${escaped(suggestedUsername(waiting.suggested, waiting.email))}" style="font:inherit;width:100%;box-sizing:border-box;padding:.45rem .6rem;border:1px solid #c9bfae;border-radius:8px"></label>`
      + `<button ${button}>Confirm</button></form><p>`);
}

export function createAccountHandler({ env = process.env, fetcher = fetch, store, limited = true, now = () => new Date() } = {}) {
  return async (request) => {
    const url = new URL(request.url);
    let kept;
    try { kept = store ?? cloudStore(env, fetcher); } catch { return reply(503, { error: "service_unavailable" }); }

    if (request.method === "GET") {
      const token = url.searchParams.get("confirm");
      // The link in the email: the account made, or another Lamp signed in to it.
      if (token !== null) {
        if (!/^[0-9a-f]{32}$/.test(token)) return page(404, "This link isn't one Lamp sent.");
        try {
          const waiting = await kept.accountWaiting(token);
          if (!waiting) return page(410, "This link has been used already, or it's more than a day old. Ask Lamp for another.");
          // Someone who sent an idea: a button, so a mail scanner opening the link uses nothing up.
          if (waiting.browser) return confirmPage(token, waiting, await kept.accountForEmail(waiting.email.toLowerCase()));
          const account = await kept.account(waiting.name);
          if (!account && !(await kept.createAccount({ name: waiting.name, email: waiting.email, created: now().toISOString() }))) {
            return page(409, `Someone else took ${escaped(waiting.name)} first. Choose another username in Lamp.`);
          }
          if (account && account.email.toLowerCase() !== waiting.email.toLowerCase()) return page(409, `${escaped(waiting.name)} is someone else's. Choose another username in Lamp.`);
          await kept.addAccountKey(waiting.hash, waiting.name);
          const browser = newSecret();
          await kept.addAccountKey(hashSecret(browser), waiting.name);
          // Done only now, so a link whose first try failed partway works when it's opened again.
          await kept.doneWaiting(token);
          return page(200, `You're signed in to Lamp as <b>${escaped(waiting.name)}</b>. Your links go under lamp.dev/${escaped(waiting.name)}. You can close this page.`,
            { "Set-Cookie": signInCookie(browser, request.url) });
        } catch { return page(503, "Lamp's site couldn't do that just now. Try the link again in a moment."); }
      }
      // Whose a key is, for the Lamp that holds it (or the browser, by its cookie): its username once the email's link
      // was opened, else none yet.
      const key = /^Bearer (\S+)$/.exec(request.headers.get("authorization") || "")?.[1] ?? cookieKey(request);
      try { return reply(200, { username: await accountOf(kept, key) }); } catch { return reply(503, { error: "service_unavailable" }); }
    }

    if (!["POST", "DELETE"].includes(request.method)) return new Response(null, { status: 405, headers: { Allow: "GET, POST, DELETE" } });
    const origin = request.headers.get("origin");
    if (origin && origin !== url.origin) return reply(403, { error: "origin_not_allowed" });
    // Signing this browser out.
    if (request.method === "DELETE") return new Response(null, { status: 204, headers: { "Set-Cookie": signOutCookie(request.url), "Cache-Control": "no-store" } });
    // The confirm page's button: the browser signed in to the address's account, or one made with the username chosen.
    const confirming = url.searchParams.get("confirm");
    if (confirming !== null) {
      if (!/^[0-9a-f]{32}$/.test(confirming)) return page(404, "This link isn't one Lamp sent.");
      try {
        const waiting = await kept.accountWaiting(confirming);
        if (!waiting?.browser) return page(410, "This link has been used already, or it's more than a day old.");
        let name = await kept.accountForEmail(waiting.email.toLowerCase());
        if (!name) {
          let chosen = "";
          try { chosen = String(new URLSearchParams(await request.text()).get("username") ?? "").trim().toLowerCase(); } catch {}
          if (!isUsername(chosen)) return confirmPage(confirming, { ...waiting, suggested: chosen }, null, "A username is 2 to 30 lowercase letters, numbers and dashes.");
          if (await kept.account(chosen) || !(await kept.createAccount({ name: chosen, email: waiting.email, created: now().toISOString() }))) {
            return confirmPage(confirming, { ...waiting, suggested: chosen }, null, `${escaped(chosen)} is someone else's. Choose another.`);
          }
          name = chosen;
        }
        const browser = newSecret();
        await kept.addAccountKey(hashSecret(browser), name);
        await kept.doneWaiting(confirming);
        return page(200, `You're signed in to Lamp as <b>${escaped(name)}</b>. We'll email you about your ideas. You can close this page.`,
          { "Set-Cookie": signInCookie(browser, request.url) });
      } catch { return page(503, "Lamp's site couldn't do that just now. Try again in a moment."); }
    }
    let asked;
    try { asked = await request.json(); } catch { return reply(400, { error: "invalid_request" }); }
    const email = typeof asked?.email === "string" ? asked.email.trim() : "";
    if (email.length > 200 || !EMAIL.test(email)) return reply(400, { error: "invalid_email" });
    if (limited) {
      const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
      if (!isIP(ip) || !kept.limiter) return reply(503, { error: "service_unavailable" });
      let retry;
      try { retry = await reserve(kept.limiter, ip, ACCOUNT_QUOTAS, fetcher); } catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" });
    }
    try {
      // An address with an account already is signing in to it, whatever username was asked for; a new one claims its own.
      const existing = await kept.accountForEmail(email);
      const name = existing ?? (typeof asked?.username === "string" ? asked.username.trim().toLowerCase() : "");
      if (!existing) {
        if (!isUsername(name)) return reply(400, { error: "invalid_username" });
        if (await kept.account(name)) return reply(409, { error: "username_taken" });
      }
      const key = newSecret(), token = randomBytes(16).toString("hex");
      await kept.waitForAccount(token, { name, email, hash: hashSecret(key), at: now().toISOString() });
      const link = `${url.origin}/api/accounts?confirm=${token}`;
      const sent = await sendMail(env, fetcher, existing
        ? { to: [email], subject: `Sign in to Lamp as ${name}`, text: `To sign in to Lamp as ${name} on this computer, open this link:\n\n${link}\n\nIf you didn't ask for this, you can ignore this email.` }
        : { to: [email], subject: `Confirm your Lamp username, ${name}`, text: `Your apps will be shared at lamp.dev/${name}. To confirm the username, open this link:\n\n${link}\n\nIf you didn't ask for this, you can ignore this email.` });
      return reply(202, { username: name, key, existing: !!existing, sent });
    } catch { return reply(503, { error: "service_unavailable" }); }
  };
}
