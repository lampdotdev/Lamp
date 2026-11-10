// A Lamp app file made from a folder holds the app's own files as Lamp lays them out, and none of Lamp's; unpacked,
// it's the same app again. One with something shaped like a key in it isn't made, and a kind lamp doesn't run is said
// so rather than taken for another.

import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { exportApp, unpack, unzipped } from "../lampapp.mjs";
import { projectOf } from "../state.mjs";

test("a page goes into a Lamp app file and comes back out of one", () => {
  const home = mkdtempSync(join(tmpdir(), "lamp-file-test-"));
  process.env.LAMP_DEV_HOME = join(home, "dev");
  try {
    const site = join(home, "tea-notes");
    mkdirSync(join(site, "img"), { recursive: true });
    writeFileSync(join(site, "index.html"), "<!doctype html><title>Tea Notes</title><script src=lamp.js></script>");
    writeFileSync(join(site, "lamp.js"), "// Lamp's own\n");
    writeFileSync(join(site, "img", "leaf.svg"), "<svg/>");
    writeFileSync(join(site, "APP.md"), "# Tea Notes\n");
    writeFileSync(join(site, ".env"), "SECRET=1\n");

    const made = exportApp(site);
    const files = unzipped(made.bytes);
    assert.deepEqual([...files.keys()].sort(), ["APP.md", "Web/img/leaf.svg", "Web/index.html", "credits.json", "lamp-app.json"], "the page in Web/, its notes beside it, nothing of Lamp's and nothing hidden");
    const manifest = JSON.parse(files.get("lamp-app.json"));
    assert.equal(manifest.platform, "web-app");
    assert.equal(manifest.site, true);
    assert.equal(manifest.format, 12);
    assert.equal(exportApp(site).bytes.length > 0 && JSON.parse(unzipped(exportApp(site).bytes).get("lamp-app.json")).app, manifest.app, "the same app in every file made from it");

    writeFileSync(join(home, "Tea Notes.lampapp"), made.bytes);
    const opened = unpack(join(home, "Tea Notes.lampapp"));
    assert.equal(opened.folder, join(home, "Tea Notes"));
    assert.equal(opened.project.kind, "page");
    assert.equal(readFileSync(join(opened.folder, "Web", "img", "leaf.svg"), "utf8"), "<svg/>");
    assert.throws(() => unpack(join(home, "Tea Notes.lampapp")), /already has things in it/, "nothing of anyone's is written over");

    writeFileSync(join(site, "keys.js"), `const key = "sk-ant-${"x".repeat(40)}";`);
    assert.throws(() => exportApp(site), /holds a key or a password, in Web\/keys\.js/);

    const phone = join(home, "phone");
    mkdirSync(join(phone, "Sources"), { recursive: true });
    writeFileSync(join(phone, "lamp-app.json"), JSON.stringify({ format: 6, name: "Phone", platform: "iphone" }));
    assert.throws(() => projectOf(phone), /is an iPhone app, which lamp doesn't build or run/);
  } finally { rmSync(home, { recursive: true, force: true }); }
});
