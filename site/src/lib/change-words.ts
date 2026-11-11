// The words the change page (`/change?with=app`) hands to the player's AI app: short, since how to change and send the
// game is in the guide the site serves (`public/change-guide.md`, fetched text, not a skill the app installs). What
// can't wait for the guide is here: that the game's page is the destination and the room's address the only place to
// send it (an app's own habits, a site-publishing skill or a local preview, otherwise take over), the address and key,
// what the game is, and the request. `curl -fsS` stops on a guide that isn't there rather than reading an error page.
// One copy for the Copy button and the app's link, so both always carry the same words.

/** The AI apps the change page opens with its words. */
export type ChangeApp = "chatgpt" | "claude";

export const isChangeApp = (app: unknown): app is ChangeApp => app === "chatgpt" || app === "claude";

export type ChangeHandoff = {
  /** The guide's address on the site the page is on. */
  guide: string;
  /** The room's game address (`/r/<room>/game`) and its key. */
  address: string;
  key: string;
  /** The change page the person is on, and the game's name when the room knows it. */
  page: string;
  name?: string | null;
  app?: ChangeApp;
  /** What the person asked for on the game's page, if anything: then the app goes ahead without asking. */
  idea?: string;
};

export function changeWords({ guide, address, key, page, name, app = "chatgpt", idea = "" }: ChangeHandoff): string {
  const wish = idea.trim().replace(/\s+/g, " ");
  const game = name?.trim() ? `"${name.trim()}"` : "the game";
  return [
    `Change ${game}, the existing browser game on my Lamp page (${page}). That page is where it goes: it shows each new version by itself. Send the game only to the game address below; no site-publishing skill, no local server, no separate preview.`,
    ...(app === "chatgpt" ? ["You need to run commands on this computer for it: if you can't, tell me to switch to Codex in the ChatGPT app, and stop."] : []),
    `Read the guide first, and follow it: curl -fsS ${guide}`,
    "If you can't read the guide, stop and tell me.",
    `Game address: ${address}`,
    `Key: ${key}`,
    wish ? `My request: ${wish}` : "My request: none yet. Ask me what to change.",
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
