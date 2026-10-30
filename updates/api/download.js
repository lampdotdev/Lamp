// Sends a download to the release's DMG through GitHub's short-lived signed link, so the private repo's
// files can be fetched without a GitHub account. Only Lamp DMGs from published releases are served.
// "latest" is the newest published release with a DMG, for the website's Download button. The nightly's DMGs are
// served by its tag ("nightly") and the file's name (/download/nightly/Lamp-Nightly-0.26.0+3.dmg), since the release
// keeps its last few and Lamp Nightly's feed names the one it signed; "latest" never is a nightly. Without a name,
// the newest DMG. The files a Lamp fetches from its own release when it needs them (llama.cpp, a starter's prebuilt app,
// `isFetchedName`) are served the same way, by their release's tag and their name.
import { REPO, dmgAssets, github, isDmgName, isFetchedName, isNightly, releases } from "../lib/github.js";

export async function GET(request) {
  const params = new URL(request.url).searchParams;
  // A version's "+" may reach the query as a space, read back as one; a DMG's name never has a space.
  const tag = params.get("tag") || "", file = (params.get("file") || "").replace(/ /g, "+");
  if (file && !isDmgName(file) && !isFetchedName(file)) return new Response("Not found", { status: 404 });
  let release;
  if (tag === "latest") {
    release = (await releases()).find((release) => dmgAssets(release).length);
    if (!release) return new Response("Not found", { status: 404 });
  } else {
    if (!/^(v[0-9][0-9A-Za-z.+-]*|nightly(-[0-9][0-9A-Za-z.+-]*)?)$/.test(tag)) return new Response("Not found", { status: 404 });
    const releaseResponse = await github(`/repos/${REPO}/releases/tags/${encodeURIComponent(tag)}`);
    if (!releaseResponse.ok) return new Response("Not found", { status: 404 });
    release = await releaseResponse.json();
  }
  const open = !release.draft && (!release.prerelease || isNightly(release));
  const served = !open ? [] : file && isFetchedName(file) ? release.assets : dmgAssets(release);
  const dmg = file ? served.find((asset) => asset.name === file) : served[0];
  if (!dmg) return new Response("Not found", { status: 404 });
  const asset = await github(`/repos/${REPO}/releases/assets/${dmg.id}`, "application/octet-stream", "manual");
  const location = asset.headers.get("location");
  if (!location) return new Response("Couldn't get the download", { status: 502 });
  return Response.redirect(location, 302);
}
