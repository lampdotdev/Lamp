import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { wishHTML, wishLink, copyWish, askFrom, withAsk, exactWishLink, remixFrom, remixLink, WISH_MARK, WISH_LIMIT, ASK_LIMIT } from "../lib/wish.js";

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

test("a request from an app's remix panel is read off the link and put after the wish", () => {
  assert.equal(askFrom("?ask=Add%20a%20weekly%20view"), "Add a weekly view");
  assert.equal(askFrom("?other=1"), null);
  assert.equal(askFrom("?ask=%20%20"), null);
  assert.equal(askFrom(`?ask=${"x".repeat(ASK_LIMIT + 20)}`).length, ASK_LIMIT);
  assert.equal(withAsk(wish, "Add a weekly view"), `${wish}\n\nThen: Add a weekly view`);
  assert.equal(withAsk(wish, ""), wish);
  assert.equal(withAsk("", "Add a weekly view"), "Add a weekly view");
  assert.ok(withAsk("w".repeat(WISH_LIMIT), "more").length <= WISH_LIMIT);
});

test("the site and the panel agree on how much a request carries", () => {
  const swift = readFileSync(new URL("../../Sources/LampSidebarKit/RemixPanel.swift", import.meta.url), "utf8");
  assert.ok(swift.includes(`public static let askLimit = ${ASK_LIMIT}`));
});

test("the exact wish's link names its file and carries the request", () => {
  const link = exactWishLink("https://files.example/w/abc.lampapp", " Add a weekly view ");
  assert.ok(link.startsWith("lamp://wish?"));
  const params = new URL(link).searchParams;
  assert.equal(params.get("file"), "https://files.example/w/abc.lampapp");
  assert.equal(params.get("text"), "Add a weekly view");
  assert.equal(exactWishLink("", "Add a weekly view"), null);
  assert.equal(exactWishLink("https://files.example/w/abc.lampapp", "  "), null);
});

test("a remix names only a starter's id or a github.com repository, and Lamp's link and mark carry it", () => {
  assert.deepEqual(remixFrom("?starter=newyork&ask=Snow"), { starter: "newyork" });
  assert.deepEqual(remixFrom("?repo=https%3A%2F%2Fgithub.com%2Flampdotdev%2Fnewyork.git&commit=B95D5012397FA3FA345505F428F1189271218753"),
    { repo: "https://github.com/lampdotdev/newyork", owner: "lampdotdev", name: "newyork", commit: "b95d5012397fa3fa345505f428f1189271218753" });
  for (const bad of ["?starter=..%2Fetc", "?starter=New%20York", "?starter=a&repo=https%3A%2F%2Fgithub.com%2Fa%2Fb",
    "?repo=http%3A%2F%2Fgithub.com%2Fa%2Fb", "?repo=https%3A%2F%2Fgithub.com.evil%2Fa%2Fb", "?repo=https%3A%2F%2Fgithub.com%2Fa%2Fb%2Ftree%2Fmain",
    "?repo=https%3A%2F%2Fgithub.com%2Fa%2Fb&commit=--upload-pack", "?repo=https%3A%2F%2Fgithub.com%2Fa%2Fb&commit=abc1234", "?ask=x"]) {
    assert.equal(remixFrom(bad), null, bad);
  }
  assert.equal(remixLink({ starter: "newyork" }, "Snow + ice"), "lamp://wish?starter=newyork&text=Snow%20%2B%20ice");
  const link = new URL(remixLink({ starter: "newyork" }, " Make it snow "));
  assert.equal(link.protocol, "lamp:");
  assert.equal(link.searchParams.get("starter"), "newyork");
  assert.equal(link.searchParams.get("text"), "Make it snow");
  assert.equal(new URL(remixLink({ repo: "https://github.com/a/b", commit: "abc1234" }, "")).searchParams.get("text"), null);
  assert.match(wishHTML("Snow & ice", { repo: "https://github.com/a/b", commit: "abc1234" }),
    /^<span data-lamp-wish="repo=https%3A%2F%2Fgithub.com%2Fa%2Fb&amp;commit=abc1234" [^>]*>Snow &amp; ice<\/span>$/);
});
