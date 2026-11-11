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
//
// `cwd` is the folder Claude Code opens in. Without it, it opens in the person's home folder and asks whether to trust
// it, so the page asks once for a games folder of their own (`gamesFolder`) and always sends it: they trust that folder
// once, never their home folder. A page can't know a Mac's home path nor make a folder, so it's the person's to give.
export const CLAUDE_LINK_MAX = 5000;
export const claudeLink = (words: string, folder: string) =>
  `claude-cli://open?q=${encodeURIComponent(words)}&cwd=${encodeURIComponent(folder)}`;

export const appLink = (app: ChangeApp, words: string, folder = "") => (app === "claude" ? claudeLink(words, folder) : chatgptLink(words));

/** The longest folder Claude Code takes from its link. */
export const CLAUDE_FOLDER_MAX = 4096;

/**
 * The games folder as the person typed or pasted it, checked as Claude Code checks its link's `cwd` (a whole path from
 * "/", no "..", nothing on the network, no control or invisible characters, within its length), so a folder it would
 * refuse is said here in plain words instead of making a link that does nothing. Quotes around it and a path dragged
 * from Finder into Terminal (spaces written "\ ") are taken as the folder they name. Whether the folder exists can't
 * be known from a page, which is why the page says to make it first.
 */
export function gamesFolder(typed: string): { folder: string } | { problem: string } {
  let folder = typed.trim().replace(/^(["'])(.*)\1$/s, "$2").replace(/\\ /g, " ").trim();
  if (folder.length > 1) folder = folder.replace(/\/+$/, "");
  if (!folder) return { problem: "Write the path of your games folder." };
  if (folder.startsWith("~")) return { problem: "Write the whole path, starting with /Users/, not ~." };
  if (folder.startsWith("//")) return { problem: "Pick a folder on this Mac, not on the network." };
  if (!folder.startsWith("/")) return { problem: "That isn't a whole path: it starts with /, like /Users/you/Games." };
  if (folder.split("/").some((part) => part === "..")) return { problem: "Write the path without \"..\" in it." };
  if (/[\u0000-\u001f\u007f]/.test(folder) || /(?![\u200C\u200D\uFE00-\uFE0F\u{E0100}-\u{E01EF}])[\p{Default_Ignorable_Code_Point}\u2028\u2029\u2800\uFFF9-\uFFFB]/u.test(folder))
    return { problem: "That path has characters in it that Claude Code won't take." };
  if (folder.length > CLAUDE_FOLDER_MAX) return { problem: "That path is too long." };
  if (folder === "/" || /^\/Users\/?[^/]*$/.test(folder)) return { problem: "Pick a folder of its own for games, inside your home folder." };
  return { folder };
}

// Where to get each app: OpenAI's page for the ChatGPT apps, the Mac's among them, and Claude Code's.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
export const CLAUDE_CODE_URL = "https://claude.com/product/claude-code";
