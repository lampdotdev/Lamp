// Sends a download to the release's DMG through GitHub's short-lived signed link, so the private repo's
// files can be fetched without a GitHub account. Only Lamp DMGs from published releases are served.
// "latest" is the newest published release with a DMG, for the website's Download button.
import { REPO, dmgAsset, github, releases } from "../lib/github.js";

export async function GET(request) {
  const tag = new URL(request.url).searchParams.get("tag") || "";
  let release;
  if (tag === "latest") {
    release = (await releases()).find((release) => dmgAsset(release));
    if (!release) return new Response("Not found", { status: 404 });
  } else {
    if (!/^v[0-9][0-9A-Za-z.+-]*$/.test(tag)) return new Response("Not found", { status: 404 });
    const releaseResponse = await github(`/repos/${REPO}/releases/tags/${encodeURIComponent(tag)}`);
    if (!releaseResponse.ok) return new Response("Not found", { status: 404 });
    release = await releaseResponse.json();
  }
  const dmg = !release.draft && !release.prerelease && dmgAsset(release);
  if (!dmg) return new Response("Not found", { status: 404 });
  const asset = await github(`/repos/${REPO}/releases/assets/${dmg.id}`, "application/octet-stream", "manual");
  const location = asset.headers.get("location");
  if (!location) return new Response("Couldn't get the download", { status: 502 });
  // Kept a minute at the CDN: each request here costs two calls against the GitHub token's hourly budget, which a flood
  // could spend, leaving every Lamp without updates until it refills. GitHub's signed link lives five minutes, so a
  // copy a minute old still works.
  return new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "public, s-maxage=60" } });
}
