import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { deflateSync, crc32 } from "node:zlib";
import { createShareHandler, createFileHandler, memoryStore, readShare, imageInfo, isID, isWishFile, LIMITS, FILE_LIMITS } from "../lib/shared-wishes.js";
import { createPageHandler } from "../lib/shared-wish-page.js";
import { createCardHandler } from "../lib/wish-card.js";

/** A plain PNG of one colour, as Lamp's pictures are PNGs or JPEGs. */
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
  assert.equal(url, `https://lamp.dev/w/${id}`);
  assert.ok(!JSON.stringify([...store.records.values()]).includes(secret), "only the secret's hash is kept");

  assert.equal((await send(handler, "PUT", { ...share, name: "Thief" }, { id, secret: "x".repeat(43) })).status, 404);
  assert.equal((await send(handler, "PUT", { ...share, name: "Plant Friend", picture: null }, { id, secret })).status, 200);
  assert.equal(store.records.get(id).name, "Plant Friend");
  assert.equal(store.records.get(id).picture, null);

  assert.equal((await send(handler, "DELETE", undefined, { id })).status, 404);
  assert.equal((await send(handler, "DELETE", undefined, { id, secret })).status, 204);
  assert.equal(store.records.has(id), false);
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
  assert.equal((await send(handler, "GET")).status, 405);
});

test("without its store or quota it answers unavailable rather than sharing", async () => {
  const handler = createShareHandler({ env: {} });
  assert.equal((await send(handler, "POST", share)).status, 503);
});

test("the page is the ideas page with the shared wish's card, its words escaped, and its own preview", async () => {
  const store = memoryStore();
  const { id } = await (await send(createShareHandler({ store, limited: false }), "POST", share)).json();
  const ideas = `<!DOCTYPE html><html><head><title>Ideas · Lamp</title><meta name="description" content="Ideas"><link rel="canonical" href="https://lamp.dev/ideas"><meta property="og:title" content="Ideas · Lamp"><meta name="twitter:card" content="summary"></head><body><dialog data-wish></dialog></body></html>`;
  const response = await createPageHandler({ store, template: async () => ideas })(new Request(`https://lamp.dev/api/wish-page?id=${id}`));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes("<dialog data-wish>"), "the ideas page's card");
  assert.ok(!html.includes("Ideas · Lamp") && !html.includes('content="summary"'), "the ideas page's own preview is gone");
  assert.ok(html.includes(`<meta property="og:image" content="https://lamp.dev/w/${id}/card.png?v=`));
  assert.ok(html.includes(`<meta name="twitter:card" content="summary_large_image">`));
  const card = JSON.parse(/<script type="application\/json" id="shared-wish">(.*?)<\/script>/.exec(html)[1]);
  assert.equal(card.wish, store.records.get(id).words);
  assert.equal(card.about, "Reminds me when each plant needs water.");
  assert.ok(!html.includes("<watered>"), "nothing the sharer wrote can close the script");
  assert.equal(response.headers.get("x-robots-tag"), "noindex");

  const gone = await createPageHandler({ store, template: async () => ideas })(new Request("https://lamp.dev/api/wish-page?id=2345678922"));
  assert.equal(gone.status, 404);
});

test("the ideas page the function serves is the one the site builds", () => {
  const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8"));
  assert.equal(config.functions["api/wish-page.js"].includeFiles, "dist/ideas/index.html");
  const dialog = readFileSync(new URL("../src/components/WishDialog.astro", import.meta.url), "utf8");
  assert.ok(dialog.includes('getElementById("shared-wish")'));
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

/** A zip holding one stored file, as Lamp's shared files are zips with lamp-app.json at their root. */
function zip(name, data) {
  const nameBytes = Buffer.from(name), local = Buffer.alloc(30), central = Buffer.alloc(46), end = Buffer.alloc(22);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt32LE(crc32(data), 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(nameBytes.length, 26);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt32LE(crc32(data), 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(nameBytes.length, 28);
  const offset = local.length + nameBytes.length + data.length;
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10); end.writeUInt32LE(central.length + nameBytes.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([local, nameBytes, data, central, nameBytes, end]);
}

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

  // A word-only update keeps the file; taking the link down takes it too.
  assert.equal((await send(handler, "PUT", { ...share, name: "Plant Friend" }, { id, secret })).status, 200);
  assert.ok(store.records.get(id).file);
  assert.equal((await part(0, 1, zip("other.txt", Buffer.from("x")))).status, 204);
  assert.equal((await finish()).status, 400, "only a file Lamp made");
  assert.equal((await send(handler, "DELETE", undefined, { id, secret })).status, 204);
  assert.equal(store.records.has(id), false);
});

test("the site and Lamp agree on the limits", () => {
  const swift = readFileSync(new URL("../../Sources/Lamp/WishLink.swift", import.meta.url), "utf8");
  assert.ok(swift.includes(`static let filePart = ${FILE_LIMITS.part.toLocaleString("en").replaceAll(",", "_")}`), "filePart");
  assert.ok(swift.includes(`static let fileTotal = ${FILE_LIMITS.total.toLocaleString("en").replaceAll(",", "_")}`), "fileTotal");
  for (const [name, value] of Object.entries({ name: LIMITS.name, line: LIMITS.line, words: LIMITS.words })) {
    assert.ok(swift.includes(`static let ${name} = ${value}`), name);
  }
});
