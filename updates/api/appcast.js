// Sparkle's appcast for Forge, built from the GitHub releases that carry a sparkle.json.
import { dmgAsset, releases, sparkleInfo } from "../lib/github.js";

const escape = (text) => String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export async function GET(request) {
  const origin = new URL(request.url).origin;
  let items = [];
  try {
    for (const release of (await releases()).slice(0, 10)) {
      const dmg = dmgAsset(release);
      const info = dmg && (await sparkleInfo(release));
      if (!info?.signature) continue;   // released before auto-update: Sparkle can't verify it
      items.push(`    <item>
      <title>${escape(release.name || release.tag_name)}</title>
      <pubDate>${new Date(release.published_at).toUTCString()}</pubDate>
      <sparkle:version>${escape(info.version)}</sparkle:version>
      <sparkle:shortVersionString>${escape(info.shortVersion || info.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escape(info.minimumSystemVersion || "14.0")}</sparkle:minimumSystemVersion>
      <description><![CDATA[${(release.body_html || "").replace(/]]>/g, "]]&gt;")}]]></description>
      <enclosure url="${origin}/download/${encodeURIComponent(release.tag_name)}" length="${Number(info.length) || dmg.size}"
        type="application/octet-stream" sparkle:edSignature="${escape(info.signature)}"/>
    </item>`);
    }
  } catch (error) {
    return new Response(`Couldn't read releases: ${error.message}`, { status: 502 });
  }
  const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Forge</title>
${items.join("\n")}
  </channel>
</rss>
`;
  return new Response(xml, {
    headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600" },
  });
}
