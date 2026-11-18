// Sending an app's maker an idea that can carry a change: the sender's own copy of the app, shared privately on
// lamp.dev (seen only by the maker, through the idea) and named by the idea with the version of the maker's app it
// starts from. One way for lamp's `send` and for Lamp's app's Send to… alike (`ideaSend` in calls.mjs): the copy's
// secret and the idea's number are whoever sent it's to keep, so sending again moves the same idea on.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { CHANGE_LIMITS } from "../site/lib/shared-wishes.js";
import { publishLink, sendFile, sendIdea } from "./link.mjs";
import { Problem, stateOf } from "./state.mjs";

const megabytes = (bytes) => `${(bytes / 1_000_000).toFixed(bytes < 10_000_000 ? 1 : 0)} MB`;

/**
 * Sends `text` (and `picture`, PNG or JPEG bytes) to the maker of the link `source`. With `change`, the app goes too:
 * `bytes`, its shared file; `base`, the version of the maker's file it starts from; `body`, the words a copy's link
 * takes (its name and words, a line and who it's by if there are any). The copy is always private: only the maker sees it. `earlier` is what the last send kept (`{ copy: { id, secret }, n }`): the same copy is
 * changed, and the same idea moved on to it, rather than new ones made. A change needs the account's key.
 * Answers what to keep for the next send: the copy (null without a change), the idea's number, and the copy's version.
 * `madeCopy` is told the copy as soon as it's up, before its file and the idea go, so a send that fails after it keeps
 * the copy to send to again rather than leaving it on the site with its secret lost.
 */
export async function sendToMaker({ site, source, text, picture = null, change = null, earlier = null, account, said = () => {}, madeCopy = () => {} }) {
  if (!change) return { copy: null, ...(await sendIdea({ site, id: source, text, picture, account })) };
  if (!account) throw Object.assign(new Problem("sending your changes needs a lamp.dev username: lamp account makes one"), { status: 401 });
  if (change.bytes.length > CHANGE_LIMITS.file) throw new Problem(`the app is ${megabytes(change.bytes.length)}, and the site takes ${megabytes(CHANGE_LIMITS.file)} with an idea`);
  said("Putting your copy up for the maker…");
  const body = { ...change.body, words: change.body.words || text, from: source, private: true };
  const copy = await publishLink({ site, body, earlier: earlier?.copy ?? null, account });
  if (copy.id !== earlier?.copy?.id) madeCopy(copy);
  const version = await sendFile({ site, link: copy, bytes: change.bytes, said });
  const sent = { copy: copy.id, base: change.base };
  // The same idea, if the last send made it with this copy; one the maker's link no longer has is sent anew.
  if (earlier?.n && earlier.copy?.id === copy.id) {
    try { return { copy, ...(await sendIdea({ site, id: source, text, picture, change: sent, n: earlier.n, account })), version }; }
    catch (error) { if (error.status !== 404) throw error; }
  }
  return { copy, ...(await sendIdea({ site, id: source, text, picture, change: sent, account })), version };
}

// What lamp keeps for a folder's sends, by the site and the maker's link: the copy (its secret too, so it stays out of
// the folder) and the idea's number.
const sentFileOf = (folder) => join(stateOf(folder), "sent.json");
export function sentFor(folder, site, source) {
  try { return JSON.parse(readFileSync(sentFileOf(folder), "utf8"))[`${site} ${source}`] ?? null; } catch { return null; }
}
export function keepSent(folder, site, source, kept) {
  let all = {};
  try { all = JSON.parse(readFileSync(sentFileOf(folder), "utf8")); } catch {}
  all[`${site} ${source}`] = kept;
  mkdirSync(dirname(sentFileOf(folder)), { recursive: true });
  writeFileSync(sentFileOf(folder), JSON.stringify(all, null, 2), { mode: 0o600 });
}

// The version of a link's file a folder was made from, as `lamp play` unpacked it: where a change sent from it starts.
const playedFromOf = (folder) => join(stateOf(folder), "played-from.json");
export function keepPlayedFrom(folder, id, version) {
  mkdirSync(dirname(playedFromOf(folder)), { recursive: true });
  writeFileSync(playedFromOf(folder), JSON.stringify({ id, version }));
}
export function playedFrom(folder, id) {
  if (!existsSync(playedFromOf(folder))) return 0;
  try { const kept = JSON.parse(readFileSync(playedFromOf(folder), "utf8")); return kept.id === id && Number.isInteger(kept.version) ? kept.version : 0; } catch { return 0; }
}
