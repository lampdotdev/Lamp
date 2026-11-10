// The package lamp makes for an Xbox is the one Lamp's app makes (Sources/Lamp/MSIX.swift): the same manifest, and
// the same files in the same layout, which the signature says, since it signs the hashes of the package's records,
// its directory, its block map and its content types. The example here is written by Lamp's own code
// (scripts/cli-files.sh), under a key made for this alone.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";
import { assemble, identityName, manifest, namesOf, PUBLISHER, signerFrom, versionAfter } from "../msix.mjs";

const kept = (name) => readFileSync(join(dirname(fileURLToPath(import.meta.url)), "fixtures", "msix", name));

test("an Xbox's package is the one Lamp's app makes", () => {
  const identity = { name: identityName("harbor-racer-1a2b3c4d"), publisher: PUBLISHER, version: "1.7.4660.2", architecture: "x64" };
  const written = manifest(identity, 'Harbor <Racer> & "Friends"', "webHost");
  assert.equal(written, kept("manifest.xml").toString());

  const names = JSON.parse(kept("names.json"));
  assert.equal(namesOf(identity).fullName, names.fullName);
  assert.equal(namesOf(identity).appUserModelID, names.appUserModelID);
  assert.equal(versionAfter("1.0.0.0", new Date(1_800_000_000_000)), names.nextVersion);
  assert.equal(versionAfter("1.8.27776.0", new Date(1_800_000_000_000)), names.sameMinute);

  const made = assemble([
    ["App.exe", Buffer.from("host")],
    ["Web/index.html", Buffer.from("<!doctype html><title>Harbor Racer</title>")],
    ["Web/LICENSE", Buffer.from("MIT")],
    ["Web/sea & sky.txt", Buffer.from("blue")],
    ["Web/empty.js", Buffer.alloc(0)],
    ["Web/big.bin", Buffer.from(Array.from({ length: 70_000 }, (_, i) => i % 251))],
    ["AppxManifest.xml", Buffer.from(written)],
  ], signerFrom(kept("key.der"), kept("certificate.der")));

  // The signature's own record is the one deflated one, and each side deflates in its own way: read back out, it's
  // what the two compare.
  const name = Buffer.from("AppxSignature.p7x");
  let at = -1;
  for (let found = made.indexOf(name); found >= 0; found = made.indexOf(name, found + 1)) {
    if (found >= 30 && made.readUInt32LE(found - 30) === 0x04034b50) at = found - 30;
  }
  assert.ok(at >= 0, "the package has its signature's record");
  const packed = made.readUInt32LE(at + 18);
  const signature = inflateRawSync(made.subarray(at + 30 + name.length, at + 30 + name.length + packed));
  assert.ok(signature.equals(kept("signature.p7x")), "the signature, and so every record, the directory, the block map and the content types");
});
