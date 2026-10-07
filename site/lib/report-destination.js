// Keep delivery separate from validation and quotas so a future inbox can replace Slack here.
export function slackPayload(report) {
  const blocks = [];
  let chunk = "";
  const append = () => blocks.push({ type: "section", text: { type: "plain_text", text: chunk, emoji: false } });
  for (const character of report) {
    // Slack decodes these entities even in plain text. Encode once, and split only between tokens,
    // so literal entities, mentions and Unicode display as the person reviewed them.
    const encoded = { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[character] ?? character;
    if (chunk.length + encoded.length > 3000) { append(); chunk = ""; }
    chunk += encoded;
  }
  if (chunk) append();
  return { text: "Lamp bug report", blocks, mrkdwn: false, unfurl_links: false, unfurl_media: false };
}

export function destinationURL(env) {
  const url = new URL(env.LAMP_BUG_REPORT_SLACK_WEBHOOK_URL);
  if (url.protocol !== "https:" || !["hooks.slack.com", "hooks.slack-gov.com"].includes(url.hostname) ||
      !url.pathname.startsWith("/services/") || url.username || url.password || url.search || url.hash || url.port) {
    throw new Error("Destination unavailable");
  }
  return url;
}

export async function forwardReport(report, url, fetcher = fetch) {
  const response = await fetcher(url, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(8000),
    headers: { "Content-Type": "application/json" }, body: JSON.stringify(slackPayload(report)),
  });
  if (!response.ok || (await response.text()).trim() !== "ok") throw new Error("Delivery failed");
}
