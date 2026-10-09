// Runs a few made-up visitors through the first-idea conversation with the real model, to see what its
// questions and wishes read like after a change to RULES in lib/first-idea.js. Each visitor answers with
// their next line, or the model's first option once they run out. From site/:
//   node --env-file=.env.local scripts/try-first-idea.js [visitor number…]
// Needs OPENROUTER_API_KEY (and FIRST_IDEA_MODEL to try another model). Calls the model directly, so no
// quota or count is touched.
import { askModel, modelFor } from "../lib/first-idea.js";

const VISITORS = [
  { situation: "checking-1", answers: ["My kid's school portal, for new grades and teacher notes"] },
  { situation: "tidying-1", answers: ["Downloads, mostly invoices and installers"] },
  { situation: "chasing-1", answers: ["Clients, I'm a freelance designer"] },
  { situation: "copying-1", answers: ["Order confirmation emails into my bookkeeping sheet"] },
  { situation: "remembering-1", answers: ["Who owes me for concert tickets I bought for friends"] },
  { situation: "gathering-1", answers: ["Calls with clients"] },
  { situation: "repeating-1", answers: ["Every Friday I send my team a summary of what got done"] },
  { situation: "finding-2", answers: ["The same few replies to customers asking about shipping"] },
  { words: "I keep losing track of which plants I watered" },
  { words: "every month I rename and file my bank statements" },
];

const env = process.env;
if (!env.OPENROUTER_API_KEY) throw new Error("Set OPENROUTER_API_KEY (see the comment at the top)");
const picked = process.argv.slice(2).map(Number).filter(Boolean);
console.log(`Model: ${modelFor(env)}\n`);

for (const [index, visitor] of VISITORS.entries()) {
  if (picked.length && !picked.includes(index + 1)) continue;
  const conversation = { situation: visitor.situation ?? null, words: visitor.words ?? null, passed: [], turns: [] };
  console.log(`── ${index + 1}. ${visitor.situation ?? `"${visitor.words}"`}`);
  const answers = [...(visitor.answers ?? [])];
  for (let round = 0; round < 3; round++) {
    let reply;
    try { reply = await askModel(conversation, env); }
    catch (error) { console.log(`   ✗ ${error.message}`); break; }
    if (reply.request) {
      console.log(`   Lamp: ${reply.lead}\n   Wish (${reply.request.split(/\s+/).length} words): ${reply.request}\n`);
      break;
    }
    const answer = answers.shift() ?? reply.options[0] ?? "Not sure";
    console.log(`   Lamp: ${reply.question}\n         [${reply.options.join(" | ")}]\n   They: ${answer}`);
    conversation.turns.push({ q: reply.question, a: answer });
  }
}
