// lamp.dev: one static page, deployed as its own Vercel project.
import { defineConfig } from "astro/config";
import { loadEnv } from "vite";
import tailwindcss from "@tailwindcss/vite";

// The /api/ functions run on Vercel, not under `astro dev`. So the first-idea section asks the real model
// while you work on it, the dev server answers /api/first-idea itself, with OPENROUTER_API_KEY (and
// FIRST_IDEA_MODEL, if set) from site/.env.local, and takes the section's counts without keeping them.
// Without a key it answers as a failed model would, and the section uses its built-in questions.
// Shared wishes (/api/wishes, /w/<id> and its card) are kept in memory while it runs, with no quotas, so Lamp Dev
// can share to it (LAMP_WISH_LINK_ENDPOINT) and the page and card can be tried with nothing set up.
function localAPI() {
  return {
    name: "lamp-local-api",
    apply: "serve",
    async configureServer(server) {
      const { createIdeaHandler } = await import("./lib/first-idea.js");
      const env = { ...process.env, ...loadEnv("development", process.cwd(), "") };
      const idea = createIdeaHandler({ env, limited: false });
      const { createShareHandler, createFileHandler, createPlayHandler, createIdeasHandler, memoryStore } = await import("./lib/shared-wishes.js");
      const { createPageHandler } = await import("./lib/shared-wish-page.js");
      const { createCardHandler } = await import("./lib/wish-card.js");
      const store = memoryStore();
      const share = createShareHandler({ store, limited: false });
      const file = createFileHandler({ store, limited: false });
      const ideas = createIdeasHandler({ store, limited: false });
      // The shared wish's page, which this server draws as you work on it. A shared page plays from this same server:
      // there's no play host of its own here.
      const page = createPageHandler({ store, template: async (origin) => (await fetch(`${origin}/w/`)).text(), playOrigin: (url) => url.origin });
      const play = createPlayHandler({ store, anyHost: true });
      const card = createCardHandler({ store });
      // The relay (RELAY.md) with its Redis and Blob kept in memory: a room's game plays on r-<room>.localhost, and
      // the helper sends its files to /__relay-blob/ here as it would to Blob. LAMP_RELAY=http://localhost:4321 points
      // lamp play at it.
      const { createRelayHandler, createRelayPlayHandler } = await import("./lib/relay.js");
      const { memoryRedis, memoryBlobs } = await import("./lib/relay-store.js");
      let here = "http://localhost:4321";
      const relayDB = memoryRedis(), relayFiles = memoryBlobs({ origin: () => here });
      const relayBase = { db: relayDB, blobs: relayFiles, wishes: store, site: () => here };
      const relay = createRelayHandler({ ...relayBase, playBase: () => here });
      const relayPlay = createRelayPlayHandler({ ...relayBase, playBase: () => here });
      server.middlewares.use(async (req, res, next) => {
        if (req.url === "/api/idea-event") { res.statusCode = 204; return res.end(); }
        const path = req.url.split("?")[0];
        const shared = /^\/w\/([^/]+)(\/card\.png)?$/.exec(path);
        const played = /^\/w\/([^/]+)\/play\/(\d+)\/(.*)$/.exec(path);
        const relayed = /^\/relay-play\/([^/]+)\/(\d+)\/(.*)$/.exec(path);
        const posted = /^\/r\/([0-9a-f]{16})\/game$/.exec(path);
        if (!/^r-/.test(req.headers.host ?? "")) here = `http://${req.headers.host}`;
        const handler = path === "/api/relay" || posted ? relay : path === "/__relay-blob/" ? (request) => relayFiles.upload(request) : relayed ? relayPlay
          : path === "/api/first-idea" ? idea : path === "/api/wishes" ? share : path === "/api/wish-file" ? file : path === "/api/wish-ideas" ? ideas
          : played ? play : shared ? (shared[2] ? card : page) : null;
        if (!handler) return next();
        const target = posted ? `/x?op=game&room=${posted[1]}` : relayed ? `/x?room=${encodeURIComponent(relayed[1])}&v=${relayed[2]}&path=${encodeURIComponent(decodeURIComponent(relayed[3]))}`
          : played ? `/x?id=${encodeURIComponent(played[1])}&v=${played[2]}&path=${encodeURIComponent(decodeURIComponent(played[3]))}`
          : shared ? `/x?id=${encodeURIComponent(shared[1])}` : req.url;
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        const headers = Object.fromEntries(Object.entries(req.headers).map(([k, v]) => [k, Array.isArray(v) ? v.join(", ") : String(v)]));
        const response = await handler(new Request(`http://${req.headers.host}${target}`, {
          method: req.method, headers, ...(["POST", "PUT"].includes(req.method) ? { body: Buffer.concat(chunks) } : {}),
          ...(path === "/__relay-blob/" ? { duplex: "half" } : {}),
        }));
        res.writeHead(response.status, Object.fromEntries(response.headers));
        res.end(Buffer.from(await response.arrayBuffer()));
      });
    },
  };
}

export default defineConfig({
  site: "https://lamp.dev",
  output: "static",
  vite: { plugins: [tailwindcss(), localAPI()] },
});
