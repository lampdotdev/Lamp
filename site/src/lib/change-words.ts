// The words the change page (`/change?with=app`) hands to the player's AI app: the room's game address, its key, and
// how to read the game and send a new one whole. One copy for the Copy button and the app's link, so both always carry
// the same words.
//
// The order matters: the app reads the game first, then checks with the player (asks what to change, or confirms the
// idea they brought from the game's page) and waits, so nothing is sent before the player has said yes. The files go in
// a new empty folder of their own, named in full in every command, so game.html and headers.txt never land in the
// player's home folder or wherever the app happens to start; an app's shell needn't keep a `cd` between commands.
// `--fail-with-body` makes curl stop on an HTTP error (a stale version, a closed room, a game too big) and still show
// the relay's answer, instead of saving an error page as game.html or reporting success.

/** The AI apps the change page opens with its words. */
export type ChangeApp = "chatgpt" | "claude";

export const isChangeApp = (app: unknown): app is ChangeApp => app === "chatgpt" || app === "claude";

export function changeWords(address: string, key: string, { app = "chatgpt", idea = "" }: { app?: ChangeApp; idea?: string } = {}): string {
  const wish = idea.trim().replace(/\s+/g, " ");
  return [
    app === "chatgpt"
      ? "Help me change the browser game I'm playing. You need to run commands on this computer for it: if you can't, tell me to switch to Codex in the ChatGPT app, and stop."
      : "Help me change the browser game I'm playing. You'll run a few commands on this computer for it.",
    "1. Make a new empty folder for this with `mktemp -d`, and use the full path it prints as <folder> in every command below.",
    `2. Read the game: curl -sS --fail-with-body -D "<folder>/headers.txt" -o "<folder>/game.html" ${address} -H "Authorization: Bearer ${key}"`,
    wish
      ? `3. Here's what I'd like to change: "${wish}". Tell me in a line or two how you'll do it, and wait for my OK.`
      : "3. Ask me what I'd like to change, and wait for my answer.",
    "4. Change game.html as I asked (or replace it with a new game). It must stay ONE self-contained HTML file (CSS and JavaScript inside it, no other files), under 4 MB. It plays in a frame of any size, which can change while it plays: lay it out for the frame's own viewport and keep it fitting when that resizes, never for one fixed window height.",
    `5. Send it, with the ETag from headers.txt as If-Match: curl -sS --fail-with-body -X POST ${address} -H "Authorization: Bearer ${key}" -H 'If-Match: "<ETag>"' -H "Content-Type: text/html; charset=utf-8" --data-binary @"<folder>/game.html"`,
    "Tell me what it answers. For every later change, start again from step 2 in the same folder.",
  ].join("\n");
}

// OpenAI documents this link for the ChatGPT desktop app on the Mac (it kept Codex's scheme): it opens a new chat with
// the words in the message box and never sends them. It can't choose the chat's mode, which is why the words
// themselves say to switch to Codex when commands can't run.
export const chatgptLink = (words: string) => `codex://new?prompt=${encodeURIComponent(words)}`;

// Claude Code's own link: it opens Claude Code in a terminal with the words typed in, unsent. Claude Code takes at most
// CLAUDE_LINK_MAX characters of them; the words with the longest idea the game's page takes stay well under it (a test
// holds that). The link only works once Claude Code has put its handler in place, which it does after a message is sent
// in it, unless that's turned off in its settings: the page says so beside the button.
export const CLAUDE_LINK_MAX = 5000;
export const claudeLink = (words: string) => `claude-cli://open?q=${encodeURIComponent(words)}`;

export const appLink = (app: ChangeApp, words: string) => (app === "claude" ? claudeLink(words) : chatgptLink(words));

// Where to get each app: OpenAI's page for the ChatGPT apps, the Mac's among them, and Claude Code's.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
export const CLAUDE_CODE_URL = "https://claude.com/product/claude-code";
