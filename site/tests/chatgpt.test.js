import { test } from "node:test";
import assert from "node:assert/strict";
import { SETUP_PROMPT, CODEX_LINK } from "../src/lib/chatgpt.ts";

// The link has to hand ChatGPT the very words the copy button copies, line breaks and all, read back as a URL is.
test("the ChatGPT link carries the setup prompt exactly", () => {
  const link = new URL(CODEX_LINK);
  assert.equal(link.protocol, "codex:");
  assert.equal(link.host + link.pathname, "new");
  assert.equal(link.searchParams.get("prompt"), SETUP_PROMPT);
});
