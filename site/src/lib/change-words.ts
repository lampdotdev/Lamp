// The words a shared game's page (`src/pages/w/index.astro`, Make it myself) hands to the player's own AI app: one
// prompt that gets Lamp's command line onto their computer, asking first (`lamp-cli-words.ts`, the homepage's steps),
// then unpacks the game's own Lamp app file into a games folder that stays, opens it, makes the change there and
// looks at it. The player ends with their changed copy open on their computer; the page they came from stays as it
// is. The app works from the file the maker shared (the same one Lamp's app opens), never from the page as it's
// shown nor from the wish's words, so the copy is the game itself, its credits and licenses with it. One copy for the
// link of each app, so both carry the same words.
import { ASK_TO_INSTALL, ASK_TO_UPDATE, CHECK_NODE, FOLLOW_GUIDE, INSTALL, RUN_HERE_CHATGPT, numbered } from "./lamp-cli-words.ts";

/** The AI apps Make it myself opens with its words. */
export type ChangeApp = "chatgpt" | "claude";

export type ChangeHandoff = {
  /** The game's name and its page on lamp.dev. */
  name: string;
  page: string;
  /** The game's Lamp app file, as the maker shared it. */
  file: string;
  app?: ChangeApp;
  /** What the person wrote on the game's page, if anything: else the app asks once the copy is open. */
  idea?: string;
};

// ChatGPT has no folder of the person's to open in, so its copy goes in one folder of its own that's there next time;
// Claude Code is opened in the games folder the person picked (`gamesFolder`).
export const CHATGPT_FOLDER = "~/Lamp Games";

// The file's name on disk, from the game's: only what's safe inside double quotes in any shell, so the words can name
// it as a command without quoting rules of their own. A name with nothing of that left is "Game".
export const fileName = (name: string) => (name.replace(/[^\p{L}\p{N} _-]+/gu, " ").replace(/\s+/g, " ").trim().slice(0, 60).trim() || "Game");

export function changeWords({ name, page, file, app = "chatgpt", idea = "" }: ChangeHandoff): string {
  const wish = idea.trim().replace(/\s+/g, " ");
  const game = name.trim() || "the game";
  const at = fileName(name);
  const lamp = "/Applications/Lamp.app/Contents/Resources/cli/lamp";
  const steps = [
    ...(app === "chatgpt" ? [RUN_HERE_CHATGPT] : []),
    // What a lamp needs for the steps below, checked by what it lists rather than a version number, since the copy
    // inside the Lamp Mac app and one from npm are numbered apart.
    `Check whether Lamp's command-line tools are already here: run lamp help (or ${lamp} help, the copy inside the Lamp Mac app). One is new enough if it lists lamp unpack, lamp open and lamp look. If one is, use it for every lamp command below, skip installing and updating, run lamp guide, and go on from "Read what lamp guide prints".`,
    `${ASK_TO_UPDATE} An old copy inside the Lamp Mac app doesn't count: if that's the only one, go on as if lamp weren't installed.`,
    "If lamp isn't installed at all: " + ASK_TO_INSTALL[0].toLowerCase() + ASK_TO_INSTALL.slice(1),
    CHECK_NODE,
    INSTALL,
    "Then check that lamp help lists lamp unpack, lamp open and lamp look. If it still doesn't (an older lamp may come first on this computer), stop and tell me.",
    FOLLOW_GUIDE,
    app === "chatgpt"
      ? `Work in my games folder, ${CHATGPT_FOLDER} (make it if it isn't there). Keep everything you make in it.`
      : "You were opened in my games folder: work in it, and keep everything you make in it.",
    `Download the game's Lamp app file into the games folder: curl -fsSL -o "${at}.lampapp" "${file}"`,
    `Unpack it: lamp unpack "${at}.lampapp". If a folder named "${at}" already has things in it, it's an earlier copy of mine: unpack into a new folder whose name isn't taken (lamp unpack "${at}.lampapp" "${at} 2"), never over it. If lamp says the game needs the Lamp Mac app, tell me and stop.`,
    "Open my copy with lamp open in its folder, so I can see it.",
    wish
      ? "Make my request in my copy, then check it with lamp look and fix what's wrong."
      : "Ask me what to change. Then make it in my copy, check it with lamp look and fix what's wrong.",
    "Keep the game's credits and licenses as they are: credits.json, every LICENSE or NOTICE file and any credits the game shows.",
    "When it works, leave my copy open, tell me which folder it's in, and ask what to change next.",
  ];
  return [
    `Help me change "${game}", a game shared on Lamp (${page}), in a copy of my own on this computer. The shared page stays as it is.`,
    "Work only from the game's own Lamp app file below: don't copy the game from its web page or remake it from its description.",
    `Game file: ${file}`,
    wish ? `My request: ${wish}` : "My request: none yet.",
    "",
    numbered(steps),
  ].join("\n");
}

// OpenAI documents this link for the ChatGPT desktop app on the Mac (it kept Codex's scheme): it opens a new chat with
// the words in the message box and never sends them. It can't choose the chat's mode, which is why the words
// themselves have a chat that can't run commands offer ChatGPT Work on this computer, and Codex when Work can't.
export const chatgptLink = (words: string) => `codex://new?prompt=${encodeURIComponent(words)}`;

// Claude Code's own link: it opens Claude Code in a terminal with the words typed in, unsent. Claude Code takes at most
// CLAUDE_LINK_MAX characters of them; the words with the longest idea and name the game's page takes stay under it (a
// test holds that). The link only works once Claude Code has put its handler in place, which it does after a message
// is sent in it, unless that's turned off in its settings.
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
