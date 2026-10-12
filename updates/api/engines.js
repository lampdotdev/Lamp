// Lamp's brake on the Claude Code and Codex it downloads (EngineInstall in the app). Each copy of Lamp
// follows Claude Code's stable channel and Codex's latest release by itself; a version named here is the
// newest it will use, and a Lamp already past it goes back to it. Set one only when a release breaks Lamp,
// and clear it once a Lamp that copes is out: a push to main deploys it.
const HOLD = {
  // claude: "2.1.287",
  // codex: "0.162.1",
};

export function GET() {
  return new Response(JSON.stringify({ hold: HOLD }), {
    headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=300" },
  });
}
