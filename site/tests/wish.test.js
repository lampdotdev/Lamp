import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { wishHTML, wishLink, copyWish, starterLink, WISH_MARK, WISH_LIMIT, STARTER_MARK } from "../lib/wish.js";

const wish = "A Mac app that sorts my files & asks <first>.\nNothing moves until I say \"yes\".";

test("the copied wish carries Lamp's mark around the same words", () => {
  const html = wishHTML(wish);
  assert.match(html, new RegExp(`^<span ${WISH_MARK}="1"`));
  assert.ok(html.includes("sorts my files &amp; asks &lt;first&gt;.\nNothing moves until I say &quot;yes&quot;."));
});

test("the site and Lamp agree on the mark and the limit", () => {
  const swift = readFileSync(new URL("../../Sources/Lamp/Wish.swift", import.meta.url), "utf8");
  assert.ok(swift.includes(`static let mark = "${WISH_MARK}"`));
  assert.ok(swift.includes(`static let limit = ${WISH_LIMIT}`));
  assert.ok(swift.includes(`static let starterMark = "${STARTER_MARK}"`));
  const starters = readFileSync(new URL("../../Sources/Lamp/Starters.swift", import.meta.url), "utf8");
  const link = new URL(starterLink("Wedding Words"));
  assert.ok(starters.includes(`url.host?.lowercased() == "${link.host}"`));
  assert.ok(starters.includes(`$0.name == "${[...link.searchParams.keys()][0]}"`));
  assert.equal(link.searchParams.get("name"), "Wedding Words");
});

test("the link holds the whole wish, and there is none for an empty one", () => {
  const link = wishLink(`  ${wish}  `);
  assert.ok(link.startsWith("lamp://wish?text="));
  assert.equal(new URL(link).searchParams.get("text"), wish);
  assert.equal(wishLink("   "), null);
  assert.equal(new URL(wishLink("x".repeat(WISH_LIMIT + 50))).searchParams.get("text").length, WISH_LIMIT);
});

test("copying writes the words and the marked form together", async () => {
  const written = [];
  class Item { constructor(forms) { this.forms = forms; } }
  const clipboard = { write: async (items) => { written.push(...items); }, writeText: async () => assert.fail("not needed") };
  assert.equal(await copyWish(wish, { clipboard, Item }), "marked");
  assert.equal(await written[0].forms["text/plain"].text(), wish);
  assert.equal(await written[0].forms["text/html"].text(), wishHTML(wish));
});

test("a browser that can't copy the marked form still copies the words, and says so", async () => {
  let plain = null;
  const refusing = { write: async () => { throw new Error("no"); }, writeText: async (t) => { plain = t; } };
  assert.equal(await copyWish(wish, { clipboard: refusing, Item: class {} }), "plain");
  assert.equal(plain, wish);
  assert.equal(await copyWish(wish, { clipboard: { writeText: async (t) => { plain = t; } }, Item: undefined }), "plain");
  assert.equal(await copyWish(wish, { clipboard: { writeText: async () => { throw new Error("no"); } }, Item: undefined }), "none");
  assert.equal(await copyWish(wish, { clipboard: undefined }), "none");
});
