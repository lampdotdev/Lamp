// A page on one of the person's devices: packaged for the device's own host, put there, opened, looked at, stopped
// and taken off again, each through what the device's integration says (devices.mjs). An Xbox is the first: the page
// goes in Lamp's host for the console's own Chromium (Resources/WebHost), in a Windows package lamp makes and signs
// itself (msix.mjs), installed through the console's Device Portal. It's `DeviceApps` in Lamp's app, for a page.
//
// The package is made in lamp's own folder for the app, never in the app's: what goes to a device is what lamp read
// of the page as it packaged it.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Problem, stateOf } from "./state.mjs";
import { androidDeviceNamed, emulatorNamed, knowsAndroid, lookOnAndroid, putOnAndroid, removeFromAndroid, stopOnAndroid, useOnAndroid } from "./android.mjs";
import { Away, Runner, StillWorking, allKept, answersOn, devicesHome, integrationOf, isReady, kept, look, takesPages } from "./devices.mjs";
import { PUBLISHER, WEB_HOST, identityName, keptSigner, namesOf, packageOf, versionAfter } from "./msix.mjs";
import { sizeOf, tile } from "./png.mjs";
import { nameOf, pageFiles } from "./share.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const HOST = join(HERE, "..", "Resources", "WebHost");
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
// The most lamp sends a device.
const PACKAGE_LIMIT = 1 << 30;

function readJSON(file) { try { return JSON.parse(readFileSync(file, "utf8")); } catch { return null; } }

/**
 * The device a word names, among those lamp set up that take a page: by its own name ("Living Room Xbox"), its kind
 * ("xbox") or its id. One that's only found on the network is never taken for the person's: it's set up first.
 */
export function deviceNamed(word, { command = "lamp" } = {}) {
  const wanted = String(word).toLowerCase();
  const mine = allKept().filter((device) => takesPages(integrationOf(device.integration)));
  const setUp = `${command} devices add sets one up: run it in a terminal yourself, since it asks for what only you should type`;
  if (!mine.length) throw new Problem(`lamp hasn't set up a device that takes a page yet. ${setUp}.`);
  const named = mine.filter((device) => {
    const integration = integrationOf(device.integration);
    return device.id.toLowerCase() === wanted || device.name.toLowerCase() === wanted || integration.id.startsWith(wanted) || integration.name.toLowerCase() === wanted;
  });
  const found = named.length ? named : mine.filter((device) => device.name.toLowerCase().includes(wanted));
  if (!found.length) throw new Problem(`lamp has no device called "${word}" set up. It has: ${mine.map((device) => device.name).join(", ")}.`);
  if (found.length > 1) throw new Problem(`"${word}" could be ${found.map((device) => `"${device.name}"`).join(" or ")}: say which by its name.`);
  if (!isReady(found[0], integrationOf(found[0].integration))) throw new Problem(`${found[0].name} isn't all set up yet. ${setUp}.`);
  return found[0];
}

/**
 * Where the word after --on says a page goes, each put on, looked at, stopped and taken off the same way: lamp's own
 * Android emulator ("android", "android-tv"), a device lamp set up ("xbox", or its name), or an Android device of the
 * person's that adb sees (its name, or adb's serial for it). Only an Android place can be tried (`use`): adb sends it
 * taps and keys, where a console takes none.
 */
export async function placeNamed(word, { command = "lamp" } = {}) {
  const android = (place) => ({
    name: place.name, word: place.word,
    put: (layout, options = {}) => putOnAndroid(layout, place, { ...options, command }),
    look: (layout) => lookOnAndroid(layout, place, { command }),
    use: (layout, moves) => useOnAndroid(layout, place, moves, { command }),
    stop: (layout) => stopOnAndroid(layout, place),
    remove: (layout) => removeFromAndroid(layout, place, { command }),
  });
  const emulator = emulatorNamed(word);
  if (emulator) {
    if (!knowsAndroid()) throw new Problem(process.platform === "darwin" ? "Lamp's Android app for a page isn't beside this copy of lamp: scripts/cli-files.sh writes it" : "lamp builds for Android on a Mac, so far");
    return android(emulator);
  }
  let device, missing;
  try { device = deviceNamed(word, { command }); } catch (error) { if (!(error instanceof Problem)) throw error; missing = error; }
  if (device) {
    return {
      name: device.name, word,
      put: async (layout, options = {}) => {
        const put = await putOn(layout, device, options);
        return { ...put, line: `${put.name} is open on ${device.name}${put.game ? ", installed as a game" : ""}: ${put.files} files, version ${put.identity.version}.` };
      },
      look: (layout) => lookOn(layout, device),
      stop: (layout) => stopOn(layout, device),
      remove: (layout) => removeFrom(layout, device),
    };
  }
  const own = await androidDeviceNamed(word);
  if (own) return android(own);
  throw new Problem(`${missing.message}${knowsAndroid() ? ` lamp's Android emulator is --on android, and an Android device of the person's goes by its name once it's plugged in with USB debugging on (${command} devices lists them).` : ""}`);
}

/**
 * Makes sure the device answers where lamp last found it, before anything is made for it. One that doesn't may have
 * been given another address since: lamp looks for it once, and goes on at the address it answers from now.
 */
async function reached(runner) {
  const device = runner.device, port = runner.integration.bridge?.install?.find((action) => action.http)?.http.port;
  if (!port || (await answersOn(device.address, port, { reach: runner.reach }))) return;
  await look().catch(() => []);
  const now = kept(device.id);
  if (now?.address && now.address !== device.address && (await answersOn(now.address, port, { reach: runner.reach }))) { device.address = now.address; return; }
  throw new Problem(`${device.name} isn't answering (last at ${device.address}). Make sure it's on and in Developer Mode, then try again.`);
}

/** Where lamp keeps what it made of an app for one device: the package, its names, and which copy the device has. */
const buildFolder = (layout, device) => join(stateOf(layout.folder), "device", createHash("sha256").update(device.id).digest("hex").slice(0, 8));

/** The app's name to lamp, which its package is named for: its folder's own, so two apps never share a package. */
const appID = (layout) => stateOf(layout.folder).split(/[\\/]/).pop();

/**
 * The package's name on the Xbox: the folder's name, cut so its hash always fits after it (`identityName` keeps 40
 * characters), so two folders with the same long name are two apps there.
 */
const xboxName = (layout) => {
  const id = appID(layout), hash = id.slice(id.lastIndexOf("-") + 1);
  const name = [...id.slice(0, id.lastIndexOf("-"))].filter((c) => /[A-Za-z0-9-]/.test(c)).join("");
  return identityName(`${name.slice(0, 40 - hash.length - 1)}-${hash}`);
};

/** What a game's page is told about the device it's on (`GamePage.descriptor`): its controller and what its keys are called. */
export function deviceFile(integration) {
  const input = integration.input ?? {}, facts = {};
  if (input.controller) facts.controller = input.controller;
  facts.keys = Object.fromEntries(Object.entries(input.keys ?? {}).sort(([a], [b]) => (a < b ? -1 : 1)));
  if (input.layout) facts.layout = input.layout;
  return `// Written by Lamp for the device this copy of the game is on (${integration.id}); don't edit.\nexport default ${JSON.stringify(facts)};\n`;
}

/** Whether the app is installed as a game: a device may give a game more than an app (an Xbox, about five times the memory and its whole GPU). */
const isGame = (layout) => layout.game || readJSON(join(layout.folder, "capabilities.json"))?.game === true;

/** The app's icon, where it has one lamp can draw from: Lamp's own for the app, or a page's. */
function iconOf(layout) {
  const candidates = [join(layout.folder, ".lamp", "AppIcon-square.png"), ...["apple-touch-icon.png", "icon.png", "favicon.png"].map((name) => join(layout.root, name))];
  for (const file of candidates) {
    try { const bytes = readFileSync(file); if (sizeOf(bytes)) return bytes; } catch {}
  }
  return null;
}

/**
 * Makes the package of the page for a device, in lamp's folder: the page's files as they are now, with what a game is
 * told of the device, in the device's host. Each one is a newer version than the last, so it replaces it.
 */
export function packageFor(layout, device, integration = integrationOf(device.integration)) {
  if (!takesPages(integration)) throw new Problem(`lamp doesn't put a page on a ${integration?.name ?? "device like that"} yet`);
  let host, library;
  try { host = readFileSync(join(HOST, WEB_HOST.program)); library = readFileSync(join(HOST, WEB_HOST.library)); }
  catch { throw new Problem(`Lamp's web host for the ${integration.name} isn't beside this copy of lamp`); }
  const files = pageFiles(layout, { device: deviceFile(integration) });
  if (files.reduce((sum, [, bytes]) => sum + bytes.length, 0) > PACKAGE_LIMIT) throw new Problem(`the page is bigger than lamp sends to a device (${PACKAGE_LIMIT >> 30} GB)`);
  const payload = [[WEB_HOST.program, host], [WEB_HOST.library, library], ...files.map(([path, bytes]) => [`${WEB_HOST.folder}/${path}`, bytes])];
  const folder = buildFolder(layout, device);
  mkdirSync(folder, { recursive: true });
  const identity = { name: xboxName(layout), publisher: PUBLISHER, version: versionAfter(readJSON(join(folder, "identity.json"))?.version), architecture: "x64" };
  const signer = keptSigner(join(devicesHome(), "msix")), icon = iconOf(layout);
  const made = packageOf({ payload, displayName: nameOf(layout), identity, entry: "webHost", logo: (width, height) => tile(icon, width, height), signer });
  writeFileSync(join(folder, "package.msix"), made);
  writeFileSync(join(folder, "certificate.cer"), signer.certificate);
  writeFileSync(join(folder, "identity.json"), JSON.stringify(identity));
  return { folder, identity, files: files.length, bytes: made.length, game: isGame(layout) };
}

/** lamp's values for the bridge: the app's id, whether it's a game, and the names Windows gives its package. */
function valuesOf(layout, identity) {
  const values = { appID: appID(layout), isGame: isGame(layout) ? "true" : "false" };
  if (identity) { const names = namesOf(identity); values.packageFullName = names.fullName; values.appUserModelID = names.appUserModelID; }
  return values;
}

/** The copy lamp last put on the device, by the record its install left; null when lamp never put one there. */
const installed = (layout, device) => readJSON(join(buildFolder(layout, device), "installed.json"));

// A device busy closing the app it's replacing can drop a connection, the upload's or the launch's just after it.
const dropped = (error) => error instanceof Away && ["ECONNRESET", "EPIPE", "ECONNABORTED"].includes(error.code);

/**
 * Packages the page and puts it on the device: the copy there is ended, the new one installed and, unless `opens` is
 * false, opened. `said` is told each stage as it starts.
 */
export async function putOn(layout, device, { opens = true, said = () => {}, runner } = {}) {
  runner ??= new Runner({ integration: integrationOf(device.integration), device });
  const integration = runner.integration, bridge = integration.bridge ?? {};
  if (!bridge.install) throw new Problem(`${device.name}'s integration doesn't say how an app goes on it`);
  await reached(runner);
  said(`Packaging ${nameOf(layout)} for ${device.name}…`);
  const made = packageFor(layout, device, integration), folder = made.folder;
  let waited = false;
  runner.onWaiting = () => { if (!waited) said(`Waiting for ${device.name} to finish with it…`); waited = true; };
  const values = valuesOf(layout, made.identity), files = { package: join(folder, "package.msix"), certificate: join(folder, "certificate.cer") };
  // The copy on the device now is ended first: a device can fail to open a package installed over its running copy.
  const before = installed(layout, device);
  if (opens && bridge.stop && before) await runner.run(bridge.stop, { extra: valuesOf(layout, before) }).catch(() => {});
  // A setting the install changes for itself (an Xbox's "treat apps as games") stays changed until the app has been
  // opened: the console settles the package's type then.
  const changed = [];
  const stillInstalling = `The ${integration.name} is still finishing installing ${nameOf(layout)}. Try again in a moment.`;
  said(`Installing it on ${device.name} (${(made.bytes / 1_000_000).toFixed(1)} MB)…`);
  for (let tries = 0; ; tries++) {
    try {
      // Noted as on its way before the upload, and as the installed one only once the device took it: an install cut
      // short may still land on the device, and a removal then names both.
      writeFileSync(join(folder, "pending.json"), JSON.stringify(made.identity));
      await runner.run(bridge.install, { extra: values, files, changed });
      writeFileSync(join(folder, "installed.json"), JSON.stringify(made.identity));
      rmSync(join(folder, "pending.json"), { force: true });
      if (opens && bridge.launch?.length) {
        said(`Opening it…`);
        waited = false;
        const opened = await runner.open(bridge.launch, bridge.running, { extra: values, changed });
        if (!opened.opened) {
          throw new Problem(opened.launched
            ? `The ${integration.name} is still finishing installing ${nameOf(layout)}, or it closed as it opened. Try again in a moment.`
            : stillInstalling + (opened.refused ? `\n${opened.refused}` : ""));
        }
      }
      break;
    } catch (error) {
      if (dropped(error) && tries < 2) { await sleep(3000); continue; }
      await runner.putBack(changed);
      if (error instanceof StillWorking) throw new Problem(stillInstalling);
      throw error;
    }
  }
  await runner.putBack(changed);
  return { ...made, opened: opens && !!bridge.launch?.length, name: nameOf(layout) };
}

/**
 * The device's screen now, kept as a picture in lamp's folder, with whether the app is the one open there and what
 * it last logged: the only word from the device of how the page runs on it.
 */
export async function lookOn(layout, device, { runner } = {}) {
  runner ??= new Runner({ integration: integrationOf(device.integration), device });
  const bridge = runner.integration.bridge ?? {};
  await reached(runner);
  const mine = installed(layout, device), values = valuesOf(layout, mine);
  const seen = { device: device.name, installed: !!mine, running: null, picture: null, log: null };
  if (mine && bridge.running) seen.running = await openNow(runner, values);
  if (bridge.look) {
    const picture = (await runner.run(bridge.look, { extra: values })).picture;
    if (picture?.length) {
      const kind = picture.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff])) ? "jpg" : "png";
      seen.picture = join(buildFolder(layout, device), `look.${kind}`);
      mkdirSync(dirname(seen.picture), { recursive: true });
      writeFileSync(seen.picture, picture);
      seen.size = kind === "png" ? sizeOf(picture) : null;
    }
  }
  if (mine && bridge.log) seen.log = await runner.run(bridge.log, { extra: values }).then((outcome) => outcome.log ?? "", (error) => { if (error instanceof Problem) return null; throw error; });
  return seen;
}

/** Whether the app is open on the device now, asked once: not whether it opens in a while. */
function openNow(runner, values) {
  const once = runner.integration.bridge.running.map((action) => (action.http ? { http: { ...action.http, until: undefined } } : action));
  return runner.run(once, { extra: values }).then(() => true, (error) => { if (error instanceof Problem && !(error instanceof Away)) return false; throw error; });
}

/** Ends the app on the device; false when lamp never put it there. */
export async function stopOn(layout, device, { runner } = {}) {
  runner ??= new Runner({ integration: integrationOf(device.integration), device });
  const bridge = runner.integration.bridge ?? {}, mine = installed(layout, device);
  if (!mine || !bridge.stop) return false;
  await reached(runner);
  const values = valuesOf(layout, mine);
  try {
    await runner.run(bridge.stop, { extra: values });
  } catch (error) {
    // A device refuses to end an app that isn't open (an Xbox answers that it failed to): that's stopped already.
    if (!(error instanceof Problem) || error instanceof Away || !bridge.running || (await openNow(runner, values))) throw error;
    return true;
  }
  // A device goes on listing an app for a while after it's told to end it (an Xbox, about fifteen seconds): waited
  // for, so a look right after says what's so.
  for (let tries = 0; bridge.running && tries < 25 && (await openNow(runner, values)); tries++) await runner.pause(1000);
  return true;
}

/** Takes the app off the device: the copy it took, and one that was on its way and may have landed. False when lamp never put it there. */
export async function removeFrom(layout, device, { runner } = {}) {
  runner ??= new Runner({ integration: integrationOf(device.integration), device });
  const bridge = runner.integration.bridge ?? {}, folder = buildFolder(layout, device);
  if (!bridge.remove) throw new Problem(`${device.name}'s integration doesn't say how an app comes off it`);
  if (!readJSON(join(folder, "installed.json")) && !readJSON(join(folder, "pending.json"))) return false;
  await reached(runner);
  const asked = new Set();
  let removed = false;
  for (const record of ["installed.json", "pending.json"]) {
    const identity = readJSON(join(folder, record));
    if (!identity || asked.has(namesOf(identity).fullName)) continue;
    asked.add(namesOf(identity).fullName);
    const values = valuesOf(layout, identity);
    if (bridge.stop) await runner.run(bridge.stop, { extra: values }).catch(() => {});
    // The copy that was only on its way may never have landed: the device saying so is no failure.
    if (record === "installed.json") await runner.run(bridge.remove, { extra: values });
    else await runner.run(bridge.remove, { extra: values }).catch(() => {});
    removed = true;
    rmSync(join(folder, record), { force: true });
  }
  return removed;
}
