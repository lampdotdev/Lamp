// Reads Lamp's releases from the private GitHub repo with a read-only token kept on the server
// (GITHUB_TOKEN: a fine-grained token with Contents: read on RooCodeInc/Forge only; the repo keeps its old name).
export const REPO = process.env.FORGE_REPO || "RooCodeInc/Forge";

export async function github(path, accept = "application/vnd.github+json", redirect = "follow") {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN isn't set");
  return fetch(`https://api.github.com${path}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: accept, "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "forge-updates" },
    redirect,
  });
}

/** Published (not draft, not pre-release) releases, newest first, with their notes as HTML. */
export async function releases() {
  const response = await github(`/repos/${REPO}/releases?per_page=30`, "application/vnd.github.html+json");
  if (!response.ok) throw new Error(`GitHub said ${response.status}`);
  return (await response.json()).filter((release) => !release.draft && !release.prerelease);
}

/**
 * A release's DMG asset: Lamp-<version>.dmg, or Forge-<version>.dmg for releases from before the rename.
 * A release republished since the rename can carry both, with sparkle.json describing the Lamp one, so
 * the Lamp DMG wins whenever it's there.
 */
export function dmgAsset(release) {
  const named = (prefix) => release.assets.find((asset) => new RegExp(`^${prefix}-[0-9][0-9A-Za-z.+-]*\\.dmg$`).test(asset.name));
  return named("Lamp") ?? named("Forge");
}

/** The release's sparkle.json (version, signature, length), written by the release workflow. */
export async function sparkleInfo(release) {
  const asset = release.assets.find((asset) => asset.name === "sparkle.json");
  if (!asset) return null;
  const response = await github(`/repos/${REPO}/releases/assets/${asset.id}`, "application/octet-stream");
  return response.ok ? response.json() : null;
}
