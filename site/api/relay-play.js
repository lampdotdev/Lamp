import { createRelayPlayHandler } from "../lib/relay.js";
import { relayBlobs, relayRedis } from "../lib/relay-store.js";
import { cloudStore } from "../lib/shared-wishes.js";

// A room's game, on the room's own host (`r-<room>.play.lamp.dev`).
let handler = null;
async function play(request) {
  try { handler ??= createRelayPlayHandler({ db: relayRedis(process.env), blobs: relayBlobs(process.env), wishes: cloudStore(process.env) }); }
  catch { return new Response(null, { status: 503 }); }
  return handler(request);
}
export const GET = play;
export const HEAD = play;
