// `lamp ai`: the AI for a page shared on lamp.dev, answered on this computer with the person's own Claude Code or
// Codex (ai.mjs), the way `lamp dev` answers a page it serves. A shared page is away from Lamp, so lamp.js asks here,
// at a port of this computer's own (127.0.0.1), where a browser lets an https page call plain http.
//
// Only the person decides which pages spend their subscription. Each shared link plays from an origin of its own
// (`playOrigin` in site/lib/shared-wishes.js: <the link's id in hex>.play.lamp.dev), which a browser always names in
// the request and a page can't change, so an approval is for one link's page: the first time it asks, the person is
// asked in the terminal, and the page is given a token it keeps and sends from then on. Nothing else is answered:
// another site, another link's page, or a request naming this computer by another name (a site that rebinds its own
// name to 127.0.0.1) is refused. Whether there's an AI here (`/ai/status` and the probes) is answered without one, so a
// page can say what it can do before anyone is asked.

import { createServer } from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { answer as answerAI, engine } from "./ai.mjs";

/** The port lamp.js on a shared page asks (`LOCAL_AI` there): one, fixed, since the page can't be told another. */
export const LOCAL_AI_PORT = 47423;
const PLAY_HOST = "play.lamp.dev";
const MOST = 2_000_000, AT_ONCE = 3, ASKING_FOR = 120_000;
const ROUTES = new Set(["/ai/status", "/ai", "/ai/act", "/ai/decide", "/ai/hear", "/ai/image"]);

const keptFile = () => join(process.env.LAMP_DEV_HOME || join(homedir(), ".lamp", "dev"), "shared-pages-ai.json");

/** The pages the person has let use their AI, by origin: `{ token, id, name, at }`. */
export function allowed() {
  try { const kept = JSON.parse(readFileSync(keptFile(), "utf8")); return kept && typeof kept === "object" ? kept : {}; } catch { return {}; }
}
function keep(all) {
  const file = keptFile();
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file + ".new", JSON.stringify(all, null, 2), { mode: 0o600 });
  renameSync(file + ".new", file);
}
/** Forgets every page let in: each asks again. */
export function forgetAllowed() { if (existsSync(keptFile())) rmSync(keptFile()); }

/** The link a shared page's origin plays, by its id, or null for any other origin. */
export function linkOf(origin) {
  let url;
  try { url = new URL(origin); } catch { return null; }
  if (url.protocol !== "https:" || url.port || !url.host.endsWith("." + PLAY_HOST)) return null;
  const hex = url.host.slice(0, -PLAY_HOST.length - 1);
  if (!/^(?:[0-9a-f]{2}){10}$/.test(hex)) return null;
  const id = Buffer.from(hex, "hex").toString();
  return /^[A-Za-z0-9]{10}$/.test(id) ? id : null;
}

const same = (a, b) => {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

/**
 * Answers shared pages' AI until it's closed. `ask(question, page)` puts a yes-or-no to the person and resolves true
 * for yes; by default it's the terminal's, and without a terminal nothing is let in. `answer(path, body, page)` is the
 * AI's [status, reply]: the person's Claude Code or Codex by default, Lamp's own AI when Lamp's app runs this
 * (`sharedPages` in calls.mjs). Resolves to the server once it listens.
 */
export async function serveLocalAI({ port = LOCAL_AI_PORT, ask = askInTerminal(), answer = answerAI, said = console.log } = {}) {
  const busy = new Map(), queued = new Map(), refused = new Set(), waiting = new Map();
  // A few of a page's requests run at once and the rest wait their turn, since lamp.js asks many at a time
  // (`LampAI.decideEach`) and takes a refusal as that item's answer.
  const turn = (origin) => {
    if ((busy.get(origin) || 0) < AT_ONCE) { busy.set(origin, (busy.get(origin) || 0) + 1); return Promise.resolve(); }
    return new Promise((go) => queued.set(origin, [...(queued.get(origin) || []), go]));
  };
  const done = (origin) => {
    const next = queued.get(origin)?.shift();
    if (next) next();
    else busy.set(origin, busy.get(origin) - 1);
  };
  // One question at a time in the terminal; a page that asks again while it's waiting gets the same answer, and one
  // the person said no to isn't asked about again while this runs.
  let asking = Promise.resolve();
  const askAbout = (origin, id, name) => {
    if (waiting.has(origin)) return waiting.get(origin);
    const asked = asking.then(async () => {
      const kept = allowed()[origin];
      if (kept) return kept.token;
      const titled = name ? `"${name}" ` : "A page ";
      const yes = await ask(`${titled}shared at lamp.dev/w/${id} wants to use your ${engineName()} here. Allow it?`, { id, name });
      if (!yes) { refused.add(origin); return null; }
      const token = randomBytes(32).toString("base64url");
      keep({ ...allowed(), [origin]: { token, id, name: name || "", at: new Date().toISOString() } });
      said(`Allowed ${name ? `"${name}"` : `lamp.dev/w/${id}`}. lamp ai --forget takes it back.`);
      return token;
    });
    asking = asked.catch(() => {});
    waiting.set(origin, asked);
    asked.finally(() => waiting.delete(origin));
    return asked;
  };

  const server = createServer(async (request, response) => {
    const origin = request.headers.origin || "";
    const id = linkOf(origin);
    const reply = (status, body) => {
      const headers = { "Content-Type": "application/json", "Cache-Control": "no-store", Vary: "Origin" };
      if (id) headers["Access-Control-Allow-Origin"] = origin;
      response.writeHead(status, headers);
      response.end(JSON.stringify(body));
    };
    // Only this computer's own name for itself: a site that points a name of its own at 127.0.0.1 is someone else.
    const host = String(request.headers.host || "").replace(/:\d+$/, "");
    if (host !== "127.0.0.1" && host !== "localhost") return reply(403, { error: "Not here." });
    if (!id) return reply(403, { error: "Only a page shared on lamp.dev can ask here." });
    const url = new URL(request.url, "http://127.0.0.1");
    if (request.method === "OPTIONS") {
      response.writeHead(204, {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
        "Access-Control-Allow-Private-Network": "true",
        "Access-Control-Max-Age": "600",
        Vary: "Origin",
      });
      return response.end();
    }
    if (request.method !== "POST") return reply(405, { error: "Method not allowed." });

    let body = {};
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > MOST) return reply(413, { error: "That's too much to ask at once." });
        chunks.push(chunk);
      }
      const text = Buffer.concat(chunks).toString();
      body = text ? JSON.parse(text) : {};
    } catch { return reply(400, { error: "That wasn't JSON." }); }

    if (url.pathname === "/pair") {
      if (refused.has(origin)) return reply(403, { error: "Not allowed on this computer." });
      const name = typeof body?.name === "string" ? body.name.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 60) : "";
      const token = await askAbout(origin, id, name);
      return token ? reply(200, { token }) : reply(403, { error: "Not allowed on this computer." });
    }
    if (!ROUTES.has(url.pathname)) return reply(404, { error: "Not found." });
    // What there is to answer with, asked before anyone is let in: only the routes whose probe asks no model.
    const asksNothing = url.pathname === "/ai/status" || (body?.probe === true && (url.pathname === "/ai/act" || url.pathname === "/ai/hear"));
    if (asksNothing) {
      const [status, answered] = await answer(url.pathname, url.pathname === "/ai/status" ? {} : { probe: true }, { id });
      return reply(status, answered);
    }
    const kept = allowed()[origin];
    const given = String(request.headers.authorization || "").replace(/^Bearer\s+/i, "");
    if (!kept || !same(given, kept.token)) return reply(401, { error: "This page isn't allowed to use the AI here yet." });
    await turn(origin);
    try {
      const [status, answered] = await answer(url.pathname, body, { id });
      reply(status, answered);
    } catch (error) {
      reply(502, { error: error?.message || "The AI didn't answer." });
    } finally {
      done(origin);
    }
  });
  await new Promise((done, fail) => { server.once("error", fail); server.listen(port, "127.0.0.1", () => { server.off("error", fail); done(); }); });
  return server;
}

const engineName = () => (engine() === "codex" ? "Codex" : "Claude Code");

/** A yes-or-no in the terminal, or always no without one. */
export function askInTerminal({ input = process.stdin, output = process.stdout } = {}) {
  return (question) => {
    if (!input.isTTY) {
      output.write(`${question} No: lamp ai can only ask in a terminal.\n`);
      return Promise.resolve(false);
    }
    const lines = createInterface({ input, output });
    return new Promise((done) => {
      const timer = setTimeout(() => { output.write("\nNo answer, so not allowed.\n"); lines.close(); done(false); }, ASKING_FOR);
      lines.question(`${question} [y/N] `, (said) => { clearTimeout(timer); lines.close(); done(/^y(es)?$/i.test(said.trim())); });
    });
  };
}
