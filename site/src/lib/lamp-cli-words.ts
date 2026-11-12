// The steps an AI app on the person's computer follows to get Lamp's command line (cli/README.md, "For a coding
// agent"), written once for each prompt that hands them over: the homepage's Use with ChatGPT (`chatgpt.ts`) and a
// shared game's Make it myself (`change-words.ts`). They ask the person before installing anything and wait for a yes:
// installing software is never implied by opening a chat, and a prompt that installs straight away reads like prompt
// injection to the AI receiving it.
//
// `lamp guide` is a required step, not an extra: `lamp setup` only writes its skill where an agent's folder already
// exists, and succeeds without writing anything when none does, so the guide is what the chat itself works from.

// ChatGPT's link can't choose the chat's mode, and a plain chat can't run commands: it offers ChatGPT Work on this
// computer by itself (Work in the cloud runs in a container that can't see it), and Codex only when Work can't.
export const RUN_HERE_CHATGPT = "You need to run commands on this computer for this. If you can't in this chat, offer right away to continue in ChatGPT Work, working locally on this computer (Work in the cloud can't reach it), and bring these steps and my answers with you. Only if Work isn't available or can't run commands here, tell me to switch to Codex in the ChatGPT app on this computer, and stop.";

export const ASK_TO_INSTALL = "Explain that Lamp's command-line tools would be installed on this computer (the command-line tools only, not the Lamp Mac app) and that setup can add Lamp instructions for future AI chats. Ask me: \"Would you like me to install and set up Lamp's command-line tools?\" Wait for my explicit yes before running any installation or setup commands. If I decline or haven't answered, stop.";

export const CHECK_NODE = "Check that Node.js 20 or later and npm are installed (node --version, npm --version). If either is missing, or Node is older than 20, tell me how to get a current version and stop. Don't install them yourself.";

export const INSTALL = "Only after I say yes, run npm install -g @lampdotdev/lamp, then lamp setup, then lamp guide. Check that each one worked before running the next. If one fails, stop and tell me what went wrong.";

export const FOLLOW_GUIDE = "Read what lamp guide prints and follow it for the rest of this chat. If lamp setup didn't add Lamp's skill for future chats, tell me.";

/** Steps as a numbered list, one a line. */
export const numbered = (steps: string[]) => steps.map((step, i) => `${i + 1}. ${step}`).join("\n");
