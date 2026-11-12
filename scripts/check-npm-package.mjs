#!/usr/bin/env node
// Exercise the npm tarball away from the checkout: tests run from cli/ can read files that packing leaves out.
// The CLI's page.js and generated starters must survive both npm pack and npm install.
//   node scripts/check-npm-package.mjs build/npm/lampdotdev-lamp-0.0.0.tgz
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const archive = resolve(process.argv[2] ?? "");
assert.ok(process.argv[2], "Give the tarball made by scripts/npm-package.sh");
const temporary = mkdtempSync(join(tmpdir(), "lamp-npm-check-"));
try {
  const install = join(temporary, "install");
  const env = { ...process.env, CI: "1", LAMP_NO_UPDATE_CHECK: "1", LAMP_DEV_HOME: join(temporary, "state") };
  const run = (command, args) => execFileSync(command, args, { cwd: temporary, env, encoding: "utf8", timeout: 60_000 });
  run("npm", ["install", "--prefix", install, "--cache", join(temporary, "cache"), "--offline", "--ignore-scripts", "--no-audit", "--no-fund", archive]);
  const lamp = (...args) => run(join(install, "node_modules", ".bin", "lamp"), args);
  // Even help imports the server, which reads page.js at module load. A source-only check misses a lost copy.
  assert.ok(lamp("--help").trim(), "The installed command prints help");
  assert.ok(lamp("guide").trim(), "The installed command carries its agent guide");
  assert.ok(lamp("skill", "game").trim(), "The installed command reads Lamp's skills");

  for (const [kind, flags, files] of [
    ["game", [], ["index.html", "lamp-game.js", "lamp-controllers.js", "lamp.js", "three/three.module.js"]],
    ["web", ["--web"], ["index.html", "lamp.js"]],
    ["mac", ["--mac"], ["Package.swift", "build.sh", "Sources/LampSupport.swift", ".gitignore"]],
  ]) {
    const folder = join(temporary, kind);
    lamp("new", folder, "--name", "Harbor App", ...flags);
    for (const file of files) assert.ok(statSync(join(folder, file)).size > 0, `${kind}: ${file} is included`);
    if (kind === "mac") {
      // npm drops files named .gitignore. Packing carries this one as gitignore so a new app keeps its exclusions.
      assert.ok(readFileSync(join(folder, ".gitignore"), "utf8").includes(".build/"));
      assert.ok(lamp("blocks", folder).trim(), "The Mac starter carries its building blocks");
    }
  }
  console.log("npm package checks passed: installed command, guide, skills, game, web app and Mac app starters");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
