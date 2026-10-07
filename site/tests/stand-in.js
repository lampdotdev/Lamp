import { mkdir, writeFile } from "node:fs/promises";
import { standIn, displayedReport } from "./receivers.js";

const proof = process.argv[2];
if (!proof) throw new Error("Provide a directory for made-up test payloads");
await mkdir(proof, { recursive: true });
const receiver = await standIn({ port: 49181, onPayload: async (payload) => {
  await writeFile(`${proof}/slack-would-receive.json`, JSON.stringify(payload, null, 2) + "\n");
  await writeFile(`${proof}/received-report.txt`, displayedReport(payload));
} });
console.log(`Local stand-in ready: ${receiver.url}/api/bug-report (never contacts Slack)`);
for (const signal of ["SIGTERM", "SIGINT"]) process.on(signal, async () => { await receiver.close(); process.exit(0); });
