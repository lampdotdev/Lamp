// What's on the home network besides what the integrations find: the TVs, read as a Samsung's API and an LG's
// descriptions say (an LG TV's answers and descriptions as Tests/Fixtures/lg-webos-tv recorded them), the subnet a
// sweep takes, and a Bonjour record's words.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { answerOf } from "../devices.mjs";
import { entriesOf } from "../mdns.mjs";
import { LG_TV, lgAt, samsungAt, subnetOf, tvsIn } from "../network.mjs";

const RECORDED = new URL("../../Tests/Fixtures/lg-webos-tv/", import.meta.url), ADDRESS = "192.168.1.20";
const answers = () => readFileSync(new URL("ssdp.txt", RECORDED), "utf8").split("\n\n").map((text) => answerOf(text, ADDRESS));
const descriptions = async ({ port }) => { try { return readFileSync(new URL(`${port}.xml`, RECORDED)); } catch { return null; } };

test("an LG TV is read under its own service when a streaming service answers first, and says every id it answers for", async () => {
  const all = answers();
  assert.equal(all[0].location, "http://192.168.1.20:9080", "the first answer's description says nothing of the TV");
  const tv = await lgAt(ADDRESS, all, { get: descriptions });
  assert.equal(tv.id, "lg:11111111-2222-4333-8444-000000001904");
  assert.equal(tv.name, "[LG] webOS TV NANO80ASA");
  assert.equal(tv.model, "65NANO80ASA.BWCDLKR");
  assert.ok(tv.udns.includes("11111111-2222-4333-8444-000000001601"), "another of its services' ids, for a TV kept under that one");
  // Its own service missed the search: read under another's, which still names it among the ids.
  const others = all.filter((answer) => answer.target !== LG_TV && !String(answer.location).includes(":1904"));
  const again = await lgAt(ADDRESS, others, { get: descriptions });
  assert.notEqual(again.id, tv.id);
  assert.ok(again.udns.some((udn) => tv.udns.includes(udn)));
  // Found among the look's answers by what they say of it.
  assert.deepEqual((await tvsIn(all, { get: descriptions })).map((each) => each.id), [tv.id]);
});

test("a Samsung TV is read from its own API, its model and Tizen from its model codes", async () => {
  const api = (device) => async () => Buffer.from(JSON.stringify({ device }));
  const frame = await samsungAt("192.168.1.30", { get: api({ OS: "Tizen", modelName: "QN50LS03BAFXZA", FrameTVSupport: "true", model: "22_PONTUSM_FTV",
    id: "uuid:made-up", name: "Den TV", resolution: "3840x2160", developerMode: "1", developerIP: "192.168.1.10" }) });
  assert.deepEqual(frame, { id: "samsung:made-up", maker: "Samsung", name: "Den TV", model: "The Frame 50", modelID: "QN50LS03BAFXZA", address: "192.168.1.30",
    os: "Tizen", osVersion: "6.5", resolution: "3840x2160", frame: true, developerIP: "192.168.1.10", developerMode: true });
  assert.equal((await samsungAt("192.168.1.31", { get: api({ OS: "Tizen", modelName: "UN65TU7000", model: "20_X" }) })).model, "Smart TV 65");
  assert.equal(await samsungAt("192.168.1.32", { get: api({ OS: "Linux" }) }), null, "only a Tizen TV");
  assert.equal(await samsungAt("192.168.1.33", { get: async () => Buffer.from("not json") }), null);
});

test("a sweep takes no more than the 256 addresses around this computer's, on a home network only", () => {
  assert.deepEqual(subnetOf("10.0.0.20", "255.255.255.0"), { network: "10.0.0.0", prefix: 24, actualPrefix: 24, mine: "10.0.0.20" });
  assert.deepEqual(subnetOf("172.16.5.9", "255.255.0.0"), { network: "172.16.5.0", prefix: 24, actualPrefix: 16, mine: "172.16.5.9" });
  assert.deepEqual(subnetOf("192.168.1.130", "255.255.255.128"), { network: "192.168.1.128", prefix: 25, actualPrefix: 25, mine: "192.168.1.130" });
  assert.equal(subnetOf("8.8.8.8", "255.255.255.0"), null, "not a home network");
  assert.equal(subnetOf("10.0.0.20", "255.0.0.0").prefix, 24);
  assert.equal(subnetOf("10.0.0.20", "255.255.255.254"), null, "too small to be a network");
});

test("a Bonjour record's words: a bare key is an empty word, and the first value for a key wins", () => {
  const entry = (text) => Buffer.concat([Buffer.from([Buffer.byteLength(text)]), Buffer.from(text)]);
  assert.deepEqual(entriesOf(Buffer.concat([entry("flag"), entry("model=Example model"), entry("model=Another"), Buffer.from([0]), entry("=no key")])),
    { flag: "", model: "Example model" });
  assert.deepEqual(entriesOf(Buffer.from([9, 0x61])), {}, "a record cut short says nothing more");
});
