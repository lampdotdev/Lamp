// A page goes on Android as Lamp's Android app around it: the project written in lamp's own folder with the app's
// names in it, built, installed with adb, opened, looked at, tried, stopped and taken off. The tools here are
// stand-ins that answer as Gradle and adb do, so what's held is what lamp writes and what it asks of them. It runs
// where Lamp's Android host has been written beside lamp (scripts/cli-files.sh, on a Mac), and is skipped elsewhere.

import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { emulatorNamed, knowsAndroid, lookOnAndroid, packageOf, putOnAndroid, removeFromAndroid, stopOnAndroid, useOnAndroid } from "../android.mjs";
import { encode } from "../png.mjs";
import { layoutOf, stateOf } from "../state.mjs";

// adb, as much of it as lamp asks: one emulator, always there, which keeps whether the app is on it and open.
const ADB = `#!/usr/bin/env node
const { appendFileSync, readFileSync, writeFileSync } = require("node:fs");
let args = process.argv.slice(2);
appendFileSync(process.env.LAMP_TEST_LOG, JSON.stringify(args) + "\\n");
const read = () => { try { return JSON.parse(readFileSync(process.env.LAMP_TEST_STATE, "utf8")); } catch { return {}; } };
const keep = (state) => writeFileSync(process.env.LAMP_TEST_STATE, JSON.stringify(state));
if (args[0] === "-s") args = args.slice(2);
const said = args.join(" "), state = read();
if (said === "devices -l") console.log("List of devices attached\\nemulator-47918          device product:sdk model:sdk_gphone device:emu");
else if (said.includes("sys.boot_completed")) console.log("1");
else if (said === "shell date +%s") console.log("1800000000");
else if (args[0] === "install") { keep({ ...state, installed: true }); console.log("Success"); }
else if (said.startsWith("shell am force-stop")) keep({ ...state, open: false });
else if (said.startsWith("shell am start")) { keep({ ...state, open: true, front: args.at(-1) }); console.log("Status: ok"); }
else if (said === "shell dumpsys activity activities") console.log(state.open ? "  mResumedActivity: ActivityRecord{7 u0 " + state.front + " t3}" : "  mResumedActivity: ActivityRecord{2 u0 com.android.launcher/.Home t1}");
else if (said.startsWith("shell pidof")) { if (state.open) console.log("4242"); else process.exit(1); }
else if (said === "exec-out screencap -p") process.stdout.write(Buffer.from(process.env.LAMP_TEST_PICTURE, "base64"));
else if (args[0] === "logcat") console.log("--------- beginning of main\\nI/Lamp    ( 4242): Lamp: 60 frames a second\\nE/AndroidRuntime( 4242): FATAL EXCEPTION: main");
else if (args[0] === "uninstall") { keep({}); console.log("Success"); }
`;

// Gradle: the build's one product, where Lamp's project says it goes.
const GRADLE = `#!/usr/bin/env node
const { mkdirSync, writeFileSync } = require("node:fs");
mkdirSync("app/build/outputs/apk/debug", { recursive: true });
writeFileSync("app/build/outputs/apk/debug/app-debug.apk", "apk");
`;

test("a game goes on lamp's Android emulator, is looked at and tried there, stopped and taken off", { skip: !knowsAndroid() && "Lamp's Android host isn't beside lamp here" }, async () => {
  const home = mkdtempSync(join(tmpdir(), "lamp-android-test-")), tools = join(home, "tools"), spec = JSON.parse(readFileSync(new URL("../lamps/android-host/tools.json", import.meta.url), "utf8"));
  Object.assign(process.env, { LAMP_ANDROID_TOOLS: tools, LAMP_ANDROID_HOME: join(home, "android"), LAMP_DEV_HOME: join(home, "dev"), LAMP_GRADLE_HOME: join(home, "gradle"),
    LAMP_TEST_LOG: join(home, "adb.log"), LAMP_TEST_STATE: join(home, "device.json"), LAMP_TEST_PICTURE: encode(4, 2, Buffer.alloc(32, 90)).toString("base64") });
  const program = (path, text = "") => { mkdirSync(dirname(join(tools, path)), { recursive: true }); writeFileSync(join(tools, path), text); chmodSync(join(tools, path), 0o755); };
  try {
    for (const path of ["jdk/Contents/Home/bin/java", "sdk/cmdline-tools/latest/bin/sdkmanager", "sdk/cmdline-tools/latest/bin/avdmanager", `sdk/build-tools/${spec.buildTools}/aapt2`,
      `sdk/platforms/android-${spec.platform}/android.jar`, "sdk/emulator/emulator", `sdk/${spec.phone.image.replaceAll(";", "/")}/system.img`]) program(path);
    program("sdk/platform-tools/adb", ADB);
    program(`gradle-${spec.gradle}/bin/gradle`, GRADLE);

    const folder = join(home, "harbor-racer");
    mkdirSync(join(folder, "_parts"), { recursive: true });
    writeFileSync(join(folder, "index.html"), "<!doctype html><title>Harbor &lt;Racer&gt; &amp; \"Friends\"</title><script type=module src=game.js></script>");
    writeFileSync(join(folder, "lamp-game.js"), "export const game = {};\n");
    writeFileSync(join(folder, "game.js"), "import './lamp-game.js';\n");
    writeFileSync(join(folder, "_parts", "sea.js"), "export default 1;\n");
    const layout = layoutOf(folder), place = emulatorNamed("android"), pkg = packageOf(layout);
    const asked = () => readFileSync(process.env.LAMP_TEST_LOG, "utf8").trim().split("\n").map((line) => JSON.parse(line).join(" "));

    const put = await putOnAndroid(layout, place, { hidden: true });
    assert.match(pkg, /^dev\.lamp\.cli\.harbor_racer_[0-9a-f]{8}$/, "a package of lamp's own, never one Lamp's app installs");
    assert.equal(put.package, pkg);
    const project = join(stateOf(layout.folder), "android", "Lamp", "Android"), assets = join(stateOf(layout.folder), "android", "build", "android-assets", "Web");
    const manifest = readFileSync(join(project, "app", "src", "main", "AndroidManifest.xml"), "utf8");
    assert.match(manifest, /android:label="Harbor &lt;Racer&gt; &amp; &quot;Friends&quot;"/, "the app's name as text, whatever is in it");
    assert.match(manifest, /android:isGame="true"/);
    assert.match(readFileSync(join(project, "app", "src", "main", "kotlin", ...pkg.split("."), "MainActivity.kt"), "utf8"), new RegExp(`^package ${pkg.replaceAll(".", "\\.")}$`, "m"));
    assert.match(readFileSync(join(project, "app", "build.gradle.kts"), "utf8"), new RegExp(`applicationId = "${pkg.replaceAll(".", "\\.")}"`));
    assert.ok(!existsSync(join(folder, "Lamp")), "nothing of the build is written in the app's own folder");
    assert.match(readFileSync(join(assets, "lamp-device.js"), "utf8"), /\(android\)/, "the game is told it's on Android");
    assert.ok(existsSync(join(assets, "_parts", "sea.js")));
    assert.ok(asked().some((line) => line.startsWith("-s emulator-47918 install -r -t ")) && asked().includes(`-s emulator-47918 shell am start -W -n ${pkg}/.MainActivity`));

    // A file gone from the page is gone from the copy the next build takes.
    rmSync(join(folder, "_parts"), { recursive: true });
    await putOnAndroid(layout, place, { hidden: true });
    assert.ok(!existsSync(join(assets, "_parts")));

    const seen = await lookOnAndroid(layout, place);
    assert.equal(seen.running, true);
    assert.deepEqual(seen.size, { width: 4, height: 2 });
    assert.equal(seen.log, "Lamp: 60 frames a second\nAndroidRuntime: FATAL EXCEPTION: main", "the page's own words, and how Android ended it");

    await useOnAndroid(layout, place, [{ kind: "button", buttons: "a", seconds: "0.5" }, { kind: "click", x: "10", y: "20" }]);
    assert.ok(asked().includes("-s emulator-47918 shell input gamepad keyevent --duration 500 KEYCODE_BUTTON_A") && asked().includes("-s emulator-47918 shell input tap 10 20"));
    await assert.rejects(useOnAndroid(layout, place, [{ kind: "click", x: "1", y: "1" }, { kind: "stick", side: "left" }]), /can't move a stick/);
    assert.ok(!asked().includes("-s emulator-47918 shell input tap 1 1"), "a move lamp can't make stops the ones before it too");

    assert.equal(await stopOnAndroid(layout, place), true);
    assert.equal((await lookOnAndroid(layout, place)).running, false);
    assert.equal(await removeFromAndroid(layout, place), true);
    assert.ok(asked().includes(`-s emulator-47918 uninstall ${pkg}`));
    assert.equal(await removeFromAndroid(layout, place), false, "nothing of lamp's left to take off");
  } finally { rmSync(home, { recursive: true, force: true }); }
});

test("what adb says is read once, for lamp and for Lamp's app: devices, a device's own words, an app's process, the screen", async () => {
  const { dumpIn, processIn, propertiesOf, rowsOf, screenItems } = await import("../android.mjs");
  const { encode, resized, sizeOf } = await import("../png.mjs");
  assert.deepEqual(rowsOf("List of devices attached\nemulator-5554          device product:sdk model:Pixel\n192.168.1.50:5555 unauthorized\n\n"),
    [{ serial: "emulator-5554", state: "device" }, { serial: "192.168.1.50:5555", state: "unauthorized" }]);
  assert.deepEqual(propertiesOf("ro.product.model=Den TV\nleanback=true\nPhysical size: 1920x1080\nPhysical density: 320\n"),
    { "ro.product.model": "Den TV", leanback: "true", size: "1920x1080", density: "320" });
  assert.deepEqual(processIn({ ok: true, out: "4242\n" }), { state: "running", pid: 4242 });
  assert.deepEqual(processIn({ ok: false, out: "", err: "adb: device 'x' not found" }), { state: "unreachable" }, "a device adb can't reach isn't an app that quit");
  assert.deepEqual(processIn({ ok: false, out: "" }), { state: "gone" });
  assert.deepEqual(processIn({ ok: false, out: "", timedOut: true }), { state: "unreachable" });

  const dump = `noise<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0">
    <node class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" clickable="false" text="" content-desc="">
      <node class="android.widget.TextView" text="Tea &amp; Toast" bounds="[60,120][600,180]" clickable="false" enabled="true" />
      <node class="android.widget.EditText" text="" hint="Name" bounds="[60,300][1020,420]" clickable="true" focused="true" />
      <node class="android.widget.Switch" text="Sugar" bounds="[60,500][1020,600]" clickable="true" checkable="true" checked="true" />
      <node class="android.widget.Button" text="Brew" bounds="[60,700][600,800]" clickable="true" enabled="false" />
    </node></hierarchy>trailing`;
  const xml = dumpIn(dump);
  assert.ok(xml.startsWith("<?xml") && xml.endsWith("</hierarchy>"));
  const items = screenItems(xml, 3);
  assert.deepEqual(items.map((item) => `${item.id} ${item.kind} ${item.name}`), ["t1 text Tea & Toast", "f1 field Name", "s1 switch Sugar", "b1 button Brew"]);
  assert.deepEqual(items[0].frame, { x: 20, y: 40, width: 180, height: 20 }, "in points, the dump's pixels over the scale");
  assert.equal(items[1].focused, true);
  assert.equal(items[2].checked, true);
  assert.equal(items[3].enabled, false);
  assert.equal(dumpIn("ERROR: null root node returned by UiTestAutomationBridge."), null, "a screen asleep has no dump");

  const shot = encode(4, 2, Buffer.alloc(32, 120));
  assert.deepEqual(sizeOf(resized(shot, 2)), { width: 2, height: 1 }, "a picture made smaller in proportion");
});
