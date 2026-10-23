import { readFileSync } from "node:fs";
import { cacheTags, findWish, isID } from "./shared-wishes.js";
import { summary } from "./shared-wish-page.js";

// The 1200×630 picture X, iMessage and Slack show for a shared wish's link: its name, its line, its icon and the
// picture of it, on the night sky of the first-idea section (global.css's .wish-night) with the lamp's warm light
// rising from the bottom. Drawn by @vercel/og; Geist stands in for the Mac's own type, which can't be sent with it.

// Each file named where it's read, so Vercel's tracing bundles it with the function (vercel.json lists them too).
const fonts = () => [
  { name: "Geist", data: readFileSync(new URL("./fonts/Geist-Regular.ttf", import.meta.url)), weight: 400, style: "normal" },
  { name: "Geist", data: readFileSync(new URL("./fonts/Geist-Bold.ttf", import.meta.url)), weight: 700, style: "normal" },
];
const lampIcon = () => `data:image/png;base64,${readFileSync(new URL("../public/apple-touch-icon.png", import.meta.url)).toString("base64")}`;

export const WIDTH = 1200;
export const HEIGHT = 630;

const h = (type, style, children) => ({ type, props: { style, children } });
const img = (src, style) => ({ type: "img", props: { src, width: style.width, height: style.height, style } });

/** A stored picture as a data: URL, so drawing never waits on a fetch it can't control. Null when it can't be read. */
async function inline(url, fetcher) {
  if (!url) return null;
  if (url.startsWith("data:")) return url;
  try {
    const response = await fetcher(url, { redirect: "error", signal: AbortSignal.timeout(4000) });
    if (!response.ok) return null;
    const type = response.headers.get("content-type") || "";
    if (!/^image\/(png|jpeg)$/.test(type)) return null;
    return `data:${type};base64,${Buffer.from(await response.arrayBuffer()).toString("base64")}`;
  } catch { return null; }
}

/** The card's elements, for @vercel/og. */
export function cardElement(wish, { picture, icon, lamp }) {
  const shot = picture && wish.picture;
  const words = summary(wish);
  const sky = {
    display: "flex", width: "100%", height: "100%", position: "relative", fontFamily: "Geist", color: "white",
    backgroundColor: "#1c1f3f",
    backgroundImage: "radial-gradient(70% 55% at 50% 115%, rgba(255,176,92,0.55), rgba(255,176,92,0) 72%), radial-gradient(60% 60% at 90% -15%, rgba(91,75,224,0.55), rgba(91,75,224,0) 70%), radial-gradient(45% 45% at 0% 30%, rgba(61,56,201,0.35), rgba(61,56,201,0) 70%)",
  };
  const mark = h("div", { display: "flex", alignItems: "center", gap: 14, fontSize: 26, color: "rgba(255,255,255,0.82)" }, [
    img(lamp, { width: 40, height: 40 }),
    h("div", { display: "flex" }, "A wish for Lamp · lamp.dev"),
  ]);
  const name = (size, lines) => h("div", { display: "block", fontSize: size, fontWeight: 700, lineHeight: 1.08, letterSpacing: "-0.02em", lineClamp: lines }, wish.name);
  const line = (size, lines) => h("div", { display: "block", fontSize: size, lineHeight: 1.3, color: "rgba(255,255,255,0.82)", lineClamp: lines }, words);

  // Lamp's mark goes at the top: X lays the page's title over the bottom left of a large card.
  if (!shot) {
    return h("div", { ...sky, flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "56px 96px", textAlign: "center" }, [
      h("div", { display: "flex", marginBottom: 36 }, [mark]),
      img(icon || lamp, { width: 156, height: 156, borderRadius: icon ? 0 : 34 }),
      h("div", { display: "flex", flexDirection: "column", alignItems: "center", gap: 18, marginTop: 28 }, [name(64, 2), line(30, 2)]),
    ]);
  }
  // The picture as large as fits the right of the card, its whole shape kept.
  const box = { width: 600, height: 470 };
  const scale = Math.min(box.width / wish.picture.width, box.height / wish.picture.height);
  const size = { width: Math.round(wish.picture.width * scale), height: Math.round(wish.picture.height * scale) };
  return h("div", { ...sky, padding: "64px 56px 56px 72px", gap: 48, alignItems: "center" }, [
    h("div", { display: "flex", flexDirection: "column", width: 440, height: "100%" }, [
      mark,
      h("div", { display: "flex", flexDirection: "column", gap: 20, marginTop: 36 }, [
        img(icon || lamp, { width: 112, height: 112, borderRadius: icon ? 0 : 24 }),
        name(58, 2),
        line(28, 3),
      ]),
    ]),
    h("div", { display: "flex", flex: 1, alignItems: "center", justifyContent: "center", height: "100%" }, [
      img(picture, { ...size, borderRadius: 16, boxShadow: "0 30px 60px rgba(0,0,0,0.45)" }),
    ]),
  ]);
}

export async function drawCard(wish, { fetcher = fetch } = {}) {
  const { ImageResponse } = await import("@vercel/og");
  const [picture, icon] = await Promise.all([inline(wish.picture?.url, fetcher), inline(wish.icon?.url, fetcher)]);
  const response = new ImageResponse(cardElement(wish, { picture, icon, lamp: lampIcon() }), { width: WIDTH, height: HEIGHT, fonts: fonts() });
  return Buffer.from(await response.arrayBuffer());
}

export function createCardHandler({ env = process.env, fetcher = fetch, store } = {}) {
  return async (request) => {
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    const id = new URL(request.url).searchParams.get("id");
    const wish = isID(id) ? await findWish(id, { env, fetcher, store }) : null;
    if (!wish) return new Response(null, { status: wish === undefined ? 503 : 404, headers: { "Cache-Control": "no-store" } });
    try {
      const png = await drawCard(wish, { fetcher });
      // Linked with the wish's last change in its address, so a change is a new picture; a removal takes it out (`cacheTags`).
      return new Response(png, {
        headers: { "Content-Type": "image/png", "Cache-Control": "public, max-age=3600, s-maxage=86400", ...cacheTags(wish.id) },
      });
    } catch (error) {
      // Only what went wrong, never the wish.
      console.error("wish card failed:", error?.name, error?.message);
      return new Response(null, { status: 503, headers: { "Cache-Control": "no-store" } });
    }
  };
}
