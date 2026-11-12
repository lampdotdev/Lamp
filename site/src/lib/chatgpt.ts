// "Use with ChatGPT": the homepage hands this prompt to ChatGPT's Mac app, which can run commands on the Mac and so
// can install lamp's command line and work with it. The one copy of the prompt: the button's link carries it and
// "copy the prompt" copies it, so both are always the same words. The install steps are shared with a shared game's
// Make it myself (`lamp-cli-words.ts`), which asks before installing as this does.
import { ASK_TO_INSTALL, CHECK_NODE, FOLLOW_GUIDE, INSTALL, RUN_HERE_CHATGPT, numbered } from "./lamp-cli-words.ts";

export const SETUP_PROMPT = `Help me decide whether to set up Lamp's command-line tools on this Mac, so you can make and change apps with them here.

${numbered([ASK_TO_INSTALL, RUN_HERE_CHATGPT, CHECK_NODE, INSTALL, FOLLOW_GUIDE, "Then ask me what I'd like to make."])}`;

// OpenAI documents this link for the ChatGPT Mac app (it kept Codex's scheme): it opens a new chat with the prompt in
// the message box and never sends it. It doesn't say which mode the chat opens in, and a plain chat can't run
// commands, so the prompt has it offer ChatGPT Work by itself (`RUN_HERE_CHATGPT`).
export const CODEX_LINK = `codex://new?prompt=${encodeURIComponent(SETUP_PROMPT)}`;

// OpenAI's page for getting the ChatGPT apps, the Mac's among them.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
