// Sparkle's appcasts, built from the GitHub releases that carry a sparkle.json: /appcast.xml for Lamp, from the
// releases, and /nightly/appcast.xml (?stream=nightly) for Lamp Nightly, from the one rolling nightly pre-release
// (.github/workflows/nightly.yml). Two apps, two feeds; neither ever sees the other's builds.
import { dmgAsset, isNightly, releases, sparkleInfo } from "../lib/github.js";

const escape = (text) => String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export async function GET(request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const nightly = url.searchParams.get("stream") === "nightly";
  let items = [];
  try {
    const all = await releases({ nightlies: nightly });
    const listed = (nightly ? all.filter(isNightly) : all).slice(0, 10);
    for (const release of listed) {
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
    <title>${nightly ? "Lamp Nightly" : "Lamp"}</title>
${items.join("\n")}
  </channel>
</rss>
`;
  return new Response(xml, {
    headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600" },
  });
}
