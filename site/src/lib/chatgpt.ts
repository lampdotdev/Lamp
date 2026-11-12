// "Use with ChatGPT": the homepage hands this prompt to ChatGPT's Mac app, whose Codex runs commands on the Mac and
// so can install lamp's command line (cli/README.md, "For a coding agent") and work with it. The one copy of the
// prompt: the button's link carries it and "copy the prompt" copies it, so both are always the same words. It asks
// the person before installing anything and waits for a yes: installing software is never implied by opening the
// chat, and a prompt that installs straight away reads like prompt injection to the AI receiving it.
//
// `lamp guide` is a required step, not an extra: `lamp setup` only writes its skill where an agent's folder already
// exists, and succeeds without writing anything when none does, so the guide is what this chat itself works from.
export const SETUP_PROMPT = `Help me decide whether to set up Lamp's command-line tools on this Mac, so you can make and change apps with them here. This would install the command-line tools only, not the Lamp Mac app.

1. First explain that Lamp's command-line tools will be installed on this Mac and that setup can add Lamp instructions for future AI chats. Ask me: "Would you like me to install and set up Lamp's command-line tools?" Wait for my explicit yes before running any installation or setup commands. If I decline or haven't answered, stop.
2. You need to run commands on this Mac for this. If you can't in this chat, offer right away to continue in ChatGPT Work, working locally on this Mac (Work in the cloud can't reach it), and bring these steps and my answer with you. Only if Work isn't available or can't run commands on this Mac, tell me to switch to Codex in the ChatGPT app on my Mac, and stop.
3. Check that Node.js 20 or later and npm are installed (node --version, npm --version). If either is missing, or Node is older than 20, tell me how to get a current version and stop. Don't install them yourself.
4. Only after I say yes, run npm install -g @lampdotdev/lamp, then lamp setup, then lamp guide. Check that each one worked before running the next. If one fails, stop and tell me what went wrong.
5. Read what lamp guide prints and follow it for the rest of this chat. If lamp setup didn't add Lamp's skill for future chats, tell me.
6. Then ask me what I'd like to make.`;

// OpenAI documents this link for the ChatGPT Mac app (it kept Codex's scheme): it opens a new chat with the prompt in
// the message box and never sends it. It doesn't say which mode the chat opens in, and a plain chat can't run
// commands, so the prompt has it offer ChatGPT Work by itself. Only Work on the Mac reaches the Mac: Work in the cloud
// runs in a container that can't see it. Codex in the ChatGPT app is the fallback when Work can't.
export const CODEX_LINK = `codex://new?prompt=${encodeURIComponent(SETUP_PROMPT)}`;

// OpenAI's page for getting the ChatGPT apps, the Mac's among them.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
