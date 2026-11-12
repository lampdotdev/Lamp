// The homepage's setup buttons (`SetupButtons.astro`): Use with ChatGPT and Use with Claude each open an AI app on the
// Mac with a prompt to set up lamp's command line and work with it, as Make it myself opens them (`change-words.ts`).
// The two prompts share every step (`lamp-cli-words.ts`, also behind Make it myself): asking before installing,
// checking Node, the install, `lamp setup` and `lamp guide`. They differ only in the one step on where the commands
// run, which depends on the app the prompt lands in.
import { claudeLink } from "./change-words.ts";
import { ASK_TO_INSTALL, CHECK_NODE, FOLLOW_GUIDE, INSTALL, RUN_HERE_CHATGPT, RUN_HERE_CLAUDE, numbered } from "./lamp-cli-words.ts";

const setupPrompt = (runHere: string) => `Help me decide whether to set up Lamp's command-line tools on this Mac, so you can make and change apps with them here.

${numbered([ASK_TO_INSTALL, runHere, CHECK_NODE, INSTALL, FOLLOW_GUIDE, "Then ask me what I'd like to make."])}`;

export const CHATGPT_SETUP_PROMPT = setupPrompt(RUN_HERE_CHATGPT);
export const CLAUDE_SETUP_PROMPT = setupPrompt(RUN_HERE_CLAUDE);

// OpenAI documents this link for the ChatGPT Mac app (it kept Codex's scheme): it opens a new chat with the prompt in
// the message box and never sends it. It doesn't say which mode the chat opens in, and a plain chat can't run
// commands, so the prompt has it offer ChatGPT Work by itself (`RUN_HERE_CHATGPT`).
export const CHATGPT_LINK = `codex://new?prompt=${encodeURIComponent(CHATGPT_SETUP_PROMPT)}`;

// The Claude desktop app's link, as Make it myself uses it (`claudeLink`): a new Claude Code session with the prompt in
// its message box, unsent. It's sent without a folder parameter, so the prompt itself says to work locally and to ask
// for a local session and a folder when this one can't run commands (`RUN_HERE_CLAUDE`).
export const CLAUDE_LINK = claudeLink(CLAUDE_SETUP_PROMPT);

// Where each app is got, the Mac's among them.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
export const CLAUDE_APP_URL = "https://claude.ai/download";
