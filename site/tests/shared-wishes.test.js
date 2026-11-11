import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { deflateSync, crc32 } from "node:zlib";
import { createShareHandler, createFileHandler, createIdeasHandler, createIdeaMailHandler, replyWords, IDEA_LIMITS, createPlayHandler, pictureScript, memoryStore, readShare, imageInfo, isID, isWishFile, readZip, slugFor, wishIDFrom, LIMITS, FILE_LIMITS } from "../lib/shared-wishes.js";
import { createPageHandler } from "../lib/shared-wish-page.js";
import { createCardHandler } from "../lib/wish-card.js";

/** A plain PNG of one color, as Lamp's pictures are PNGs or JPEGs. */
function png(width, height) {
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
    const out = Buffer.alloc(8 + data.length + 4);
    out.writeUInt32BE(data.length, 0);
    body.copy(out, 4);
    out.writeUInt32BE(crc32(body), 8 + data.length);
    return out;
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 2;
  const rows = Buffer.alloc((width * 3 + 1) * height, 0x80);
  for (let y = 0; y < height; y++) rows[y * (width * 3 + 1)] = 0;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", header), chunk("IDAT", deflateSync(rows)), chunk("IEND", Buffer.alloc(0))]);
}

const share = {
  name: "Plant Pal",
  line: "Reminds me when each plant needs water.",
  words: "A Mac app that keeps my plants <watered> & tells me \"which one\" is thirsty.\nNothing else.",
  picture: png(300, 200).toString("base64"),
  icon: png(64, 64).toString("base64"),
};

const send = (handler, method, body, { id, secret, origin, type = "application/json" } = {}) => handler(new Request(`https://lamp.dev/api/wishes${id ? `?id=${id}` : ""}`, {
  method,
  headers: { "content-type": type, ...(secret ? { authorization: `Bearer ${secret}` } : {}), ...(origin ? { origin } : {}) },
  ...(body === undefined ? {} : { body: typeof body === "string" ? body : JSON.stringify(body) }),
}));

test("only a checked wish is taken: known fields, plain words within their limits, real pictures", () => {
  const read = readShare(share);
  assert.equal(read.name, "Plant Pal");
  assert.equal(read.picture.width, 300);
  assert.equal(read.icon.type, "image/png");
  assert.equal(readShare({ ...share, picture: null, icon: undefined }).picture, null);
  assert.equal(readShare({ ...share, name: "Plant\u0000\nPal" }).name, "Plant Pal");
  assert.equal(readShare({ ...share, extra: 1 }), null);
  assert.equal(readShare({ ...share, name: "x".repeat(LIMITS.name + 1) }), null);
  assert.equal(readShare(share).by, "", "nobody named, with no byline");
  assert.equal(readShare({ ...share, by: "  A  Maker " }).by, "A Maker");
  assert.equal(readShare({ ...share, by: "x".repeat(LIMITS.by + 1) }), null);
  assert.deepEqual(readShare(share).ideas, [], "no suggestions");
  assert.deepEqual(readShare({ ...share, ideas: ["Water them by the weather", " Add a fern "] }).ideas, ["Water them by the weather", "Add a fern"]);
  assert.equal(readShare({ ...share, ideas: ["a", "b", "c", "d"] }), null, "at most three");
  assert.equal(readShare({ ...share, ideas: ["x".repeat(LIMITS.idea + 1)] }), null);
  assert.equal(readShare({ ...share, ideas: "Add a fern" }), null);
  assert.equal(readShare(share).shape, null, "a link that says no shape");
  assert.equal(readShare({ ...share, shape: 16 / 9 }).shape, 1.7778);
  assert.equal(readShare({ ...share, shape: "fill" }).shape, "fill");
  assert.equal(readShare({ ...share, shape: 9 }), null, "no shape that thin or wide");
  assert.equal(readShare({ ...share, shape: "16:9" }), null);
  assert.equal(readShare({ ...share, name: "e\u0301".repeat(LIMITS.name) }).name.length, LIMITS.name * 2, "counted as Lamp counts");
  assert.equal(readShare({ ...share, words: "  " }), null);
  assert.equal(readShare({ ...share, picture: Buffer.from("<svg></svg>").toString("base64") }), null);
  assert.equal(readShare({ ...share, icon: png(64, 32).toString("base64") }), null, "an icon is square");
  assert.equal(readShare({ ...share, picture: png(5000, 10).toString("base64") }), null);
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, 0xff, 0xc0, 0, 11, 8, 0, 120, 0, 160, 3, 1, 2, 3]);
  assert.deepEqual(imageInfo(jpeg), { type: "image/jpeg", extension: "jpg", width: 160, height: 120 });
});

test("a wish is shared, changed and taken down only with its secret", async () => {
  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  const created = await send(handler, "POST", share);
  assert.equal(created.status, 201);
  const { id, url, secret } = await created.json();
  assert.ok(isID(id));
  assert.equal(url, `https://lamp.dev/w/${id}-plant-pal`, "the link carries the wish's name, only for reading");
  assert.ok(!JSON.stringify([...store.records.values()]).includes(secret), "only the secret's hash is kept");

  assert.equal((await send(handler, "PUT", { ...share, name: "Thief" }, { id, secret: "x".repeat(43) })).status, 404);
  assert.equal((await send(handler, "PUT", { ...share, name: "Plant Friend", picture: null }, { id, secret })).status, 200);
  assert.equal(store.records.get(id).name, "Plant Friend");
  assert.equal(store.records.get(id).picture, null);

  assert.equal((await send(handler, "DELETE", undefined, { id })).status, 404);
  assert.equal((await send(handler, "DELETE", undefined, { id, secret })).status, 204);
  assert.equal(store.records.has(id), false);
});

test("what's new in each release is checked, kept newest first, and kept by a change that doesn't say", async () => {
  const older = { date: "2026-10-01T09:00:00Z", lines: ["Plants have names now"] };
  const newer = { date: "2026-11-02T10:30:00.000Z", lines: ["Reminders come at dawn", " Ferns  are in "] };
  assert.deepEqual(readShare({ ...share, releases: [older, newer] }).releases.map((r) => r.lines[0]), ["Reminders come at dawn", "Plants have names now"]);
  assert.equal(readShare(share).releases, undefined, "a Lamp from before them says nothing");
  assert.equal(readShare({ ...share, releases: [{ ...older, lines: [] }] }), null, "a release says something");
  assert.equal(readShare({ ...share, releases: [{ ...older, lines: Array(LIMITS.releaseLines + 1).fill("a") }] }), null);
  assert.equal(readShare({ ...share, releases: [{ ...older, lines: ["x".repeat(LIMITS.releaseLine + 1)] }] }), null);
  assert.equal(readShare({ ...share, releases: [{ ...older, date: "2999-01-01T00:00:00Z" }] }), null, "never far ahead");
  assert.equal(readShare({ ...share, releases: [{ ...older, extra: 1 }] }), null);
  assert.equal(readShare({ ...share, releases: Array(LIMITS.releases + 1).fill(older) }), null);

  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  const { id, secret } = await (await send(handler, "POST", { ...share, releases: [older] })).json();
  await send(handler, "PUT", share, { id, secret });
  assert.deepEqual(store.records.get(id).releases.map((r) => r.date), ["2026-10-01T09:00:00.000Z"]);
  await send(handler, "PUT", { ...share, releases: [older, newer] }, { id, secret });
  const page = await createPageHandler({ store, template: async () => "<html><head></head><body></body></html>" })(new Request(`https://lamp.dev/w/${id}?id=${id}`));
  assert.match(await page.text(), /"releases":\[\{"date":"2026-11-02T10:30:00.000Z","lines":\["Reminders come at dawn","Ferns are in"\]\}/);
});

test("pictures that went up are taken back when the wish can't be kept", async () => {
  const store = memoryStore();
  const removed = [];
  store.removeImages = async (urls) => { removed.push(...urls); };
  store.create = async () => { throw new Error("down"); };
  assert.equal((await send(createShareHandler({ store, limited: false }), "POST", share)).status, 503);
  assert.equal(removed.length, 2);
});

test("browsers on other sites, other kinds of body and oversized ones are refused", async () => {
  const handler = createShareHandler({ store: memoryStore(), limited: false });
  assert.equal((await send(handler, "POST", share, { origin: "https://example.com" })).status, 403);
  assert.equal((await send(handler, "POST", JSON.stringify(share), { type: "text/plain" })).status, 415);
  assert.equal((await send(handler, "POST", "{")).status, 400);
  assert.equal((await send(handler, "POST", { ...share, words: "x".repeat(3_000_000) })).status, 413);
  assert.equal((await send(handler, "PATCH")).status, 405);
  assert.equal((await send(handler, "GET")).status, 404, "a follower asks by id");
});

test("without its store or quota it answers unavailable rather than sharing", async () => {
  const handler = createShareHandler({ env: {} });
  assert.equal((await send(handler, "POST", share)).status, 503);
});

test("the page is the shared wish's own, with the wish in it, its words escaped, and its own preview", async () => {
  const store = memoryStore();
  const { id } = await (await send(createShareHandler({ store, limited: false }), "POST", share)).json();
  const built = `<!DOCTYPE html><html><head><title>An app · Lamp</title><meta name="description" content="An app made with Lamp."><link rel="canonical" href="https://lamp.dev/w/"><meta property="og:title" content="An app · Lamp"><meta name="twitter:card" content="summary"></head><body><section data-stage></section></body></html>`;
  const response = await createPageHandler({ store, template: async () => built })(new Request(`https://lamp.dev/api/wish-page?id=${id}`));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes("<section data-stage>"), "the built page");
  assert.ok(!html.includes("An app · Lamp") && !html.includes('content="summary"'), "the built page's own preview is gone");
  assert.ok(html.includes(`<meta property="og:image" content="https://lamp.dev/w/${id}/card.png?v=`));
  assert.ok(html.includes(`<meta name="twitter:card" content="summary_large_image">`));
  const card = JSON.parse(/<script type="application\/json" id="shared-wish">(.*?)<\/script>/.exec(html)[1]);
  assert.equal(card.wish, store.records.get(id).words);
  assert.equal(card.about, "Reminds me when each plant needs water.");
  assert.equal(card.by, "", "a wish shared with no name has no byline");
  assert.ok(!html.includes("<watered>"), "nothing the sharer wrote can close the script");
  assert.equal(response.headers.get("x-robots-tag"), "noindex");

  // The name after the id is only for reading: an old one, or none, finds the same wish.
  for (const part of [`${id}-old-name`, `${id}-`]) {
    assert.equal((await createPageHandler({ store, template: async () => built })(new Request(`https://lamp.dev/api/wish-page?id=${part}`))).status, 200);
  }
  assert.equal(wishIDFrom(`${id}x`), null, "the id ends at a dash");
  assert.equal(slugFor("Café  Crème!"), "cafe-creme");
  assert.equal(slugFor("東京"), "", "a name with nothing plain to spell has no slug");

  const gone = await createPageHandler({ store, template: async () => built })(new Request("https://lamp.dev/api/wish-page?id=2345678922"));
  assert.equal(gone.status, 404);
});

test("the page the function serves is the one the site builds", () => {
  const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8"));
  assert.equal(config.functions["api/wish-page.js"].includeFiles, "dist/w/index.html");
  const page = readFileSync(new URL("../src/pages/w/index.astro", import.meta.url), "utf8");
  assert.ok(page.includes('getElementById("shared-wish")'));
});

test("the card is a 1200×630 PNG, with or without a picture", async () => {
  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  for (const body of [share, { ...share, picture: null, icon: null, line: "" }]) {
    const { id } = await (await send(handler, "POST", body)).json();
    const response = await createCardHandler({ store })(new Request(`https://lamp.dev/api/wish-card?id=${id}`));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "image/png");
    const info = imageInfo(Buffer.from(await response.arrayBuffer()));
    assert.deepEqual([info.width, info.height], [1200, 630]);
  }
});

/** A zip holding stored files. */
function zipOf(entries) {
  const locals = [], centrals = [];
  let offset = 0;
  for (const [name, data] of entries) {
    const nameBytes = Buffer.from(name), local = Buffer.alloc(30), central = Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt32LE(crc32(data), 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(nameBytes.length, 26);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt32LE(crc32(data), 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(nameBytes.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(local, nameBytes, data); centrals.push(central, nameBytes);
    offset += local.length + nameBytes.length + data.length;
  }
  const directory = Buffer.concat(centrals), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, end]);
}

/** A zip holding one stored file, as Lamp's shared files are zips with lamp-app.json at their root. */
function zip(name, data) {
  const nameBytes = Buffer.from(name), local = Buffer.alloc(30), central = Buffer.alloc(46), end = Buffer.alloc(22);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt32LE(crc32(data), 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(nameBytes.length, 26);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt32LE(crc32(data), 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(nameBytes.length, 28);
  const offset = local.length + nameBytes.length + data.length;
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10); end.writeUInt32LE(central.length + nameBytes.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([local, nameBytes, data, central, nameBytes, end]);
}

test("a part sent again while its first try is still storing keeps the parts sent meanwhile", async () => {
  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  const { id, secret } = await (await send(handler, "POST", share)).json();
  // Parts kept as the site keeps them, each at an address of its own and gone once removed.
  const blobs = new Map();
  let count = 0, slowPut = true, holdPut, slowRead = false, holdRead;
  store.putFile = async (_id, _name, bytes) => {
    if (slowPut) { slowPut = false; await new Promise((resolve) => { holdPut = resolve; }); }
    const url = `blob:${count++}`;
    blobs.set(url, Buffer.from(bytes));
    return url;
  };
  store.readFile = async (url) => {
    if (slowRead) { slowRead = false; await new Promise((resolve) => { holdRead = resolve; }); }
    if (!blobs.has(url)) throw new Error("missing");
    return blobs.get(url);
  };
  store.removeImages = async (urls) => { for (const url of urls) blobs.delete(url); };
  const files = createFileHandler({ store, limited: false });
  const file = zip("lamp-app.json", Buffer.alloc(5000, 7));
  const part = (n, bytes) => files(new Request(`https://lamp.dev/api/wish-file?id=${id}&part=${n}&of=2`, {
    method: "PUT", headers: { "content-type": "application/octet-stream", authorization: `Bearer ${secret}` }, body: bytes,
  }));
  const tick = () => new Promise((resolve) => setTimeout(resolve, 10));
  // The first try at part 0 stores slowly, as one whose connection dropped can; Lamp sends it again, then part 1.
  const late = part(0, file.subarray(0, 3000));
  await tick();
  assert.equal((await part(0, file.subarray(0, 3000))).status, 204);
  assert.equal((await part(1, file.subarray(3000))).status, 204);
  // Putting them together reads the parts while the late first try lands.
  slowRead = true;
  const done = files(new Request(`https://lamp.dev/api/wish-file?id=${id}`, { method: "POST", headers: { authorization: `Bearer ${secret}` } }));
  await tick();
  holdPut();
  assert.equal((await late).status, 204);
  holdRead();
  assert.equal((await done).status, 200);
  assert.deepEqual(blobs.get(store.records.get(id).file.url), file);
});

test("the wish itself goes with its link in parts, only as a file Lamp made, and goes with the link", async () => {
  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  const files = createFileHandler({ store, limited: false });
  const { id, secret } = await (await send(handler, "POST", share)).json();
  const file = zip("lamp-app.json", Buffer.alloc(5000, 7));
  assert.ok(isWishFile(file));
  assert.equal(isWishFile(zip("readme.txt", Buffer.from("hi"))), false);
  const part = (n, of, bytes, key = secret) => files(new Request(`https://lamp.dev/api/wish-file?id=${id}&part=${n}&of=${of}`, {
    method: "PUT", headers: { "content-type": "application/octet-stream", authorization: `Bearer ${key}` }, body: bytes,
  }));
  const finish = (key = secret) => files(new Request(`https://lamp.dev/api/wish-file?id=${id}`, { method: "POST", headers: { authorization: `Bearer ${key}` } }));

  assert.equal((await part(0, 2, file.subarray(0, 3000), "x".repeat(43))).status, 404, "only with the link's secret");
  assert.equal((await part(0, FILE_LIMITS.parts + 1, file)).status, 400);
  assert.equal((await part(0, 2, file.subarray(0, 3000))).status, 204);
  assert.equal((await finish()).status, 409, "not until every part is there");
  assert.equal((await part(1, 2, file.subarray(3000))).status, 204);
  const done = await finish();
  assert.equal(done.status, 200);
  assert.equal(store.records.get(id).parts, undefined, "the parts go once they're together");
  assert.deepEqual(Buffer.from(store.records.get(id).file.url.split(",")[1], "base64"), file);

  const page = await createPageHandler({ store, template: async () => "<html><head></head><body></body></html>" })(new Request(`https://lamp.dev/api/wish-page?id=${id}`));
  assert.match(await page.text(), /"file":"data:application\/octet-stream;base64,[^"]+","fileSize":\d+/);

  // Lamps that follow the link see the file's version, and each file sent again counts up; never the secret.
  const latest = async () => (await handler(new Request(`https://lamp.dev/api/wishes?id=${id}`))).json();
  assert.deepEqual(Object.keys(await latest()).sort(), ["by", "file", "format", "id", "name", "version"]);
  assert.equal((await latest()).version, 1);
  assert.equal((await part(0, 1, file)).status, 204);
  assert.equal((await finish()).status, 200);
  assert.equal((await latest()).version, 2);
  // Taken away and sent again, it's still newer than any before.
  assert.equal((await files(new Request(`https://lamp.dev/api/wish-file?id=${id}`, { method: "DELETE", headers: { authorization: `Bearer ${secret}` } }))).status, 204);
  assert.equal((await latest()).version, 0);
  assert.equal((await part(0, 1, file)).status, 204);
  assert.equal((await finish()).status, 200);
  assert.equal((await latest()).version, 3);

  // A word-only update keeps the file; taking the link down takes it too.
  assert.equal((await send(handler, "PUT", { ...share, name: "Plant Friend" }, { id, secret })).status, 200);
  assert.ok(store.records.get(id).file);
  assert.equal((await part(0, 1, zip("other.txt", Buffer.from("x")))).status, 204);
  assert.equal((await finish()).status, 400, "only a file Lamp made");
  assert.equal((await send(handler, "DELETE", undefined, { id, secret })).status, 204);
  assert.equal(store.records.has(id), false);

  // A link taken down while a part goes up keeps nothing of it.
  const again = await (await send(handler, "POST", share)).json();
  const removed = [];
  const racing = { ...store, async get(at) { const record = await store.get(at); store.records.delete(at); return record; }, async removeImages(urls) { removed.push(...urls); } };
  const late = await createFileHandler({ store: racing, limited: false })(new Request(`https://lamp.dev/api/wish-file?id=${again.id}&part=0&of=1`, {
    method: "PUT", headers: { "content-type": "application/octet-stream", authorization: `Bearer ${again.secret}` }, body: file,
  }));
  assert.equal(late.status, 404);
  assert.equal(removed.length, 1, "the part that went up is taken away");
});

test("the site and Lamp agree on the limits", () => {
  const swift = readFileSync(new URL("../../Sources/Lamp/WishLink.swift", import.meta.url), "utf8");
  assert.ok(swift.includes(`static let filePart = ${FILE_LIMITS.part.toLocaleString("en").replaceAll(",", "_")}`), "filePart");
  assert.ok(swift.includes(`static let fileTotal = ${FILE_LIMITS.total.toLocaleString("en").replaceAll(",", "_")}`), "fileTotal");
  for (const [name, value] of Object.entries({ name: LIMITS.name, by: LIMITS.by, line: LIMITS.line, words: LIMITS.words, ideas: LIMITS.ideas, idea: LIMITS.idea, asks: LIMITS.asks, ask: LIMITS.ask,
    releases: LIMITS.releases, releaseLines: LIMITS.releaseLines, releaseLine: LIMITS.releaseLine })) {
    assert.ok(swift.includes(`static let ${name} = ${value}`), name);
  }
});

test("a link's page plays only from the play host, framed by the site, and Remix… waits behind it", async () => {
  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  const files = createFileHandler({ store, limited: false });
  const { id, secret } = await (await send(handler, "POST", share)).json();
  const send_ = (what, method, body, query = "") => files(new Request(`https://lamp.dev/api/wish-file?id=${id}${what}${query}`, {
    method, headers: { authorization: `Bearer ${secret}`, ...(body ? { "content-type": "application/octet-stream" } : {}) }, ...(body ? { body } : {}),
  }));
  assert.equal((await send_("", "PUT", zip("lamp-app.json", Buffer.alloc(10, 1)), "&part=0&of=1")).status, 204);
  assert.equal((await send_("", "POST")).status, 200);
  assert.equal(readZip(zip("../index.html", Buffer.from("x"))), null, "never a path that steps up");
  assert.equal((await send_("&what=page", "PUT", zip("other.html", Buffer.from("x")), "&part=0&of=1")).status, 204);
  assert.equal((await send_("&what=page", "POST")).status, 400, "a page has index.html at its root");
  const html = Buffer.from("<!doctype html><title>Plant Pal</title><script src=lamp.js></script>");
  assert.equal((await send_("&what=page", "PUT", zipOf([["index.html", html], ["dir/index.html", html], ["lamp.js", Buffer.from("// the kit")]]), "&part=0&of=1")).status, 204);
  assert.equal((await send_("&what=page", "POST")).status, 200);

  const env = { LAMP_PLAY_ORIGIN: "https://play.lamp.dev", LAMP_SITE_ORIGIN: "https://lamp.dev" };
  const play = createPlayHandler({ store, env });
  const own = `${Buffer.from(id).toString("hex")}.play.lamp.dev`;
  const served = await play(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=index.html`));
  assert.equal(served.status, 200);
  assert.match(served.headers.get("content-type"), /^text\/html/);
  assert.equal(served.headers.get("content-security-policy"), "frame-ancestors https://lamp.dev");
  // The page as it was, after what lets the link's page ask it for a picture of it, which only the site may ask.
  assert.equal(await served.text(), html.toString().replace("<!doctype html>", "<!doctype html>" + pictureScript("https://lamp.dev")), "after its doctype, so it isn't drawn in quirks mode");
  assert.equal((await play(new Request(`https://lamp.dev/api/wish-play?id=${id}&v=1&path=index.html`))).status, 404, "never on the site's own host");
  assert.equal((await play(new Request(`https://play.lamp.dev/api/wish-play?id=${id}&v=1&path=index.html`))).status, 404, "only on the link's own host");
  const gone = await play(new Request(`https://${own}/api/wish-play?id=${id}&v=2&path=index.html`));
  assert.equal(gone.status, 404, "only the version it has");
  assert.equal(gone.headers.get("origin-agent-cluster"), "?1", "a cluster of its own on every answer, errors too");

  const built = "<html><head><title>A wish</title></head><body></body></html>";
  const page = await (await createPageHandler({ store, env, template: async () => built })(new Request(`https://lamp.dev/api/wish-page?id=${id}`))).text();
  assert.match(page, new RegExp(`"play":"https://${own}/w/${id}/play/1/"`), "it plays from the link's own host, from its folder");
  assert.equal((await play(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=`))).status, 200, "the folder is its index.html");
  assert.equal((await play(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=index`))).status, 200, "a .html file by its clean name");
  const folder = await play(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=dir`));
  assert.match(await folder.text(), new RegExp(`<base href="/w/${id}/play/1/dir/">`), "a folder without its slash keeps its own files in place");
  assert.equal((await play(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=dir/`))).status, 200);
  // A big file is played straight from the store, where it's kept as what it is: not a page's HTML, not a worker's own
  // script, and not from a store a browser can't reach.
  // Each ask a minute apart, so it reads the record as this test changes it.
  let later = 0;
  const direct = createPlayHandler({ store, env, direct: 5, now: () => (later += 61_000) });
  const ask = (path, dest) => direct(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=${path}`, dest ? { headers: { "sec-fetch-dest": dest } } : {}));
  assert.equal((await ask("lamp.js")).status, 200, "the dev server's memory isn't a browser's to reach");
  const stored = store.records.get(id).page.files, kept = stored["lamp.js"];
  stored["lamp.js"] = "https://store.example/lamp.js";
  const big = await ask("lamp.js", "script");
  assert.equal(big.status, 302);
  assert.equal(big.headers.get("location"), "https://store.example/lamp.js");
  assert.equal(big.headers.get("vary"), "Sec-Fetch-Dest, Sec-Fetch-Mode");
  assert.notEqual((await ask("lamp.js", "worker")).status, 302, "a worker's script stays on the page's origin");
  assert.equal((await ask("index.html")).status, 200, "never a page's HTML");
  // A game's data goes to the store from a much smaller size; its scripts don't.
  const data = createPlayHandler({ store, env, direct: 1e9, directData: 5, now: () => (later += 61_000) });
  const pageNow = store.records.get(id).page;
  pageNow.files["map.bin"] = "https://store.example/map.bin";
  pageNow.sizes = { ...pageNow.sizes, "map.bin": 10, "lamp.js": 10 };
  const asked = (path, mode = "cors") => data(new Request(`https://${own}/api/wish-play?id=${id}&v=1&path=${path}`, { headers: { "sec-fetch-mode": mode } }));
  assert.equal((await asked("map.bin")).headers.get("location"), "https://store.example/map.bin");
  assert.notEqual((await asked("map.bin", "no-cors")).status, 302, "an element's load stays on the page's origin");
  assert.notEqual((await asked("lamp.js")).status, 302, "a script stays where its imports resolve");
  delete pageNow.files["map.bin"];
  stored["lamp.js"] = kept;
  const without = await (await createPageHandler({ store, env: {}, template: async () => built })(new Request(`https://lamp.dev/api/wish-page?id=${id}`))).text();
  assert.doesNotMatch(without, /"play"/, "with no play host, nothing plays");

  // The page goes with the wish itself, and one sent again later plays at a new address.
  assert.equal((await send_("", "DELETE")).status, 204);
  assert.equal(store.records.get(id).page, undefined);
  assert.equal((await send_("&what=page", "PUT", zip("index.html", html), "&part=0&of=1")).status, 204);
  assert.equal((await send_("&what=page", "POST")).status, 200);
  assert.equal(store.records.get(id).page.version, 2);

  // A game's files are served from the link's record as remembered for a minute, not read from the store for each;
  // a version the memory doesn't have is read afresh.
  let reads = 0, clock = 0;
  const counted = { ...store, get: async (id) => { reads += 1; return store.get(id); } };
  const remembering = createPlayHandler({ store: counted, env, now: () => clock });
  const v = store.records.get(id).page.version;
  for (let i = 0; i < 5; i++) assert.equal((await remembering(new Request(`https://${own}/api/wish-play?id=${id}&v=${v}&path=index.html`))).status, 200);
  assert.equal(reads, 1);
  await remembering(new Request(`https://${own}/api/wish-play?id=${id}&v=${v + 1}&path=index.html`));
  assert.equal(reads, 2, "a version it doesn't have");
  clock += 61_000;
  await remembering(new Request(`https://${own}/api/wish-play?id=${id}&v=${v}&path=index.html`));
  assert.equal(reads, 3, "after a minute");
  clock += 61_000;
  await Promise.all(Array.from({ length: 20 }, () => remembering(new Request(`https://${own}/api/wish-play?id=${id}&v=${v}&path=index.html`))));
  assert.equal(reads, 4, "files asked for at once share one read");

  // A new page leaves the one before it playable, for a game still open on it; the one before that goes.
  const again = async () => {
    assert.equal((await send_("&what=page", "PUT", zip("index.html", html), "&part=0&of=1")).status, 204);
    assert.equal((await send_("&what=page", "POST")).status, 200);
  };
  // A handler of its own each time: one remembers a link's record for a minute.
  const plays = async (v) => (await createPlayHandler({ store, env })(new Request(`https://${own}/api/wish-play?id=${id}&v=${v}&path=index.html`))).status;
  await again();
  assert.deepEqual([await plays(2), await plays(3)], [200, 200]);
  await again();
  assert.deepEqual([await plays(2), await plays(3), await plays(4)], [404, 200, 200]);
});

test("the maker and an idea's sender talk by email, the replies kept on the idea's thread", async () => {
  const { createHmac } = await import("node:crypto");
  const store = memoryStore();
  const { id, secret } = await (await send(createShareHandler({ store, limited: false }), "POST", { ...share, by: "Alex" })).json();
  const secretKey = Buffer.from("a webhook's own secret").toString("base64");
  const env = { RESEND_API_KEY: "re_test", LAMP_IDEAS_FROM: "Lamp <ideas@lamp.dev>", LAMP_IDEAS_REPLY_DOMAIN: "reply.lamp.dev", RESEND_WEBHOOK_SECRET: `whsec_${secretKey}` };
  const mails = [];
  let received = "Yes please, and rain too!\n\nOn Tue, Nov 10, 2026 at 9:00 AM Lamp <ideas@lamp.dev> wrote:\n> Alex added your idea";
  const fetcher = async (url, init) => {
    if (String(url).includes("/emails/receiving/")) return Response.json({ text: received });
    mails.push(JSON.parse(init.body));
    return Response.json({});
  };
  const ideas = createIdeasHandler({ store, limited: false, fetcher, env });
  const mailIn = createIdeaMailHandler({ store, fetcher, env });
  const call = (method, query, body) => ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}${query}`, {
    method, headers: { ...(method === "POST" ? {} : { authorization: `Bearer ${secret}` }), "content-type": "application/json" }, ...(body ? { body: JSON.stringify(body) } : {}) }));
  const { n } = await (await call("POST", "", { text: "Bigger waves", email: "Someone@Example.com" })).json();
  await call("DELETE", `&n=${n}&built=1`, { note: "Done, try the harbor" });
  const box = /^idea-([0-9a-f]{20})@reply\.lamp\.dev$/.exec(mails[0].reply_to[0])?.[1];
  assert.ok(box, "replies go to the idea's own mailbox");
  assert.match(mails[0].text, /Done, try the harbor[\s\S]*Reply to this email to answer Alex/);
  assert.match(mails[0].headers["List-Unsubscribe"], new RegExp(`stop=${box}`));

  const deliver = (from, at = Date.now(), key = secretKey, mid = "<reply-1@example.com>") => {
    const body = JSON.stringify({ type: "email.received", data: { email_id: "e1", from, to: [`idea-${box}@reply.lamp.dev`], message_id: mid } });
    const stamp = String(Math.floor(at / 1000));
    const signature = createHmac("sha256", Buffer.from(key, "base64")).update(`msg_1.${stamp}.${body}`).digest("base64");
    return mailIn(new Request("https://lamp.dev/api/idea-mail", { method: "POST", body, headers: { "svix-id": "msg_1", "svix-timestamp": stamp, "svix-signature": `v1,${signature}` } }));
  };
  const listed = async () => (await (await call("GET", "")).json()).ideas;
  assert.equal((await deliver("someone@example.com", Date.now(), Buffer.from("another").toString("base64"))).status, 401, "only what Resend signed");
  assert.equal((await deliver("someone@example.com", Date.now() - 600_000)).status, 401, "nor an old one sent again");
  assert.equal((await deliver("Not Them <other@example.com>")).status, 200);
  assert.deepEqual(await listed(), [], "nothing from another address");
  assert.equal((await deliver("Someone <someone@example.com>")).status, 200);
  assert.equal((await deliver("Someone <someone@example.com>")).status, 200);
  const [waiting] = await listed();
  assert.deepEqual([waiting.n, waiting.status, waiting.waiting, waiting.wantsNews], [n, "in", true, true]);
  assert.deepEqual(waiting.thread.map((one) => [one.by, one.text]), [["maker", "Done, try the harbor"], ["sender", "Yes please, and rain too!"]], "their words, once, without the email they quote");
  assert.ok(!JSON.stringify(waiting).includes(box) && !JSON.stringify(waiting).includes("example.com"), "never the mailbox or the address");

  assert.equal((await (await call("PATCH", `&n=${n}`, { note: "Rain is next" })).json()).notified, true);
  assert.equal(mails[1].subject, `Re: Your idea is in ${share.name}`);
  assert.equal(mails[1].headers["In-Reply-To"], "<reply-1@example.com>");
  assert.deepEqual(await listed(), [], "answered, it's off the list");
  received = "One more thing";
  await deliver("someone@example.com", Date.now(), secretKey, "<reply-2@example.com>");
  assert.deepEqual((await listed())[0].thread.map((one) => one.text), ["Done, try the harbor", "Yes please, and rain too!", "Rain is next", "One more thing"]);
  assert.equal((await call("PATCH", `&n=${n}`)).status, 200);
  assert.deepEqual(await listed(), [], "seen to without a word");

  assert.equal((await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=${n}&stop=${box}`))).status, 200);
  assert.equal((await (await call("PATCH", `&n=${n}`, { note: "Anyone there?" })).json()).notified, false, "no more emails once they stop them");
  assert.equal(replyWords("Sure\n\n-----Original Message-----\nFrom: Lamp"), "Sure");
  // Two first emails at once go with one mailbox; an outcome given to an answered idea takes it off the list.
  const other = (await (await call("POST", "", { text: "Night races", email: "someone@example.com" })).json()).n;
  const before = mails.length;
  await Promise.all([call("PATCH", `&n=${other}`, { note: "Do you mean a full race?" }), call("PATCH", `&n=${other}`, { note: "Or just a lap?" })]);
  assert.deepEqual(new Set(mails.slice(before).map((mail) => mail.reply_to[0])).size, 1);
  const otherBox = /^idea-([0-9a-f]{20})@/.exec(mails.at(-1).reply_to[0])[1];
  const answerOther = () => {
    const body = JSON.stringify({ type: "email.received", data: { email_id: "e2", from: "someone@example.com", to: [`idea-${otherBox}@reply.lamp.dev`], message_id: "<reply-3@example.com>" } });
    const stamp = String(Math.floor(Date.now() / 1000));
    const signature = createHmac("sha256", Buffer.from(secretKey, "base64")).update(`msg_2.${stamp}.${body}`).digest("base64");
    return mailIn(new Request("https://lamp.dev/api/idea-mail", { method: "POST", body, headers: { "svix-id": "msg_2", "svix-timestamp": stamp, "svix-signature": `v1,${signature}` } }));
  };
  await answerOther();
  assert.equal((await listed()).find((one) => one.n === other)?.waiting, true);
  await call("DELETE", `&n=${other}&built=1`);
  assert.deepEqual(await listed(), [], "given its outcome, it's seen to");
  const earlier = (await (await call("GET", "&earlier=1")).json()).ideas;
  assert.deepEqual(earlier.map((one) => one.n), [other, n], "those seen to, the latest word first");
  assert.ok(earlier.every((one) => one.thread && !("mailbox" in one) && !("email" in one)));
  // A note kept on its own, from before threads, is the start of one, and stays so when the maker writes again.
  const legacy = await store.addIdea(id, { text: "A lighthouse", at: "2026-11-10T10:00:00.000Z", token: "x".repeat(16), status: "dismissed", done: "2026-11-10T12:00:00.000Z", note: "We have one already" });
  const legacyThread = async () => (await (await call("GET", "&earlier=1")).json()).ideas.find((one) => one.n === legacy).thread.map((one) => one.text);
  assert.deepEqual(await legacyThread(), ["We have one already"]);
  await call("PATCH", `&n=${legacy}`, { note: "It's by the docks" });
  assert.deepEqual(await legacyThread(), ["We have one already", "It's by the docks"]);
});

test("the maker can have ideas and replies at their own address, and answer them from it", async () => {
  const { createHmac } = await import("node:crypto");
  const store = memoryStore();
  const { id, secret } = await (await send(createShareHandler({ store, limited: false }), "POST", { ...share, by: "Alex" })).json();
  const secretKey = Buffer.from("a webhook's own secret").toString("base64");
  const env = { RESEND_API_KEY: "re_test", LAMP_IDEAS_FROM: "Lamp <ideas@lamp.dev>", LAMP_IDEAS_REPLY_DOMAIN: "reply.lamp.dev", RESEND_WEBHOOK_SECRET: `whsec_${secretKey}` };
  const mails = [];
  let received = "";
  const fetcher = async (url, init) => {
    if (String(url).includes("/emails/receiving/")) return Response.json({ text: received });
    mails.push(JSON.parse(init.body));
    return Response.json({});
  };
  const ideas = createIdeasHandler({ store, limited: false, fetcher, env });
  const mailIn = createIdeaMailHandler({ store, fetcher, env });
  const call = (method, query, body, auth = true) => ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}${query}`, {
    method, headers: { ...(auth ? { authorization: `Bearer ${secret}` } : {}), "content-type": "application/json" }, ...(body ? { body: JSON.stringify(body) } : {}) }));
  const deliver = (from, to, mid) => {
    const body = JSON.stringify({ type: "email.received", data: { email_id: "e1", from, to: [to], message_id: mid } });
    const stamp = String(Math.floor(Date.now() / 1000));
    const signature = createHmac("sha256", Buffer.from(secretKey, "base64")).update(`m.${stamp}.${body}`).digest("base64");
    return mailIn(new Request("https://lamp.dev/api/idea-mail", { method: "POST", body, headers: { "svix-id": "m", "svix-timestamp": stamp, "svix-signature": `v1,${signature}` } }));
  };

  assert.equal((await call("PUT", "&maker=1", { email: "alex@example.com" }, false)).status, 404, "only with the link's secret");
  assert.equal((await call("PUT", "&maker=1", { email: "not an address" })).status, 400);
  assert.deepEqual(await (await call("PUT", "&maker=1", { email: "Alex@Example.com" })).json(), { email: "Alex@Example.com", confirmed: false, sent: true });
  const key = /confirm=([0-9a-f]{20})/.exec(mails[0].text)[1];
  await call("POST", "", { text: "Before it's confirmed" }, false);
  assert.equal(mails.length, 1, "nothing goes to an address until it's confirmed");
  await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&confirm=${"0".repeat(20)}`));
  assert.equal((await (await call("GET", "&maker=1")).json()).confirmed, false, "only with its own key");
  await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&confirm=${key}`));
  assert.deepEqual(await (await call("GET", "&maker=1")).json(), { email: "Alex@Example.com", confirmed: true });

  const { n } = await (await call("POST", "", { text: "Bigger waves", email: "someone@example.com" }, false)).json();
  const toMaker = mails.at(-1);
  assert.deepEqual(toMaker.to, ["Alex@Example.com"]);
  assert.match(toMaker.subject, /^Idea for .+: Bigger waves$/);
  const makerBox = /^idea-([0-9a-f]{20})@/.exec(toMaker.reply_to[0])[1];

  // The maker answers from their email: on the thread as theirs, and on to the sender.
  received = "Coming this week!\n\nOn Tue, Lamp wrote:\n> Someone playing";
  assert.equal((await deliver("Someone Else <someone@example.com>", `idea-${makerBox}@reply.lamp.dev`, "<m1@example.com>")).status, 200);
  assert.equal(mails.at(-1), toMaker, "only from the maker's own address");
  await deliver("alex@example.com", `idea-${makerBox}@reply.lamp.dev`, "<m1@example.com>");
  await deliver("alex@example.com", `idea-${makerBox}@reply.lamp.dev`, "<m1@example.com>");
  const toSender = mails.at(-1);
  assert.deepEqual([toSender.to, mails.length], [["someone@example.com"], 3], "once, however often it comes");
  assert.match(toSender.text, /Coming this week!/);
  const senderBox = /^idea-([0-9a-f]{20})@/.exec(toSender.reply_to[0])[1];

  // The sender answers: on the thread, and to the maker in that idea's conversation.
  received = "Yay";
  await deliver("someone@example.com", `idea-${senderBox}@reply.lamp.dev`, "<s1@example.com>");
  assert.deepEqual(mails.at(-1).to, ["Alex@Example.com"]);
  assert.equal(mails.at(-1).headers["In-Reply-To"], toMaker.headers["Message-ID"]);
  const idea = (await (await call("GET", "")).json()).ideas.find((one) => one.n === n);
  assert.deepEqual(idea.thread.map((one) => [one.by, one.text]), [["maker", "Coming this week!"], ["sender", "Yay"]]);
  assert.ok(!JSON.stringify(idea).includes(makerBox));

  // The stop link in the maker's emails lets the address go.
  const stop = /stopmaker=([0-9a-f]{20})/.exec(toMaker.text)[1];
  await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&stopmaker=${stop}`, { method: "POST" }));
  assert.deepEqual(await (await call("GET", "&maker=1")).json(), { email: null, confirmed: false });
  const before = mails.length;
  await call("POST", "", { text: "Fireworks" }, false);
  assert.equal(mails.length, before);
});

test("a link's questions go to its page, and only as questions within the limits", async () => {
  const store = memoryStore();
  const handler = createShareHandler({ store, limited: false });
  const asks = ["Found a bug?", "Something in town we're missing?"];
  const { id } = await (await send(handler, "POST", { ...share, asks })).json();
  const page = await (await createPageHandler({ store, template: async () => "<html><head></head><body></body></html>" })(new Request(`https://lamp.dev/api/wish-page?id=${id}`))).text();
  assert.match(page, /"asks":\["Found a bug\?","Something in town we're missing\?"\]/);
  assert.equal((await send(handler, "POST", { ...share, asks: ["a", "b", "c", "d"] })).status, 400, "three at most");
  assert.equal((await send(handler, "POST", { ...share, asks: ["x".repeat(81)] })).status, 400);
});

test("ideas reach the link's maker, and only the maker reads them", async () => {
  const store = memoryStore();
  const { id, secret } = await (await send(createShareHandler({ store, limited: false }), "POST", share)).json();
  const ideas = createIdeasHandler({ store, limited: false });
  const post = (body, at = id) => ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${at}`, {
    method: "POST", headers: { "content-type": "application/json", origin: "https://lamp.dev" }, body: JSON.stringify(body),
  }));
  const list = (key = secret) => ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}`, { headers: { authorization: `Bearer ${key}` } }));

  assert.equal((await post({ text: "Add a night mode" })).status, 201);
  assert.equal((await post({ text: "Bigger waves", email: "not an address" })).status, 400);
  const sent = await (await post({ text: "Bigger waves", email: "someone@example.com" })).json();
  assert.equal(sent.n, 2);
  assert.equal((await post({ text: "  " })).status, 400, "words required");
  assert.equal((await post({ text: "x".repeat(1001) })).status, 400);
  assert.equal((await post({ text: "hi" }, "zzzzzzzzzz")).status, 404, "only for a link that's out");
  assert.equal((await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}`, {
    method: "POST", headers: { "content-type": "application/json", origin: "https://elsewhere.example" }, body: "{}" }))).status, 403);

  assert.equal((await list("x".repeat(43))).status, 404, "only with the link's secret");
  const kept = (await (await list()).json()).ideas;
  assert.deepEqual(kept.map((idea) => [idea.n, idea.text, idea.wantsNews]), [[1, "Add a night mode", undefined], [2, "Bigger waves", true]]);
  assert.ok(kept.every((idea) => !("email" in idea) && typeof idea.at === "string"), "never the addresses");


  const done = await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=1`, { method: "DELETE", headers: { authorization: `Bearer ${secret}` } }));
  assert.equal(done.status, 200);
  assert.deepEqual((await (await list()).json()).ideas.map((idea) => idea.n), [2]);
  assert.equal((await post({ text: "Night mode" })).status, 201);
  assert.deepEqual((await (await list()).json()).ideas.map((idea) => idea.n), [2, 3], "numbers never come back");

  // Built: the site writes to whoever asked, once, through Resend, and the maker never sees where.
  const mails = [];
  const fetcher = async (url, init) => { mails.push([url, JSON.parse(init.body)]); return new Response("{}", { status: 200 }); };
  const built = createIdeasHandler({ store, limited: false, fetcher, env: { RESEND_API_KEY: "re_test", LAMP_IDEAS_FROM: "Lamp <ideas@lamp.dev>" } });
  const answer = await (await built(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=2&built=1`, { method: "DELETE", headers: { authorization: `Bearer ${secret}`, "content-type": "application/json" }, body: JSON.stringify({ note: "Thanks, the waves are huge now" }) }))).json();
  assert.equal(answer.notified, true);
  assert.equal(mails.length, 1);
  assert.equal(mails[0][0], "https://api.resend.com/emails");
  assert.deepEqual(mails[0][1].to, ["someone@example.com"]);
  assert.match(mails[0][1].text, /Bigger waves[\s\S]*Thanks, the waves are huge now[\s\S]*https:\/\/lamp\.dev\/w\//);
  assert.deepEqual((await (await list()).json()).ideas.map((idea) => idea.n), [3]);
  assert.equal(mails.length, 1);
  // Two at once for one idea: one email.
  const twice = await (await post({ text: "Fireworks at midnight", email: "someone@example.com" })).json();
  const asked = () => built(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=${twice.n}&built=1`, { method: "DELETE", headers: { authorization: `Bearer ${secret}` } }));
  const answers = await Promise.all([asked(), asked()]);
  assert.deepEqual((await Promise.all(answers.map((one) => one.json()))).map((one) => one.notified).sort(), [false, true]);
  assert.equal(mails.length, 2);
  assert.equal(mails[1][1].to[0], "someone@example.com");
  // The sender's browser asks after its own ideas, by number and token, and hears only their outcome.
  const kept1 = await (await post({ text: "A lighthouse on the point" })).json();
  const kept2 = await (await post({ text: "Fog in the mornings" })).json();
  const mine = async (pairs) => (await (await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&mine=${pairs}`))).json()).ideas;
  assert.deepEqual(await mine(`${kept1.n}.${kept1.token},${kept2.n}.${kept2.token}`), [{ n: kept1.n, status: "open" }, { n: kept2.n, status: "open" }]);
  assert.deepEqual(await mine(`${kept1.n}.${"x".repeat(16)}`), [], "only with its token");
  await built(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=${kept1.n}&built=1`, { method: "DELETE", headers: { authorization: `Bearer ${secret}` } }));
  const noted = (note) => built(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=${kept2.n}`, { method: "DELETE", headers: { authorization: `Bearer ${secret}`, "content-type": "application/json" }, body: JSON.stringify({ note }) }));
  assert.equal((await noted("x".repeat(IDEA_LIMITS.note + 1))).status, 400, "a note too long is turned away, the idea left open");
  await noted("We have fog at night already");
  assert.deepEqual((await mine(`${kept1.n}.${kept1.token},${kept2.n}.${kept2.token}`)).map((one) => [one.status, one.note]), [["in", undefined], ["dismissed", "We have fog at night already"]]);
  assert.ok(!(await (await list()).json()).ideas.some((one) => one.n === kept1.n || one.n === kept2.n), "the maker sees only those still open");
  // Dealing with ideas makes room for more: the cap counts those still open.
  const full = memoryStore();
  const { id: fullID, secret: fullSecret } = await (await send(createShareHandler({ store: full, limited: false }), "POST", share)).json();
  const fullIdeas = createIdeasHandler({ store: full, limited: false });
  for (let i = 0; i < IDEA_LIMITS.kept; i++) await full.addIdea(fullID, { text: `idea ${i}`, at: new Date().toISOString() });
  const postFull = () => fullIdeas(new Request(`https://lamp.dev/api/wish-ideas?id=${fullID}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text: "one more" }) }));
  assert.equal((await postFull()).status, 429);
  await fullIdeas(new Request(`https://lamp.dev/api/wish-ideas?id=${fullID}&n=1`, { method: "DELETE", headers: { authorization: `Bearer ${fullSecret}` } }));
  assert.equal((await postFull()).status, 201);
  const quiet = await (await built(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=3&built=1`, { method: "DELETE", headers: { authorization: `Bearer ${secret}` } }))).json();
  assert.equal(quiet.notified, false, "nobody asked");
  assert.equal(mails.length, 2);
  // A picture of the app goes with an idea when the sender keeps it in, and goes once the idea has its outcome.
  const dot = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  assert.equal((await post({ text: "Look here", picture: "not a picture" })).status, 400);
  const shot = await (await post({ text: "Look here", picture: dot })).json();
  assert.equal((await (await list()).json()).ideas.find((one) => one.n === shot.n).picture, `data:image/png;base64,${dot}`);
  await ideas(new Request(`https://lamp.dev/api/wish-ideas?id=${id}&n=${shot.n}`, { method: "DELETE", headers: { authorization: `Bearer ${secret}` } }));
  assert.equal((await store.ideas(id)).find((one) => one.n === shot.n).picture, undefined);
});
