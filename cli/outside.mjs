// Lamp's app, reached the way the person's own coding agent reaches it (`OutsideServer`, Lamp's MCP endpoint): a Unix
// socket in that Lamp's own folder, private to the person, a hello line each way, then JSON-RPC a line at a time. lamp
// asks it to take a Mac app's folder on (`open_project`, which Lamp reviews with the person first), to put each change
// into the app it has open (`apply_change`, which says how it went in: live, held for a Reload, reopened…), and to
// look at it (`look_at_app`). What a change does to an open app is Lamp's app's to work out (`LiveReload`); this only
// carries the folder's path there and the answer back.

import { createConnection } from "node:net";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Problem, stateOf } from "./state.mjs";

// The handshake's version, as Lamp's helper sends it (`OutsideKit.protocolVersion`).
const PROTOCOL = 1;

/** What a Lamp is called where its folders are, by its bundle id (`OutsideKit.editionName`). */
export function editionName(bundle) {
  if (bundle === "dev.lamp.host.dev" || bundle.startsWith("dev.lamp.host.dev.")) {
    const instance = bundle.startsWith("dev.lamp.host.dev.") ? bundle.slice("dev.lamp.host.dev.".length) : "";
    return "Lamp Dev" + (instance ? ` ${instance}` : "");
  }
  return bundle === "dev.lamp.host.nightly" ? "Lamp Nightly" : "Lamp";
}

const socketOf = (bundle) => join(homedir(), "Library", "Application Support", editionName(bundle), "MCP", "lamp.sock");

/** The Lamps lamp looks for, in order: the one LAMP_APP names (a bundle id), else the release and then Lamp Nightly. */
const candidates = () => process.env.LAMP_APP ? [process.env.LAMP_APP] : ["dev.lamp.host", "dev.lamp.host.nightly"];

/**
 * A connection to a running Lamp, greeted: `call(tool, args)` answers what the tool said (its outcome, its words and
 * its pictures). Null when no Lamp lamp knows of is answering.
 */
export async function reachLamp(bundles = candidates()) {
  for (const bundle of bundles) {
    if (!/^dev\.lamp\.host(\.[A-Za-z0-9-]+)*$/.test(bundle) || !existsSync(socketOf(bundle))) continue;
    const lamp = await connected(bundle).catch(() => null);
    if (lamp) return lamp;
  }
  return null;
}

function connected(bundle) {
  return new Promise((done, failed) => {
    const socket = createConnection(socketOf(bundle));
    let buffer = "", greeted = false, next = 1;
    const waiting = new Map();
    const fail = (problem) => {
      for (const { failed: no } of waiting.values()) no(problem);
      waiting.clear();
      failed(problem);
    };
    socket.setEncoding("utf8");
    socket.on("error", (error) => fail(new Problem(`couldn't reach ${editionName(bundle)}: ${error.message}`)));
    socket.on("close", () => fail(new Problem(`${editionName(bundle)} closed the connection`)));
    socket.on("connect", () => socket.write(JSON.stringify({ lamp_hello: { protocol: PROTOCOL, client: "lamp" } }) + "\n"));
    const send = (method, params) => new Promise((answered, no) => {
      const id = next++;
      waiting.set(id, { answered, failed: no });
      socket.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
    socket.on("data", async (chunk) => {
      buffer += chunk;
      for (let at; (at = buffer.indexOf("\n")) >= 0; ) {
        const line = buffer.slice(0, at);
        buffer = buffer.slice(at + 1);
        if (!line.trim()) continue;
        let said;
        try { said = JSON.parse(line); } catch { continue; }
        if (!greeted) {
          if (said.lamp_hello?.error) { socket.destroy(); return failed(new Problem(said.lamp_hello.error)); }
          if (!said.lamp_hello) { socket.destroy(); return failed(new Problem(`${editionName(bundle)} didn't answer as Lamp does`)); }
          greeted = true;
          try {
            await send("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "lamp", version: "1" } });
            socket.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
          } catch (error) { return failed(error); }
          done({
            name: editionName(bundle), bundle,
            async call(tool, args) {
              const result = await send("tools/call", { name: tool, arguments: args });
              return answerOf(result);
            },
            close() { socket.removeAllListeners("close"); socket.end(); },
          });
          continue;
        }
        const one = waiting.get(said.id);
        if (!one) continue;
        waiting.delete(said.id);
        if (said.error) one.failed(new Problem(said.error.message ?? "Lamp refused it"));
        else one.answered(said.result ?? {});
      }
    });
  });
}

/** A tool's answer as lamp reads it: the outcome its words lead with, the words after it, and its pictures. */
export function answerOf(result) {
  const content = Array.isArray(result?.content) ? result.content : [];
  const text = content.filter((part) => part.type === "text").map((part) => part.text).join("\n");
  const outcome = /^Outcome: ([a-z_]+)\./.exec(text)?.[1] ?? null;
  // The facts are one line of JSON under the outcome: kept for whoever reads them, out of the words.
  const lines = text.split("\n");
  let facts = {};
  if (outcome && lines[1]?.startsWith("{")) { try { facts = JSON.parse(lines[1]); } catch {} }
  const words = (outcome ? lines.slice(lines[1]?.startsWith("{") ? 2 : 1) : lines).join("\n").trim();
  const pictures = content.filter((part) => part.type === "image" && part.data).map((part) => Buffer.from(part.data, "base64"));
  return { outcome, facts, words, pictures, failed: result?.isError === true };
}

// MARK: Which folders are Lamp's app's

const markOf = (folder) => join(stateOf(folder), "in-lamp.json");

/** The Lamp a folder was given to (`lamp open --in-lamp`), by its bundle id, or null for one lamp runs itself. */
export function givenTo(folder) {
  try { return JSON.parse(readFileSync(markOf(folder), "utf8")).bundle ?? null; } catch { return null; }
}

export function giveTo(folder, bundle) {
  mkdirSync(stateOf(folder), { recursive: true });
  writeFileSync(markOf(folder), JSON.stringify({ bundle }));
}

export function takeBack(folder) { rmSync(markOf(folder), { force: true }); }

/** The pictures an answer brought, kept where lamp keeps a look's, by their paths. */
export function keepPictures(folder, pictures) {
  mkdirSync(stateOf(folder), { recursive: true });
  return pictures.map((bytes, n) => {
    const path = join(stateOf(folder), `lamp-look${n ? `-${n + 1}` : ""}.png`);
    writeFileSync(path, bytes);
    return path;
  });
}
