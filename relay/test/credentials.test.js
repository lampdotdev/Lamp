// The relay's credentials: each holder gets into its own session as what it is, for as long as it's given, and
// nothing else gets in.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { issue, check, newSecret, newSessionId, lifetimes } from '../credentials.js';

const secret = newSecret();
const session = newSessionId();
const other = newSessionId();

test('a credential gets its holder into its own session as what it is', () => {
  for (const kind of ['host', 'join', 'controller']) {
    const token = issue(secret, { kind, session, player: kind === 'controller' ? 3 : undefined });
    const payload = check(secret, token, { kinds: [kind], session });
    assert.ok(payload, kind);
    assert.equal(payload.k, kind);
    assert.equal(payload.s, session);
  }
  assert.equal(check(secret, issue(secret, { kind: 'controller', session, player: 3 }), { kinds: ['controller'], session }).p, 3);
});

test('a phone\'s credential is never a host\'s, and a host\'s is never a phone\'s', () => {
  const join = issue(secret, { kind: 'join', session });
  const controller = issue(secret, { kind: 'controller', session, player: 1 });
  const host = issue(secret, { kind: 'host', session });
  assert.equal(check(secret, join, { kinds: ['host'], session }), null);
  assert.equal(check(secret, controller, { kinds: ['host'], session }), null);
  assert.equal(check(secret, host, { kinds: ['join', 'controller'], session }), null);
});

test('a credential opens no other session', () => {
  for (const kind of ['host', 'join', 'controller']) {
    assert.equal(check(secret, issue(secret, { kind, session }), { kinds: [kind], session: other }), null, kind);
  }
});

test('a phone\'s credentials run out in minutes; a host\'s in hours', () => {
  const now = Date.now();
  const join = issue(secret, { kind: 'join', session, now });
  const controller = issue(secret, { kind: 'controller', session, player: 1, now });
  assert.ok(check(secret, join, { kinds: ['join'], session, now: now + 14 * 60_000 }));
  assert.equal(check(secret, join, { kinds: ['join'], session, now: now + 16 * 60_000 }), null);
  assert.ok(check(secret, controller, { kinds: ['controller'], session, now: now + 60_000 }));
  assert.equal(check(secret, controller, { kinds: ['controller'], session, now: now + 3 * 60_000 }), null);
  assert.ok(lifetimes.join <= 15 * 60 && lifetimes.controller <= 2 * 60);
});

test('a changed, cut, borrowed or foreign credential gets nowhere', () => {
  const token = issue(secret, { kind: 'controller', session, player: 1 });
  const [body, signature] = token.split('.');
  const asHost = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(body, 'base64url')), k: 'host' })).toString('base64url');
  assert.equal(check(secret, `${asHost}.${signature}`, { kinds: ['host'], session }), null, 'kind rewritten');
  const flipped = signature.slice(0, -2) + (signature.at(-2) === 'A' ? 'B' : 'A') + signature.at(-1);
  assert.equal(check(secret, `${body}.${flipped}`, { kinds: ['controller'], session }), null, 'signature changed');
  assert.equal(check(secret, body, { kinds: ['controller'], session }), null, 'no signature');
  assert.equal(check(secret, `${token}.x`, { kinds: ['controller'], session }), null, 'extra part');
  assert.equal(check(newSecret(), token, { kinds: ['controller'], session }), null, 'another relay\'s secret');
  assert.equal(check(secret, undefined, { kinds: ['controller'], session }), null, 'none');
  assert.equal(check(secret, 'x'.repeat(5000), { kinds: ['controller'], session }), null, 'too long');
});

test('every credential is new, even for the same holder at the same moment', () => {
  const now = Date.now();
  assert.notEqual(issue(secret, { kind: 'join', session, now }), issue(secret, { kind: 'join', session, now }));
});
