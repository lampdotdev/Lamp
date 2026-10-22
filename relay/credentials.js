// The relay's credentials: short signed tokens, each for one kind of holder in one session, that the relay checks
// with its own secret and keeps no record of. None of them is Lamp's token for an app's AI, and none opens anything
// but its session.
//
//   host        the TV app (or Lamp, for the preview) that a session is for: opens the session's socket as its host,
//               puts the phone page there and asks for join links. Lasts as long as a session may.
//   join        what a phone's link carries (in the part of the address after #, which a browser never sends): good
//               for a few minutes, for a phone to take a player's place.
//   controller  given to a phone once it has joined: its player in that session, for a couple of minutes, renewed
//               over the socket while it stays, so a phone that drops off can come back as the same player.

import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

export const lifetimes = { host: 12 * 60 * 60, join: 15 * 60, controller: 2 * 60 };

const encode = (buffer) => Buffer.from(buffer).toString('base64url');

export function newSecret() {
  return randomBytes(32);
}

export function newSessionId() {
  // Lower-case letters and digits only: the id is a subdomain of the page's address.
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return Array.from(randomBytes(20), (byte) => alphabet[byte % alphabet.length]).join('');
}

export function issue(secret, { kind, session, player, now = Date.now() }) {
  if (!lifetimes[kind]) throw new Error(`no such kind of credential: ${kind}`);
  const payload = { k: kind, s: session, e: Math.floor(now / 1000) + lifetimes[kind], n: encode(randomBytes(9)) };
  if (player !== undefined) payload.p = player;
  const body = encode(JSON.stringify(payload));
  return `${body}.${encode(createHmac('sha256', secret).update(body).digest())}`;
}

// The credential's contents when it was made with this secret, is of one of the kinds asked for, is for this session
// and hasn't run out; null otherwise, whatever is wrong with it.
export function check(secret, token, { kinds, session, now = Date.now() }) {
  if (typeof token !== 'string' || token.length > 1024) return null;
  const [body, signature, extra] = token.split('.');
  if (!body || !signature || extra !== undefined) return null;
  const expected = createHmac('sha256', secret).update(body).digest();
  let given;
  try { given = Buffer.from(signature, 'base64url'); } catch { return null; }
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  let payload;
  try { payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); } catch { return null; }
  if (!payload || !kinds.includes(payload.k) || payload.s !== session) return null;
  if (typeof payload.e !== 'number' || payload.e * 1000 <= now) return null;
  return payload;
}
