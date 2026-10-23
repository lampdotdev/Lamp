// Takes a shared wish's link down (lamp.dev/w/<id>), its pictures with it, when it shows what it mustn't.
// From site/, with the production variables pulled (`vercel env pull .env.local --environment=production`):
//   node --env-file=.env.local scripts/take-down-wish.js <id>
// The page and its card can stay in Vercel's cache for up to a day; purge the tag wish-<id> in the project's
// Caches settings to take them out at once.
import { takeDown } from "../lib/shared-wishes.js";

const id = process.argv[2];
if (!id) { console.error("Which wish? node scripts/take-down-wish.js <id>"); process.exit(1); }
console.log(await takeDown(id) ? `Took down ${id}.` : `There's no shared wish ${id}.`);
