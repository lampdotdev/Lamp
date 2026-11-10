import { timingSafeEqual } from "node:crypto";
import { cleanupRelay } from "../lib/relay.js";
import { relayBlobs, relayRedis } from "../lib/relay-store.js";

// Run by Vercel's cron (vercel.json), which sends the project's CRON_SECRET: removes the Blob files of rooms that are
// gone, and files no version of a room points at, since Redis lets a room run out but Blob keeps its files.
export async function GET(request) {
  const secret = process.env.CRON_SECRET;
  const given = Buffer.from(request.headers.get("authorization") ?? "");
  const wanted = Buffer.from(`Bearer ${secret}`);
  if (!secret || given.length !== wanted.length || !timingSafeEqual(given, wanted)) return new Response(null, { status: 401 });
  try { return Response.json(await cleanupRelay({ db: relayRedis(process.env), blobs: relayBlobs(process.env) })); }
  catch (error) { console.error("relay cleanup:", error?.name, error?.message); return new Response(null, { status: 503 }); }
}
