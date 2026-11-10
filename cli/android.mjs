// A page on Android: Lamp's Android app around the page (`GameAndroid` in Lamp's app, one app for phones, tablets and
// TVs), built by Gradle with the tools Lamp keeps on this computer, and put on lamp's own emulator or on a device of
// the person's that adb sees. The project is written in lamp's own folder for the app, never in the app's: what's
// built is Lamp's host and the page's files as lamp read them, so nothing in the app's folder runs in the build.
//
// The tools and Gradle's cache are the ones every Lamp on this computer shares (they're large, and the same for each).
// lamp's adb server, its key to the person's devices and its emulators are its own, on ports and in folders no other
// Lamp uses, as each Lamp's are: a device allows lamp once, and an emulator lamp started is lamp's to close.

import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { chmodSync, createReadStream, createWriteStream, existsSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Problem, stateOf } from "./state.mjs";
import { scaled, sizeOf, tile } from "./png.mjs";
import { nameOf, pageFiles } from "./share.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
// Lamp's Android app for a page and the tools it's built with, as Lamp's own code writes them (scripts/cli-files.sh).
const HOST = join(HERE, "lamps", "android-host");
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const readJSON = (file) => { try { return JSON.parse(readFileSync(file, "utf8")); } catch { return null; } };

// lamp's own ports: its adb server's, and for each emulator its console's (adb reaches it on the next one up) and
// the one it's controlled on. Clear of every Lamp's (`Edition.androidPorts`).
const PORTS = { server: 47915, phone: { console: 47918, control: 47916 }, tv: { console: 47920, control: 47922 } };

const EMULATORS = {
  phone: { word: "android", name: "the Android emulator", words: ["android", "android-phone", "android-emulator", "emulator"] },
  tv: { word: "android-tv", name: "the Android TV emulator", words: ["android-tv", "android-tv-emulator", "tv-emulator"] },
};

/** What a game's page is told of the device it's on (`GamePage.descriptor` for Android: nothing of its own to name). */
const DEVICE = `// Written by Lamp for the device this copy of the game is on (android); don't edit.\nexport default ${JSON.stringify({ keys: {} })};\n`;

let read;
/** What Lamp builds an Android app with, and where its host's files go. */
function spec() {
  if (process.platform !== "darwin") throw new Problem("lamp builds for Android on a Mac, so far");
  read ??= readJSON(join(HOST, "tools.json"));
  if (!read) throw new Problem("Lamp's Android app for a page isn't beside this copy of lamp: scripts/cli-files.sh writes it");
  return read;
}

/** Whether this copy of lamp has what it needs to put a page on Android at all. */
export const knowsAndroid = () => process.platform === "darwin" && existsSync(join(HOST, "tools.json"));

/** lamp's own: adb's key to the person's devices, the emulators it made, and which of them it started. */
export const androidHome = () => process.env.LAMP_ANDROID_HOME || join(homedir(), ".lamp", "android");
/** The tools, one copy for every Lamp on this Mac (`Edition.sharedDeveloperFolder`). */
export const toolsFolder = () => process.env.LAMP_ANDROID_TOOLS || join(homedir(), "Library", "Developer", "Lamp", "Android");
/** Gradle's own cache, every dependency it fetched, shared the same way (`Edition.sharedCachesFolder`). */
const gradleCache = () => process.env.LAMP_GRADLE_HOME || join(homedir(), "Library", "Caches", "Lamp", "gradle");

function paths() {
  const tools = toolsFolder(), sdk = join(tools, "sdk"), jdk = join(tools, "jdk"), gradleFolder = join(tools, `gradle-${spec().gradle}`);
  const javaHome = join(jdk, "Contents", "Home");
  return {
    tools, sdk, jdk, javaHome, gradleFolder,
    java: join(javaHome, "bin", "java"), gradle: join(gradleFolder, "bin", "gradle"),
    adb: join(sdk, "platform-tools", "adb"), emulator: join(sdk, "emulator", "emulator"),
    sdkmanager: join(sdk, "cmdline-tools", "latest", "bin", "sdkmanager"), avdmanager: join(sdk, "cmdline-tools", "latest", "bin", "avdmanager"),
    userHome: join(androidHome(), "home"), avdHome: join(androidHome(), "avd"),
  };
}

/** Which of the tools are on this computer (`AndroidTools.has…`). */
export function toolsThere() {
  const p = paths(), s = spec(), image = (name) => existsSync(join(p.sdk, ...name.split(";"), "system.img"));
  const there = {
    jdk: existsSync(p.java), commandLineTools: existsSync(p.sdkmanager), gradle: existsSync(p.gradle),
    buildPackages: existsSync(p.adb) && existsSync(join(p.sdk, "build-tools", s.buildTools, "aapt2")) && existsSync(join(p.sdk, "platforms", `android-${s.platform}`, "android.jar")),
    emulatorPackages: existsSync(p.emulator) && image(s.phone.image), tvImage: image(s.tv.image),
  };
  there.builds = there.jdk && there.commandLineTools && there.gradle && there.buildPackages;
  return there;
}

const NO_TOOLS = (command) => `Android's tools aren't on this computer yet. "${command} devices add android" downloads them (about 2 GB, Google's and Gradle's own); it accepts Google's terms for them, so the person runs it in a terminal themselves.`;

/** What every command of Google's or Gradle's is run with (`AndroidTools.environment`), lamp's own server and folders in it. */
function environment() {
  const p = paths(), env = { ...process.env };
  // A serial the person set for their own adb would send every command of lamp's to it.
  delete env.ANDROID_SERIAL;
  return {
    ...env, JAVA_HOME: p.javaHome, ANDROID_HOME: p.sdk, ANDROID_SDK_ROOT: p.sdk, ANDROID_USER_HOME: p.userHome, ANDROID_AVD_HOME: p.avdHome,
    GRADLE_USER_HOME: gradleCache(), ANDROID_ADB_SERVER_PORT: String(PORTS.server),
    // lamp's server doesn't look for emulators on adb's usual ports: those are the person's, or another Lamp's.
    ADB_LOCAL_TRANSPORT_MAX_PORT: "5554",
  };
}

/** Runs a tool to its end: what it said, and whether it ended well. `binary` keeps its output as bytes. */
function run(file, args, { cwd, input, timeout = 60_000, env, binary = false } = {}) {
  return new Promise((done) => {
    const out = [], err = [];
    let timedOut = false, child;
    const end = (code, failure) => {
      clearTimeout(timer);
      const all = Buffer.concat(out);
      done({ ok: code === 0 && !timedOut, code, out: binary ? all : all.toString("utf8"), err: failure ?? Buffer.concat(err).toString("utf8"), timedOut });
    };
    try { child = spawn(file, args, { cwd, env: env ?? environment(), stdio: ["pipe", "pipe", "pipe"] }); }
    catch (error) { return done({ ok: false, code: null, out: binary ? Buffer.alloc(0) : "", err: String(error.message), timedOut: false }); }
    const timer = setTimeout(() => { timedOut = true; child.kill("SIGKILL"); }, timeout);
    child.stdout.on("data", (chunk) => out.push(chunk));
    child.stderr.on("data", (chunk) => err.push(chunk));
    child.on("error", (error) => end(null, String(error.message)));
    child.on("close", (code) => end(code));
    child.stdin.on("error", () => {});
    child.stdin.end(input ?? "");
  });
}

const tail = (text, lines) => text.split(/\r?\n/).filter((line) => line.trim()).slice(-lines).join("\n");

// MARK: adb

let server;
/** lamp's adb server, started once for this command with nothing of this command's held open by it. */
function serverStarted() {
  server ??= new Promise((done) => {
    const p = paths();
    mkdirSync(p.userHome, { recursive: true });
    const child = spawn(p.adb, ["start-server"], { env: environment(), stdio: "ignore" });
    const timer = setTimeout(() => { child.kill(); done(); }, 30_000);
    child.on("error", () => { clearTimeout(timer); done(); });
    child.on("exit", () => { clearTimeout(timer); done(); });
  });
  return server;
}

async function adb(args, { serial, timeout = 60_000, input, binary } = {}) {
  await serverStarted();
  return run(paths().adb, [...(serial ? ["-s", serial] : []), ...args], { timeout, input, binary });
}

/**
 * Ends lamp's adb server as a command of lamp's ends, if this command started or used it and none of lamp's emulators
 * is running: a server left behind would go on holding the person's plugged-in devices, which their own adb then
 * couldn't use. While an emulator runs it stays, so each look at it is quick; the next command starts one otherwise.
 */
export async function androidDone() {
  if (!server) return;
  await server;
  for (const kind of Object.keys(EMULATORS)) if (await answers(PORTS[kind].console)) return;
  await run(paths().adb, ["kill-server"], { timeout: 10_000 });
}

/** Each line of `adb devices -l`: the selector adb takes with -s, its state, and the model adb read. */
async function listed() {
  const said = (await adb(["devices", "-l"], { timeout: 30_000 })).out;
  return said.split("\n").map((line) => line.trim()).filter((line) => line && !line.startsWith("*") && !line.startsWith("List of"))
    .map((line) => line.split(/\s+/)).filter((parts) => parts.length >= 2)
    .map(([serial, state, ...facts]) => ({ serial, state, model: facts.find((fact) => fact.startsWith("model:"))?.slice(6).replaceAll("_", " ") }));
}

/** What the person does about a device adb lists in a state it can't be used in (`Adb.advice`). */
function advice(name, state) {
  if (state === "unauthorized") return `On ${name}, choose Allow when it asks whether to allow debugging from this computer (tick Always allow).`;
  if (state === "offline") return `${name} isn't answering. Unplug it and plug it in again, and unlock it.`;
  return `On ${name}, open Settings → About phone and tap Build number seven times to turn on Developer options, then in Settings → System → Developer options turn on USB debugging, and plug it in.`;
}

/** The person's own devices adb sees, each with its name and whether lamp is allowed on it. lamp's emulators aren't among them. */
export async function androidDevices() {
  const emulators = new Set(Object.keys(EMULATORS).map(serialOf)), found = [];
  for (const device of await listed()) {
    if (emulators.has(device.serial)) continue;
    let name = device.model ?? device.serial, id = device.serial, tv = false;
    if (device.state === "device") {
      const keys = ["ro.product.manufacturer", "ro.product.model", "ro.serialno"];
      const asked = keys.map((key) => `echo ${key}=$(getprop ${key})`).join(";") + ";echo leanback=$(pm has-feature android.software.leanback)";
      const said = Object.fromEntries((await adb(["shell", asked], { serial: device.serial, timeout: 20_000 })).out.split("\n")
        .map((line) => line.trim()).filter((line) => line.includes("=")).map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]));
      const maker = said["ro.product.manufacturer"] ?? "", model = said["ro.product.model"] || name;
      name = !maker || model.toLowerCase().startsWith(maker.toLowerCase()) ? model : `${maker} ${model}`;
      // The serial the device reads is its own; adb's selector for one on the network is only where it is now.
      if (said["ro.serialno"]) id = said["ro.serialno"];
      tv = said.leanback === "true";
    }
    found.push({ serial: device.serial, state: device.state, name, id, tv });
  }
  return found;
}

// MARK: The emulators

const serialOf = (kind) => `emulator-${PORTS[kind].console}`;
const recordOf = (kind) => join(androidHome(), `emulator-${kind}.json`);

/** Whether something answers on one of this computer's ports. */
function answers(port) {
  return new Promise((done) => {
    const socket = net.connect(port, "127.0.0.1");
    const end = (there) => { socket.destroy(); done(there); };
    socket.setTimeout(1500, () => end(false));
    socket.on("connect", () => end(true));
    socket.on("error", () => end(false));
  });
}

/**
 * Tells lamp's adb server about lamp's emulator on its ports, in the message an emulator sends it as it boots (adb's
 * `host:emulator:<port>`, its length first in hex): a server started after the emulator hasn't heard of it.
 */
function register(kind) {
  return new Promise((done) => {
    const request = `host:emulator:${PORTS[kind].console + 1}`, socket = net.connect(PORTS.server, "127.0.0.1");
    socket.setTimeout(2000, () => { socket.destroy(); done(false); });
    socket.on("connect", () => socket.end(request.length.toString(16).padStart(4, "0") + request, () => done(true)));
    socket.on("error", () => done(false));
  });
}

/** Whether lamp's emulator of that kind is running and adb reaches it. Another emulator adb lists isn't lamp's to use. */
async function emulatorRunning(kind) {
  const serial = serialOf(kind), there = async () => (await listed()).some((device) => device.serial === serial && device.state === "device");
  if (await there()) return true;
  if (!(await answers(PORTS[kind].console))) return false;
  await register(kind);
  await sleep(500);
  return there();
}

/** Makes one of lamp's emulators from its system image: a recent Pixel, or a 1080p TV (`Emulator.create`). */
async function makeEmulator(kind) {
  const p = paths(), s = spec()[kind];
  mkdirSync(p.avdHome, { recursive: true });
  mkdirSync(p.userHome, { recursive: true });
  // avdmanager asks whether to make a hardware profile of its own; the answer is no.
  const made = await run(p.avdmanager, ["create", "avd", "-n", s.avd, "-k", s.image, "-d", s.profile, "--force"], { input: "no\n", timeout: 120_000 });
  if (!made.ok || !existsSync(join(p.avdHome, `${s.avd}.avd`, "config.ini"))) throw new Problem(`lamp couldn't make the emulator.\n${tail(made.out + made.err, 8)}`);
}

/**
 * Starts lamp's emulator of that kind when it isn't running, waits for Android to boot, and gives back its serial. It's
 * a window of its own on the Mac; `hidden` starts it with none and no sound, for a check nobody watches. One running
 * hidden is opened again with its window when the person asks to see it.
 */
/** A Problem when that emulator isn't downloaded, saying how it is. */
function emulatorThere(kind, command) {
  const there = toolsThere();
  if (!there.builds) throw new Problem(NO_TOOLS(command));
  if (there.emulatorPackages && (kind !== "tv" || there.tvImage)) return;
  const word = EMULATORS[kind].word;
  throw new Problem(`${EMULATORS[kind].name[0].toUpperCase()}${EMULATORS[kind].name.slice(1)} isn't on this computer yet. "${command} devices add ${word}" downloads it (about a gigabyte); it accepts Google's terms for it, so the person runs it in a terminal themselves.`);
}

async function startEmulator(kind, { hidden = false, said = () => {}, command = "lamp" } = {}) {
  const p = paths(), s = spec()[kind], serial = serialOf(kind);
  emulatorThere(kind, command);
  if (await emulatorRunning(kind)) {
    if (hidden || !readJSON(recordOf(kind))?.hidden) return serial;
    said(`Opening ${EMULATORS[kind].name} again with its window…`);
    await closeEmulator(kind);
  }
  if (!existsSync(join(p.avdHome, `${s.avd}.avd`, "config.ini"))) {
    said(`Making ${EMULATORS[kind].name}…`);
    await makeEmulator(kind);
  }
  said(`Starting ${EMULATORS[kind].name}${hidden ? ", with no window" : ""}…`);
  const { console: port, control } = PORTS[kind], logFile = join(androidHome(), `emulator-${kind}.log`);
  // After a crash the emulator would otherwise open with a dialog asking to send Google a report, and start nothing
  // until it's answered.
  const args = ["-avd", s.avd, "-ports", `${port},${port + 1}`, "-grpc", String(control), "-crash-report-mode", "never", "-no-boot-anim",
    "-netdelay", "none", "-netspeed", "full", ...(hidden ? ["-no-window", "-no-audio"] : [])];
  const log = openSync(logFile, "w");
  const child = spawn(p.emulator, args, { env: environment(), detached: true, stdio: ["ignore", log, log] });
  let quit = false;
  child.on("exit", () => { quit = true; });
  child.on("error", () => { quit = true; });
  child.unref();
  writeFileSync(recordOf(kind), JSON.stringify({ hidden, pid: child.pid }));
  // Booting takes most of a minute the first time, a few seconds from its saved state after that.
  for (let waited = 0; waited < 240; waited++) {
    await sleep(1000);
    if (quit) { rmSync(recordOf(kind), { force: true }); throw new Problem(`The emulator quit while starting; what it said is in ${logFile}`); }
    if ((await emulatorRunning(kind)) && (await adb(["shell", "getprop", "sys.boot_completed"], { serial, timeout: 10_000 })).out.trim() === "1") {
      // Android covers the first full-screen app with a tip on leaving full screen; in lamp's own emulator it's taken as read.
      await adb(["shell", "settings", "put", "secure", "immersive_mode_confirmations", "confirmed"], { serial, timeout: 10_000 });
      return serial;
    }
  }
  throw new Problem(`The emulator didn't finish starting; what it said is in ${logFile}`);
}

/** Closes lamp's emulator of that kind, saving where it is; false when it wasn't running. */
export async function closeEmulator(kind) {
  if (!(await emulatorRunning(kind))) { rmSync(recordOf(kind), { force: true }); return false; }
  await adb(["emu", "kill"], { serial: serialOf(kind), timeout: 20_000 });
  for (let waited = 0; waited < 60 && (await answers(PORTS[kind].console)); waited++) await sleep(500);
  rmSync(recordOf(kind), { force: true });
  return true;
}

// MARK: Where a page goes

const emulatorPlace = (kind) => ({ name: EMULATORS[kind].name, word: EMULATORS[kind].word, key: `android:emulator-${kind}`, emulator: kind });

/** lamp's emulator a word names ("android", "android-tv"), or null. Nothing is started or asked of adb. */
export function emulatorNamed(word) {
  const wanted = String(word).toLowerCase(), kind = Object.keys(EMULATORS).find((each) => EMULATORS[each].words.includes(wanted));
  return kind ? emulatorPlace(kind) : null;
}

/** The person's own Android device a word names, by its name or adb's serial; null when adb sees none like it. */
export async function androidDeviceNamed(word) {
  if (!knowsAndroid() || !toolsThere().buildPackages) return null;
  const wanted = String(word).toLowerCase(), all = await androidDevices();
  const exact = all.filter((device) => device.serial.toLowerCase() === wanted || device.id.toLowerCase() === wanted || device.name.toLowerCase() === wanted);
  const found = exact.length ? exact : all.filter((device) => device.name.toLowerCase().includes(wanted));
  if (!found.length) return null;
  if (found.length > 1) throw new Problem(`"${word}" could be ${found.map((device) => `"${device.name}" (${device.serial})`).join(" or ")}: say which by its serial.`);
  if (found[0].state !== "device") throw new Problem(advice(found[0].name, found[0].state));
  return { name: found[0].name, word: found[0].serial, key: `android:${found[0].id}`, serial: found[0].serial };
}

/** The serial adb reaches the place by: an emulator's once it runs (started when `start` says so, else null), a device's own. */
async function reach(place, { start = false, hidden, said, command } = {}) {
  if (!place.emulator) return place.serial;
  if (start) return startEmulator(place.emulator, { hidden, said, command });
  return (await emulatorRunning(place.emulator)) ? serialOf(place.emulator) : null;
}

/** adb's own word that it couldn't reach the device, which isn't the app's doing. */
function away(place, result) {
  const said = (result.out + result.err).toLowerCase();
  return result.timedOut || /not found|offline|no devices|unauthorized|closed/.test(said) ? new Problem(`${place.name} isn't answering. ${place.emulator ? "Open the page on it again." : "Plug it in again and unlock it."}`) : null;
}

// MARK: The app

/** The app's name to lamp, which its package is named for: its folder's own, so two apps never share a package. */
const appID = (layout) => stateOf(layout.folder).split(/[\\/]/).pop();

/**
 * The app's package name, which Android ties its data and identity to: lamp's own prefix, so a copy lamp puts on a
 * device never takes the place of one Lamp's app put there, and the app's id with what a Java name can't carry made safe.
 */
export const packageOf = (layout) => `dev.lamp.cli.${appID(layout).replace(/[^A-Za-z0-9]/g, "_").replace(/^(?=\d)/, "_").toLowerCase()}`;

/** The app's name as its manifest's label: text, never markup or a reference to a resource. */
const label = (name) => name.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/^([@?])/, "\\$1");

function iconOf(layout) {
  for (const file of [join(layout.folder, ".lamp", "AppIcon-square.png"), ...["apple-touch-icon.png", "icon.png", "favicon.png"].map((name) => join(layout.root, name))]) {
    try { const bytes = readFileSync(file); if (sizeOf(bytes)) return bytes; } catch {}
  }
  return null;
}

/** Writes a file only when it isn't that already, so a build finds nothing changed where nothing is. */
function put(file, content) {
  const bytes = Buffer.isBuffer(content) ? content : Buffer.from(content);
  try { if (readFileSync(file).equals(bytes)) return; } catch {}
  try {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, bytes);
  } catch {
    // A folder where the file goes, or a file where its folder does, from the page as it was before.
    rmSync(file, { recursive: true, force: true });
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, bytes);
  }
}

/** Makes a folder hold exactly these files: what's gone from the page is gone from its copy. */
function sync(folder, files) {
  const kept = new Set(files.map(([path]) => path));
  const clear = (at, prefix) => {
    for (const entry of readdirSync(at, { withFileTypes: true })) {
      const path = prefix + entry.name, file = join(at, entry.name);
      if (!entry.isDirectory()) { if (!kept.has(path)) rmSync(file, { force: true }); continue; }
      clear(file, path + "/");
      if (!readdirSync(file).length) rmSync(file, { recursive: true, force: true });
    }
  };
  if (existsSync(folder)) clear(folder, "");
  for (const [path, bytes] of files) put(join(folder, ...path.split("/")), bytes);
}

const buildFolder = (layout) => join(stateOf(layout.folder), "android");
const recordFolder = (layout, place) => join(stateOf(layout.folder), "device", createHash("sha256").update(place.key).digest("hex").slice(0, 8));

/**
 * Writes Lamp's Android project for the page in lamp's folder (`GameAndroid.write`, with the page and the icon where
 * build.sh puts them) and builds it: the same app for every Android device.
 */
async function build(layout, { command = "lamp" } = {}) {
  const s = spec(), p = paths();
  if (!toolsThere().builds) throw new Problem(NO_TOOLS(command));
  const root = buildFolder(layout), project = join(root, ...s.folder.split("/"));
  const id = appID(layout), pkg = packageOf(layout), kind = layout.game ? "game" : "page", icon = iconOf(layout);
  const files = pageFiles(layout, { device: DEVICE });
  const fill = (text) => text.replaceAll("{{PACKAGE}}", pkg).replaceAll("{{ANDROID_PACKAGE}}", pkg).replaceAll("{{SLUG}}", id)
    .replaceAll("{{EXE}}", pkg.split(".").pop()).replaceAll("{{NAME}}", label(nameOf(layout)));
  const host = (path) => fill(readFileSync(join(HOST, ...path.split("/")), "utf8"));
  const kotlin = `app/src/main/kotlin/${pkg.replaceAll(".", "/")}`;
  const written = [
    ...["settings.gradle.kts", "build.gradle.kts", "gradle.properties", "gradle/libs.versions.toml", "app/build.gradle.kts"].map((path) => [path, host(path)]),
    ["app/src/main/AndroidManifest.xml", host(`${kind}/AndroidManifest.xml`)],
    [`${kotlin}/MainActivity.kt`, host(`${kind}/MainActivity.kt`)],
    [`${kotlin}/LampPageGateway.kt`, host("LampPageGateway.kt")],
    // The banner a TV's home screen shows: the app's icon on a dark tile, or the tile alone until it has one.
    [s.banner, tile(icon, 320, 180)],
    ["local.properties", `sdk.dir=${p.sdk}\n`],
  ];
  for (const [path, content] of written) put(join(project, ...path.split("/")), content);
  sync(join(root, "build", "android-assets", "Web"), files);
  put(join(root, "build", "android-res", "mipmap-xxxhdpi", "ic_launcher.png"), scaled(icon, 432) ?? tile(null, 432, 432));
  mkdirSync(gradleCache(), { recursive: true });
  mkdirSync(p.userHome, { recursive: true });
  const ran = await run(p.gradle, ["--console=plain", "-q", `-Dlamp.app=${id}`, "assembleDebug"], { cwd: project, timeout: 20 * 60_000 });
  const apk = join(project, ...s.apk.split("/"));
  if (!ran.ok || !existsSync(apk)) throw new Problem(`The Android build didn't finish${ran.timedOut ? " in time" : ""}:\n${tail(ran.out + ran.err, 40)}`);
  return { apk, package: pkg, files: files.length, game: layout.game };
}

/** The app's process on the device, or null when it isn't running. */
async function pidOf(pkg, serial) {
  const pid = Number((await adb(["shell", "pidof", pkg], { serial, timeout: 20_000 })).out.trim().split(/\s+/)[0]);
  return Number.isInteger(pid) && pid > 0 ? pid : null;
}

/**
 * Builds the page's Android app and puts it on the place in the stead of the copy there, then opens it. A copy signed
 * with another key can't be updated: it's taken off first, and what it saved with it, since Android allows no other way.
 */
export async function putOnAndroid(layout, place, { said = () => {}, hidden = false, command = "lamp" } = {}) {
  const name = nameOf(layout);
  // Said before anything is built: an emulator that isn't downloaded can't be opened in.
  if (place.emulator) emulatorThere(place.emulator, command);
  said(`Building ${name} for Android…`);
  const built = await build(layout, { command });
  const serial = await reach(place, { start: true, hidden, said, command });
  said(`Installing it on ${place.name}…`);
  let installed = await adb(["install", "-r", "-t", built.apk], { serial, timeout: 300_000 });
  if (!installed.ok && (installed.out + installed.err).includes("INSTALL_FAILED_UPDATE_INCOMPATIBLE")) {
    await adb(["uninstall", built.package], { serial, timeout: 60_000 });
    installed = await adb(["install", "-r", "-t", built.apk], { serial, timeout: 300_000 });
  }
  if (!installed.ok) throw away(place, installed) ?? new Problem(`Couldn't put ${name} on ${place.name}: ${tail(installed.out + installed.err, 6)}`);
  said("Opening it…");
  // The device's own clock as the app starts: its log is read from then on.
  const since = (await adb(["shell", "date", "+%s"], { serial, timeout: 10_000 })).out.trim();
  mkdirSync(recordFolder(layout, place), { recursive: true });
  writeFileSync(join(recordFolder(layout, place), "installed.json"), JSON.stringify({ package: built.package, since: /^\d+$/.test(since) ? since : null }));
  // lamp's own emulator may have put its screen to sleep; a device of the person's is theirs to wake.
  if (place.emulator) await adb(["shell", "input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard"], { serial, timeout: 20_000 });
  await adb(["shell", "am", "force-stop", built.package], { serial, timeout: 30_000 });
  const started = await adb(["shell", "am", "start", "-W", "-n", `${built.package}/.MainActivity`], { serial, timeout: 60_000 });
  if (!started.ok || started.out.includes("Error")) throw away(place, started) ?? new Problem(`${name} didn't open on ${place.name}: ${tail(started.out + started.err, 6)}`);
  let pid = null;
  for (let tries = 0; tries < 20 && !(pid = await pidOf(built.package, serial)); tries++) await sleep(250);
  if (!pid) throw new Problem(`${name} opened on ${place.name} and closed at once: ${command} look --on ${place.word} shows what it said.`);
  return { name, package: built.package, files: built.files, game: built.game, line: `${name} is open on ${place.name}: ${built.files} files${hidden && place.emulator ? ", in an emulator with no window" : ""}.` };
}

const installedOn = (layout, place) => readJSON(join(recordFolder(layout, place), "installed.json"));

/** What the page said since it was opened: its console, and how the app ended if Android ended it. */
async function logOf(mine, serial, pid) {
  const said = await adb(["logcat", "-d", "-v", "brief", ...(mine.since ? ["-T", `${mine.since}.000`] : []), ...(pid ? [`--pid=${pid}`] : []), "-s", "Lamp:V", "AndroidRuntime:E"], { serial, timeout: 30_000 });
  if (!said.ok) return null;
  return said.out.split(/\r?\n/).map((line) => /^[VDIWEF]\/([^\s(]+)\s*\(\s*\d+\):\s?(.*)$/.exec(line)).filter(Boolean)
    .map(([, tag, text]) => (tag === "Lamp" ? text : `${tag}: ${text}`)).join("\n");
}

/** The place's screen now, kept as a picture in lamp's folder, with whether the app is open there and what its page said. */
export async function lookOnAndroid(layout, place, { command = "lamp" } = {}) {
  const serial = await reach(place);
  if (!serial) throw new Problem(`${place.name} isn't running: ${command} open --on ${place.word} starts it, with the page in it.`);
  const mine = installedOn(layout, place), seen = { device: place.name, installed: !!mine, running: null, picture: null, log: null };
  const pid = mine ? await pidOf(mine.package, serial) : null;
  if (mine) seen.running = pid !== null;
  const shot = await adb(["exec-out", "screencap", "-p"], { serial, timeout: 60_000, binary: true });
  if (!shot.ok) { const gone = away(place, { ...shot, out: "" }); if (gone) throw gone; }
  if (shot.ok && sizeOf(shot.out)) {
    seen.picture = join(recordFolder(layout, place), "look.png");
    mkdirSync(dirname(seen.picture), { recursive: true });
    writeFileSync(seen.picture, shot.out);
    seen.size = sizeOf(shot.out);
  }
  if (mine) seen.log = await logOf(mine, serial, pid);
  return seen;
}

/** An emulator lamp started with no window is closed once its app is: nobody can see it to close it themselves. */
async function closeIfHidden(place) {
  if (!place.emulator || !readJSON(recordOf(place.emulator))?.hidden) return false;
  return closeEmulator(place.emulator);
}

/** Ends the app on the place; false when lamp never put it there. */
export async function stopOnAndroid(layout, place) {
  const mine = installedOn(layout, place);
  if (!mine) return false;
  const serial = await reach(place);
  if (!serial) return true;
  const stopped = await adb(["shell", "am", "force-stop", mine.package], { serial, timeout: 30_000 });
  if (!stopped.ok) throw away(place, stopped) ?? new Problem(`Couldn't stop it on ${place.name}: ${tail(stopped.out + stopped.err, 4)}`);
  await closeIfHidden(place);
  return true;
}

/**
 * Takes the app off the place, and what it saved there with it; false when lamp never put it there. An emulator that
 * isn't running is started for it with no window, and closed again after.
 */
export async function removeFromAndroid(layout, place, { command = "lamp" } = {}) {
  const mine = installedOn(layout, place);
  if (!mine) return false;
  const serial = await reach(place, { start: true, hidden: true, command });
  const removed = await adb(["uninstall", mine.package], { serial, timeout: 60_000 });
  const gone = away(place, removed);
  if (gone) throw gone;
  rmSync(join(recordFolder(layout, place), "installed.json"), { force: true });
  await closeIfHidden(place);
  return true;
}

// MARK: Trying it

// A key's name as lamp use takes it, as Android's.
const KEYS = { space: "SPACE", enter: "ENTER", return: "ENTER", escape: "ESCAPE", tab: "TAB", backspace: "DEL", delete: "FORWARD_DEL", up: "DPAD_UP", down: "DPAD_DOWN",
  left: "DPAD_LEFT", right: "DPAD_RIGHT", shift: "SHIFT_LEFT", control: "CTRL_LEFT", alt: "ALT_LEFT", command: "META_LEFT", back: "BACK", home: "HOME", menu: "MENU",
  select: "DPAD_CENTER", ok: "DPAD_CENTER", play: "MEDIA_PLAY_PAUSE" };
// A controller's button as lamp use takes it, as Android's.
const BUTTONS = { a: "BUTTON_A", b: "BUTTON_B", x: "BUTTON_X", y: "BUTTON_Y", lb: "BUTTON_L1", rb: "BUTTON_R1", menu: "BUTTON_START", view: "BUTTON_SELECT",
  up: "DPAD_UP", down: "DPAD_DOWN", left: "DPAD_LEFT", right: "DPAD_RIGHT", ls: "BUTTON_THUMBL", rs: "BUTTON_THUMBR" };

/** One move as the device's own `input` command; a Problem for one it can't make. */
function inputFor(move) {
  const number = (value, what) => { const n = Number(value); if (!Number.isFinite(n)) throw new Problem(`${move.kind} takes ${what}`); return Math.round(n); };
  const held = (seconds) => (Number(seconds) > 0 ? ["--duration", String(Math.round(Math.min(Number(seconds), 30) * 1000))] : []);
  switch (move.kind) {
    case "click":
      if (move.target !== undefined) throw new Problem("on a device, click takes a point of the picture: click <x> <y>");
      return ["tap", String(number(move.x, "a point: click <x> <y>")), String(number(move.y, "a point: click <x> <y>"))];
    case "drag":
      return ["swipe", ...[move.x, move.y, move.toX, move.toY].map((value) => String(number(value, "two points: drag <x> <y> <to x> <to y>"))), "400"];
    case "type":
      // `input text` takes a space as %s and hands the rest to the device's shell: quoted whole.
      return ["text", `'${String(move.text).replaceAll("'", "'\\''").replaceAll(" ", "%s")}'`];
    case "key": {
      const names = String(move.key).toLowerCase().split("+");
      if (names.length > 1) throw new Problem("on a device, keys are pressed one at a time");
      const code = KEYS[names[0]] ?? (/^[a-z0-9]$/.test(names[0]) ? names[0].toUpperCase() : /^f([1-9]|1[0-2])$/.test(names[0]) ? names[0].toUpperCase() : null);
      if (!code) throw new Problem(`lamp doesn't know a key called "${move.key}" on Android`);
      return ["keyevent", ...held(move.seconds), `KEYCODE_${code}`];
    }
    case "button": {
      const names = String(move.buttons).toLowerCase().split("+");
      if (names.length > 1) throw new Problem("on a device, a controller's buttons are pressed one at a time");
      if (!BUTTONS[names[0]]) throw new Problem(`lamp can't press "${move.buttons}" on Android: it presses ${Object.keys(BUTTONS).join(", ")}`);
      return ["gamepad", "keyevent", ...held(move.seconds), `KEYCODE_${BUTTONS[names[0]]}`];
    }
    case "wait": return null;
    default: throw new Problem(`lamp can't ${move.kind === "stick" ? "move a stick" : move.kind} on a device: it clicks a point, drags, types, presses a key or a controller's button, and waits`);
  }
}

/** Tries the app on the place as a person would, one move after another, then looks. */
export async function useOnAndroid(layout, place, moves, { command = "lamp" } = {}) {
  const serial = await reach(place);
  if (!serial) throw new Problem(`${place.name} isn't running: ${command} open --on ${place.word} starts it, with the page in it.`);
  const mine = installedOn(layout, place);
  if (!mine || !(await pidOf(mine.package, serial))) throw new Problem(`It isn't open on ${place.name}: ${command} open --on ${place.word} opens it there.`);
  // Each is checked before any is made, so a move lamp can't make stops them all.
  const inputs = moves.map(inputFor);
  for (const [index, input] of inputs.entries()) {
    if (!input) { await sleep(Math.min(Math.max(Number(moves[index].seconds) || 1, 0), 30) * 1000); continue; }
    const sent = await adb(["shell", "input", ...input], { serial, timeout: 60_000 });
    if (!sent.ok) throw away(place, sent) ?? new Problem(`${place.name} didn't take that: ${tail(sent.out + sent.err, 4)}`);
  }
  // What the move did is drawn a moment after it.
  await sleep(600);
  return { did: `${moves.length === 1 ? "Done" : `${moves.length} moves made`} on ${place.name}.`, ...(await lookOnAndroid(layout, place, { command })) };
}

// MARK: The tools

const sha256 = (file) => new Promise((done, failed) => {
  const hash = createHash("sha256");
  createReadStream(file).on("data", (chunk) => hash.update(chunk)).on("end", () => done(hash.digest("hex"))).on("error", failed);
});

/** An archive that holds one folder with everything in it: that folder's contents become `folder`'s own. */
function flatten(folder) {
  const names = readdirSync(folder).filter((name) => !name.startsWith("."));
  if (names.length !== 1) return;
  const inner = join(folder, names[0]);
  let entries;
  try { entries = readdirSync(inner); } catch { return; }
  for (const name of entries) renameSync(join(inner, name), join(folder, name));
  rmSync(inner, { recursive: true, force: true });
}

/** Downloads one release beside its place, checks it against what its maker published, unpacks it and moves it in whole. */
async function fetchInto(release, destination, archive, name, said) {
  const staging = join(dirname(destination), `.staging-${randomUUID()}`), download = join(staging, "download"), unpacked = join(staging, "unpacked");
  mkdirSync(unpacked, { recursive: true });
  try {
    said(`Downloading ${name} (${Math.round(release.size / 1_000_000)} MB)…`);
    const answer = await fetch(release.url, { redirect: "follow" });
    if (!answer.ok || !answer.body) throw new Problem(`${name} didn't download (${answer.status}).`);
    await new Promise((done, failed) => {
      const file = createWriteStream(download);
      file.on("error", failed).on("finish", done);
      (async () => {
        try { for await (const chunk of answer.body) if (!file.write(chunk)) await new Promise((drained) => file.once("drain", drained)); file.end(); }
        catch (error) { file.destroy(); failed(new Problem(`${name} stopped downloading: ${error.message}`)); }
      })();
    });
    if ((await sha256(download)) !== release.sha256) throw new Problem(`The download of ${name} didn't match what its maker published, so lamp didn't use it.`);
    const opened = archive === "tar" ? await run("/usr/bin/tar", ["-xzf", download, "-C", unpacked], { timeout: 600_000, env: process.env })
      : await run("/usr/bin/unzip", ["-q", download, "-d", unpacked], { timeout: 600_000, env: process.env });
    if (!opened.ok) throw new Problem(`lamp couldn't unpack ${name}.`);
    rmSync(destination, { recursive: true, force: true });
    renameSync(unpacked, destination);
  } finally { rmSync(staging, { recursive: true, force: true }); }
}

/**
 * Downloads and puts in place whichever of Android's tools are missing (`AndroidTools.install`): a Java runtime,
 * Google's command-line tools and Gradle, each checked against the checksum its maker publishes, then through Google's
 * own package manager the platform, and the emulator with its system image (`tv`: the TV's image too). Google's terms
 * for its packages are accepted as they install, which is why only the person starts this.
 */
export async function installTools({ emulator = true, tv = false, said = () => {} } = {}) {
  const s = spec(), p = paths();
  if (s.arch !== (process.arch === "x64" ? "x86_64" : process.arch)) throw new Problem("this copy of lamp has Android's tools for another kind of Mac: scripts/cli-files.sh writes them for this one");
  mkdirSync(p.tools, { recursive: true });
  mkdirSync(p.userHome, { recursive: true });
  let there = toolsThere();
  if (!there.jdk) {
    await fetchInto(s.jdk, p.jdk, "tar", "Java", said);
    // Temurin's archive holds one folder, jdk-17…/Contents/Home: that folder's contents are what's kept.
    flatten(p.jdk);
    if (!(await run(p.java, ["-version"])).ok) { rmSync(p.jdk, { recursive: true, force: true }); throw new Problem("Java didn't start on this Mac."); }
  }
  if (!there.commandLineTools) {
    // Google's package manager wants itself at cmdline-tools/latest inside the SDK.
    const latest = join(p.sdk, "cmdline-tools", "latest");
    mkdirSync(dirname(latest), { recursive: true });
    await fetchInto(s.commandLineTools, latest, "zip", "Google's tools", said);
    flatten(latest);
    for (const tool of [p.sdkmanager, p.avdmanager]) chmodSync(tool, 0o755);
  }
  if (!there.gradle) {
    await fetchInto(s.gradleRelease, p.gradleFolder, "zip", "Gradle", said);
    flatten(p.gradleFolder);
    chmodSync(p.gradle, 0o755);
  }
  there = toolsThere();
  const packages = [...(there.buildPackages ? [] : s.buildPackages), ...(emulator && !there.emulatorPackages ? s.emulatorPackages : []), ...(tv && !there.tvImage ? [s.tv.image] : [])];
  if (packages.length) {
    said(`Downloading ${emulator || tv ? "the Android platform and emulator" : "the Android platform"}, which takes a while…`);
    // Google's terms have to be accepted for each package; sdkmanager asks on its input.
    const script = '/usr/bin/yes | "$LAMP_SDKMANAGER" --licenses > /dev/null 2>&1; /usr/bin/yes | "$LAMP_SDKMANAGER" --install "$@" 2>&1';
    const ran = await run("/bin/sh", ["-c", script, "sh", ...packages], { cwd: p.tools, env: { ...environment(), LAMP_SDKMANAGER: p.sdkmanager }, timeout: 2 * 3600_000 });
    there = toolsThere();
    if (!there.buildPackages || (emulator && !there.emulatorPackages) || (tv && !there.tvImage)) throw new Problem(`Google's tools couldn't download the Android platform.\n${tail(ran.out, 6)}`);
  }
  return toolsThere();
}

/** Lets go of everything lamp made for Android: its emulators (closed first), and its key to the person's devices. The tools stay, every Lamp's. */
export async function forgetAndroid() {
  if (knowsAndroid() && toolsThere().buildPackages) {
    for (const kind of Object.keys(EMULATORS)) await closeEmulator(kind).catch(() => {});
  }
  const had = existsSync(androidHome());
  rmSync(androidHome(), { recursive: true, force: true });
  return had;
}

/** lamp's emulators, each with whether it's made and whether it's running now, for `lamp devices`. */
export async function emulators() {
  const p = paths(), s = spec(), there = toolsThere(), all = [];
  for (const kind of Object.keys(EMULATORS)) {
    const downloaded = there.emulatorPackages && (kind !== "tv" || there.tvImage);
    all.push({ kind, ...EMULATORS[kind], downloaded, made: existsSync(join(p.avdHome, `${s[kind].avd}.avd`, "config.ini")),
      running: downloaded && there.buildPackages ? await emulatorRunning(kind) : false, hidden: !!readJSON(recordOf(kind))?.hidden });
  }
  return all;
}

export { advice as androidAdvice };
