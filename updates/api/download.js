// Sends a download to the release's DMG through GitHub's short-lived signed link, so the private repo's
// files can be fetched without a GitHub account. Only Lamp DMGs from published releases are served.
import { REPO, dmgAsset, github } from "../lib/github.js";

export async function GET(request) {
  const tag = new URL(request.url).searchParams.get("tag") || "";
  if (!/^v[0-9][0-9A-Za-z.+-]*$/.test(tag)) return new Response("Not found", { status: 404 });
  const releaseResponse = await github(`/repos/${REPO}/releases/tags/${encodeURIComponent(tag)}`);
  if (!releaseResponse.ok) return new Response("Not found", { status: 404 });
  const release = await releaseResponse.json();
  const dmg = !release.draft && !release.prerelease && dmgAsset(release);
  if (!dmg) return new Response("Not found", { status: 404 });
  const asset = await github(`/repos/${REPO}/releases/assets/${dmg.id}`, "application/octet-stream", "manual");
  const location = asset.headers.get("location");
  if (!location) return new Response("Couldn't get the download", { status: 502 });
  return Response.redirect(location, 302);
}
