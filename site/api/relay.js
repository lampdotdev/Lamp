import { createRelayHandler } from "../lib/relay.js";
import { relayBlobs, relayRedis } from "../lib/relay-store.js";
import { cloudStore } from "../lib/shared-wishes.js";

// The relay's API (RELAY.md): the page's calls and the helper's, by `op`. Without its own Redis and Blob store set
// up, it answers 503 and the page says lamp.dev isn't answering.
let handler = null;
async function relay(request) {
  try { handler ??= createRelayHandler({ db: relayRedis(process.env), blobs: relayBlobs(process.env), wishes: cloudStore(process.env) }); }
  catch { return Response.json({ error: "service_unavailable" }, { status: 503, headers: { "Cache-Control": "no-store" } }); }
  return handler(request);
}
export const GET = relay;
export const POST = relay;
