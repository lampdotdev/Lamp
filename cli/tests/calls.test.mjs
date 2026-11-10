// What Lamp's app asks of lamp goes through one file (calls.mjs), run once for each call: what it's given on its
// input, and its answer as the last line it prints. The first call is an Xbox's package, made from a folder of files.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const CALLS = fileURLToPath(new URL("../calls.mjs", import.meta.url));

/** One call as Lamp's app makes it: the answer's last line, and how the run ended. */
function call(name, given) {
  const ran = spawnSync(process.execPath, [CALLS, name], { input: JSON.stringify(given), encoding: "utf8" });
  const last = ran.stdout.trim().split("\n").pop();
  return { status: ran.status, answer: last ? JSON.parse(last) : null, errors: ran.stderr };
}

test("Lamp's app has an Xbox's package made from a folder of files", () => {
  const home = mkdtempSync(join(tmpdir(), "lamp-calls-test-"));
  try {
    mkdirSync(join(home, "payload", "Web"), { recursive: true });
    writeFileSync(join(home, "payload", "App.exe"), "host");
    writeFileSync(join(home, "payload", "Web", "index.html"), "<p>the game</p>");
    const given = { payload: join(home, "payload"), out: join(home, "out", "package.msix"), certificate: join(home, "out", "certificate.cer"),
      displayName: "Harbor Racer", slug: "harbor-racer", architecture: "x64", entry: "webHost", signer: join(home, "signer") };

    const made = call("msix", given);
    assert.equal(made.status, 0, made.errors);
    assert.equal(made.answer.done.identity.name, "Lamp.harbor-racer");
    assert.equal(made.answer.done.fullName, `Lamp.harbor-racer_${made.answer.done.identity.version}_x64__nx0tdkwh5ctmc`);
    assert.equal(made.answer.done.files, 2);
    const written = readFileSync(given.out);
    assert.equal(written.length, made.answer.done.bytes);
    assert.ok(written.includes("<p>the game</p>") && written.includes('Name="Lamp.harbor-racer"'));
    assert.ok(readFileSync(given.certificate).length > 0, "the certificate a device installs beside it");
    assert.equal(statSync(join(given.signer, "key.der")).mode & 0o777, 0o600, "the key it was signed with is kept, the person's alone to read");

    // A newer version than the last, and the same key the next time.
    const next = call("msix", { ...given, after: made.answer.done.identity.version });
    assert.notEqual(next.answer.done.identity.version, made.answer.done.identity.version);
    assert.deepEqual(readFileSync(given.certificate), readFileSync(join(given.signer, "certificate.der")));

    // What the person can put right is said in a sentence, and ends the run as a failure; a link is never followed.
    symlinkSync("/etc/hosts", join(home, "payload", "Web", "secret"));
    const linked = call("msix", given);
    assert.equal(linked.status, 1);
    assert.equal(linked.answer.problem, "Web/secret is a shortcut to another file. Put the file itself in its place.");

    // Anything else is lamp's own fault: no answer, and its words on standard error.
    const unknown = call("no-such-call", {});
    assert.notEqual(unknown.status, 0);
    assert.equal(unknown.answer, null);
    assert.match(unknown.errors, /no call named "no-such-call"/);
  } finally { rmSync(home, { recursive: true, force: true }); }
});
