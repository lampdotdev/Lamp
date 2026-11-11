// "Use with ChatGPT": the homepage hands this prompt to ChatGPT's Mac app, whose Codex runs commands on the Mac and
// so can install lamp's command line (cli/README.md, "For a coding agent") and work with it. The one copy of the
// prompt: the panel shows it, copies it and puts it in the link, so all three are always the same words.
//
// `lamp guide` is a required step, not an extra: `lamp setup` only writes its skill where an agent's folder already
// exists, and succeeds without writing anything when none does, so the guide is what this chat itself works from.
export const SETUP_PROMPT = `Set up Lamp's command line on this Mac so you can make and change apps with it here. This installs the command line only, not the Lamp Mac app.

1. First make sure you can run commands on this Mac. If you can't, tell me to switch to Codex in the ChatGPT app on my Mac, and stop.
2. Check that Node.js 20 or later and npm are installed (node --version, npm --version). If either is missing, or Node is older than 20, tell me how to get a current version and stop. Don't install them yourself.
3. Run npm install -g @lampdotdev/lamp, then lamp setup, then lamp guide. Check that each one worked before running the next. If one fails, stop and tell me what went wrong.
4. Read what lamp guide prints and follow it for the rest of this chat. If lamp setup didn't add Lamp's skill for future chats, tell me.
5. Then ask me what I'd like to make.`;

// OpenAI documents this link for the ChatGPT Mac app (it kept Codex's scheme): it opens a new chat with the prompt in
// the message box and never sends it. It doesn't say which mode the chat opens in, so the panel says to choose Codex.
export const CODEX_LINK = `codex://new?prompt=${encodeURIComponent(SETUP_PROMPT)}`;

// OpenAI's page for getting the ChatGPT apps, the Mac's among them.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
