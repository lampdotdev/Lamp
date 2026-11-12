// A maker's account and the links that go under it (lamp.dev/<username>/<app>), against the site's own handlers with
// the store in memory and Resend stood in for.

import { test } from "node:test";
import assert from "node:assert/strict";
import { createAccountHandler, isUsername } from "../lib/accounts.js";
import { createShareHandler, memoryStore } from "../lib/shared-wishes.js";
import { createPageHandler } from "../lib/shared-wish-page.js";

const env = { RESEND_API_KEY: "test", LAMP_IDEAS_FROM: "Lamp <ideas@lamp.dev>" };

test("an account is a username confirmed by email, and links shared with its key go under it", async () => {
  const store = memoryStore(), mail = [];
  const fetcher = async (url, request) => { mail.push(JSON.parse(request.body)); return new Response("{}", { status: 200 }); };
  const accounts = createAccountHandler({ env, fetcher, store, limited: false });
  const wishes = createShareHandler({ store, limited: false });
  const page = createPageHandler({ store, template: async () => "<html><head></head><body></body></html>" });
  const ask = (body) => accounts(new Request("https://lamp.dev/api/accounts", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }));
  const confirm = () => accounts(new Request(/https:\S+confirm=[0-9a-f]+/.exec(mail.at(-1).text)[0]));
  const share = (body, { key, id, secret } = {}) => wishes(new Request(`https://lamp.dev/api/wishes${id ? `?id=${id}` : ""}`, { method: id ? "PUT" : "POST",
    headers: { "content-type": "application/json", ...(key ? { "x-lamp-account": key } : {}), ...(secret ? { authorization: `Bearer ${secret}` } : {}) }, body: JSON.stringify(body) }));
  const words = { name: "Bricks", line: "Build with bricks.", words: "A brick builder." };

  assert.deepEqual(["matt-rubens", "a1", "w", "api", "-x", "ab--c", "A"].map(isUsername), [true, true, false, false, false, false, false]);
  assert.equal((await ask({ username: "w", email: "matt@example.com" })).status, 400, "the site's own words aren't usernames");

  // Asked: a key now, the email with the link to confirm it, and no account until it's opened.
  const asked = await (await ask({ username: "Matt-Rubens", email: "matt@example.com" })).json();
  assert.equal(asked.username, "matt-rubens");
  assert.match(mail[0].subject, /Confirm your Lamp username, matt-rubens/);
  const signedIn = async (key) => (await (await accounts(new Request("https://lamp.dev/api/accounts", { headers: { authorization: `Bearer ${key}` } }))).json()).username;
  assert.equal(await signedIn(asked.key), null);
  assert.equal((await confirm()).status, 200);
  assert.equal(await signedIn(asked.key), "matt-rubens");
  assert.equal((await confirm()).status, 410, "the link works once");
  // A confirmation that fails partway can be opened again.
  const flaky = await (await ask({ username: "tide", email: "tide@example.com" })).json();
  const addKey = store.addAccountKey;
  store.addAccountKey = async () => { throw new Error("store down"); };
  assert.equal((await confirm()).status, 503);
  store.addAccountKey = addKey;
  assert.equal((await confirm()).status, 200);
  assert.equal(await signedIn(flaky.key), "tide");

  // The username is the address's: another can't have it, and the address asking again signs in with a key of its own.
  assert.equal((await ask({ username: "matt-rubens", email: "someone@example.com" })).status, 409);
  const again = await (await ask({ email: "MATT@example.com" })).json();
  assert.deepEqual([again.username, again.existing], ["matt-rubens", true]);
  await confirm();
  assert.equal(await signedIn(again.key), "matt-rubens");

  // A link shared with the key is at /matt-rubens/bricks, and a second app of the same name gets a name of its own.
  const shared = await (await share(words, { key: asked.key })).json();
  assert.equal(shared.url, "https://lamp.dev/matt-rubens/bricks");
  assert.equal((await (await share(words, { key: asked.key })).json()).url, "https://lamp.dev/matt-rubens/bricks-2");
  const opened = await page(new Request("https://lamp.dev/api/wish-page?user=matt-rubens&app=bricks"));
  assert.equal(opened.status, 200);
  assert.match(await opened.text(), /Bricks/);
  // The old kind of link to it goes there, with what it carries for the page.
  const old = await page(new Request(`https://lamp.dev/api/wish-page?id=${shared.id}&ask=Add+a+lighthouse`));
  assert.deepEqual([old.status, old.headers.get("location")], [301, "https://lamp.dev/matt-rubens/bricks?ask=Add+a+lighthouse"]);
  // Lamps that follow it, and lamp play, find it by its name too.
  const followed = await (await wishes(new Request("https://lamp.dev/api/wishes?user=matt-rubens&app=bricks"))).json();
  assert.equal(followed.id, shared.id);

  // Without a key a link is shared as before; sent again with one, it moves under the username, and keeps that name
  // when the app is renamed.
  // A share whose record can't be kept lets its new name go again.
  const create = store.create;
  store.create = async () => { throw new Error("store down"); };
  assert.equal((await share({ ...words, name: "Lighthouse" }, { key: asked.key })).status, 503);
  store.create = create;
  assert.equal((await (await share({ ...words, name: "Lighthouse" }, { key: asked.key })).json()).url, "https://lamp.dev/matt-rubens/lighthouse");

  const plain = await (await share({ ...words, name: "Tide Clock" })).json();
  assert.match(plain.url, /\/w\/[A-Za-z0-9]{10}-tide-clock$/);
  const moved = await (await share({ ...words, name: "Tide Clock" }, { key: asked.key, id: plain.id, secret: plain.secret })).json();
  assert.equal(moved.url, "https://lamp.dev/matt-rubens/tide-clock");
  const renamed = await (await share({ ...words, name: "Harbor Clock" }, { id: plain.id, secret: plain.secret })).json();
  assert.equal(renamed.url, "https://lamp.dev/matt-rubens/tide-clock");
});
