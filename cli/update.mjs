// Whether a newer lamp is out. For a lamp installed from npm (@lampdotdev/lamp): at most once a day a process of its own
// asks npm's registry, without holding up the command, and keeps what it heard; the next command says so in one line,
// once a day, with the command that updates it. lamp never updates a global install: it's the person's.
// For the copy in Lamp's app, run as the person's `lamp` (lamp.sh): lamp is published on npm at every change to main
// (`nightly`) as well as with each release (`latest`), much sooner than Lamp's app can be built, so at most once an hour
// the same background process fetches the newest of its channel into ~/.lamp/cli when it's newer than the app's own,
// and the launcher runs that one from then on, until the app has caught up. Lamp's own calls of lamp (LampCLI.swift)
// never do: the app and the lamp inside it are always the same.

import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, sep } from "node:path";
import { fileURLToPath } from "node:url";

const NAME = "@lampdotdev/lamp";
const DAY = 24 * 60 * 60 * 1000, HOUR = 60 * 60 * 1000;
const here = dirname(fileURLToPath(import.meta.url));
const cache = () => join(process.env.LAMP_DEV_HOME ? dirname(process.env.LAMP_DEV_HOME) : join(homedir(), ".lamp"), "update.json");

/** Whether this copy is one npm installed, and so one npm updates. */
const fromNpm = () => here.includes(`${sep}node_modules${sep}@lampdotdev${sep}lamp${sep}`);

// npm's package has its package.json at its top, beside cli/; Lamp's app carries lamp's own in cli/ (build.sh).
const own = () => {
  for (const file of [join(here, "..", "package.json"), join(here, "package.json")]) {
    try { const { name, version } = JSON.parse(readFileSync(file, "utf8")); if ((name === NAME || name === "lamp") && version) return version; } catch {}
  }
  return null;
};

/**
 * The npm channel a copy run as the person's `lamp` from Lamp's app follows: Lamp Nightly's, `nightly`; Lamp's, `latest`.
 * None for Lamp Dev (a build from source has its checkout's lamp) or any other copy.
 */
const channel = () => {
  if (!process.env.LAMP_FROM_APP || !process.env.LAMP_LAUNCHER) return null;
  const app = process.env.LAMP_APP ?? "";
  return app === "dev.lamp.host.nightly" ? "nightly" : app === "dev.lamp.host" ? "latest" : null;
};
/** Where fetched copies are kept, and the launcher's note of which to run (lamp.sh reads it). */
const fetched = () => join(dirname(cache()), "cli");
const read = () => { try { return JSON.parse(readFileSync(cache(), "utf8")); } catch { return {}; } };
const keep = (state) => { try { mkdirSync(dirname(cache()), { recursive: true }); writeFileSync(cache(), JSON.stringify(state)); } catch {} };

/** This lamp's version, and where it came from, for `lamp --version`. */
export function versionLine() {
  const mine = own() ?? "unknown";
  const app = process.env.LAMP_BUNDLED_VERSION;
  if (process.env.LAMP_FROM_APP && app && app !== mine) return `lamp ${mine} (fetched from npm, newer than the ${app} in Lamp's app)`;
  if (process.env.LAMP_FROM_APP) return `lamp ${mine} (in Lamp's app)`;
  return `lamp ${mine}${fromNpm() ? "" : " (from a checkout)"}`;
}

/**
 * Whether version a is newer than b, as semver orders them: by their numbers, a pre-release older than its release, and
 * two pre-releases by their parts in turn, numbers as numbers (0.36.2-nightly.10 after 0.36.2-nightly.9). Build
 * metadata (+…) says nothing about order.
 */
export function newer(a, b) {
  const parts = (version) => {
    const [main, ...rest] = String(version).split("+")[0].split("-");
    return { numbers: main.split(".").map(Number), pre: rest.length ? rest.join("-").split(".") : null };
  };
  const x = parts(a), y = parts(b);
  for (let i = 0; i < 3; i++) if ((x.numbers[i] || 0) !== (y.numbers[i] || 0)) return (x.numbers[i] || 0) > (y.numbers[i] || 0);
  if (!x.pre || !y.pre) return !x.pre && !!y.pre;
  for (let i = 0; i < Math.max(x.pre.length, y.pre.length); i++) {
    const p = x.pre[i], q = y.pre[i];
    if (p === undefined || q === undefined) return q === undefined;
    if (p === q) continue;
    const pn = /^\d+$/.test(p), qn = /^\d+$/.test(q);
    if (pn && qn) return Number(p) > Number(q);
    if (pn !== qn) return qn;   // a word part outranks a number part
    return p > q;
  }
  return false;
}

/**
 * The line to say, when there's a newer lamp than this one and it hasn't been said today; and a check of npm started
 * in the background when the last is a day old. Nothing for a copy npm didn't install, in CI, or with
 * LAMP_NO_UPDATE_CHECK set.
 */
export function updateNotice() {
  if (process.env.CI || process.env.LAMP_NO_UPDATE_CHECK) return null;
  if (channel()) {
    const state = read(), now = Date.now();
    if (!(state.fetchChecked > now - HOUR)) {
      try { spawn(process.execPath, [fileURLToPath(import.meta.url), "--fetch", channel()], { detached: true, stdio: "ignore" }).unref(); } catch {}
    }
    return null;
  }
  if (!fromNpm()) return null;
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

// The background fetch, for the copy in Lamp's app: the newest lamp of its channel, when it's newer than the app's own,
// checked against npm's integrity hash, unpacked into ~/.lamp/cli/<version>, and named for the launcher with the app's
// version it's newer than, so an app updated since runs its own again.
if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv[2] === "--fetch") {
  const tag = process.argv[3];
  keep({ ...read(), fetchChecked: Date.now() });
  const app = process.env.LAMP_BUNDLED_VERSION || own();
  try {
    const answer = await fetch(`https://registry.npmjs.org/${NAME.replace("/", "%2F")}/${encodeURIComponent(tag)}`, { signal: AbortSignal.timeout(8000) });
    const { version, dist } = answer.ok ? await answer.json() : {};
    const folder = join(fetched(), String(version));
    if (typeof version === "string" && /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/.test(version) && app && newer(version, app)
        && typeof dist?.tarball === "string" && /^sha512-/.test(dist?.integrity ?? "")) {
      if (!existsSync(join(folder, "package", "cli", "lamp.mjs"))) {
        const bytes = Buffer.from(await (await fetch(dist.tarball, { signal: AbortSignal.timeout(60000) })).arrayBuffer());
        if (`sha512-${createHash("sha512").update(bytes).digest("base64")}` !== dist.integrity) throw new Error("integrity");
        const part = `${folder}.part`;
        rmSync(part, { recursive: true, force: true });
        mkdirSync(part, { recursive: true });
        writeFileSync(join(part, "lamp.tgz"), bytes);
        if (spawnSync("tar", ["xzf", "lamp.tgz"], { cwd: part }).status !== 0) throw new Error("unpack");
        rmSync(join(part, "lamp.tgz"));
        rmSync(folder, { recursive: true, force: true });
        renameSync(part, folder);
      }
      // The one used until now is retired as of now: its week starts here, not from when it was fetched.
      let before = null;
      try { before = readFileSync(join(fetched(), "use"), "utf8").split("\n")[1] || null; } catch {}
      if (before && dirname(before) !== folder) { try { const now = new Date(); utimesSync(dirname(before), now, now); } catch {} }
      writeFileSync(join(fetched(), "use"), `${app}\n${join(folder, "package")}\n`);
      // Older ones go once they've been out of use a week (the launcher touches the one it runs, and the one retired above
      // was touched as it was): a `lamp dev` started from one may run for days, reading its files (libraries,
      // controllers) as it goes.
      for (const other of readdirSync(fetched())) {
        if (other === "use" || other === String(version) || other.endsWith(".part")) continue;
        try { if (statSync(join(fetched(), other)).mtimeMs < Date.now() - 7 * DAY) rmSync(join(fetched(), other), { recursive: true, force: true }); } catch {}
      }
      // The one in use is touched, so it's counted from when it was last named.
      try { const now = new Date(); utimesSync(folder, now, now); } catch {}
    }
  } catch {}
}
