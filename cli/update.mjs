// Whether a newer lamp is out, for a lamp installed from npm (@lampdotdev/lamp). The copy in Lamp's app updates with
// Lamp (Sparkle) and a checkout with its repository, so neither asks. At most once a day a process of its own asks npm's
// registry, without holding up the command, and keeps what it heard; the next command says so in one line, once a day,
// with the command that updates it. lamp never updates itself: a global install is the person's.

import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, sep } from "node:path";
import { fileURLToPath } from "node:url";

const NAME = "@lampdotdev/lamp";
const DAY = 24 * 60 * 60 * 1000;
const here = dirname(fileURLToPath(import.meta.url));
const cache = () => join(process.env.LAMP_DEV_HOME ? dirname(process.env.LAMP_DEV_HOME) : join(homedir(), ".lamp"), "update.json");

/** Whether this copy is one npm installed, and so one npm updates. */
const fromNpm = () => here.includes(`${sep}node_modules${sep}@lampdotdev${sep}lamp${sep}`);

const own = () => { try { return JSON.parse(readFileSync(join(here, "..", "package.json"), "utf8")).version ?? null; } catch { return null; } };
const read = () => { try { return JSON.parse(readFileSync(cache(), "utf8")); } catch { return {}; } };
const keep = (state) => { try { mkdirSync(dirname(cache()), { recursive: true }); writeFileSync(cache(), JSON.stringify(state)); } catch {} };

/** Whether version a is newer than b, by their numbers (a pre-release is older than its release). */
export function newer(a, b) {
  const parts = (version) => { const [main, pre] = String(version).split("-"); return { numbers: main.split(".").map(Number), pre: pre ?? null }; };
  const x = parts(a), y = parts(b);
  for (let i = 0; i < 3; i++) if ((x.numbers[i] || 0) !== (y.numbers[i] || 0)) return (x.numbers[i] || 0) > (y.numbers[i] || 0);
  return y.pre !== null && x.pre === null;
}

/**
 * The line to say, when there's a newer lamp than this one and it hasn't been said today; and a check of npm started
 * in the background when the last is a day old. Nothing for a copy npm didn't install, in CI, or with
 * LAMP_NO_UPDATE_CHECK set.
 */
export function updateNotice() {
  if (!fromNpm() || process.env.CI || process.env.LAMP_NO_UPDATE_CHECK) return null;
  const mine = own(), state = read(), now = Date.now();
  if (!(state.checked > now - DAY)) {
    try { spawn(process.execPath, [fileURLToPath(import.meta.url), "--check"], { detached: true, stdio: "ignore" }).unref(); } catch {}
  }
  if (!mine || !state.latest || !newer(state.latest, mine) || state.told > now - DAY) return null;
  keep({ ...state, told: now });
  return `lamp ${state.latest} is out (this is ${mine}): npm install -g ${NAME}`;
}

// The background check: npm's registry, a few seconds at most, and what it said kept for the next command.
if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv[2] === "--check") {
  const state = read();
  keep({ ...state, checked: Date.now() });
  try {
    const answer = await fetch(`https://registry.npmjs.org/${NAME.replace("/", "%2F")}/latest`, { signal: AbortSignal.timeout(5000) });
    const latest = answer.ok ? (await answer.json()).version : null;
    if (typeof latest === "string" && /^\d+\.\d+\.\d+/.test(latest)) keep({ ...read(), checked: Date.now(), latest });
  } catch {}
}
