// The words the change page (`/change?with=app`) hands to the player's AI app: the room's game address, its key, and
// how to read the game and send a new one whole. One copy for the Copy button and the "Change with ChatGPT" link, so
// both always carry the same words.
//
// The order matters: the app reads the game first, then asks what to change and waits, so nothing is sent before the
// player has said what they want. `--fail-with-body` makes curl stop on an HTTP error (a stale version, a closed room,
// a game too big) and still show the relay's answer, instead of saving an error page as game.html or reporting success.
export function changeWords(address: string, key: string): string {
  return [
    "Help me change the browser game I'm playing. You need to run commands on this computer for it: if you can't, tell me to switch to Codex in the ChatGPT app, and stop.",
    `1. Read the game: curl -sS --fail-with-body -D headers.txt -o game.html ${address} -H "Authorization: Bearer ${key}"`,
    "2. Ask me what I'd like to change, and wait for my answer.",
    "3. Change game.html as I asked (or replace it with a new game). It must stay ONE self-contained HTML file (CSS and JavaScript inside it, no other files), under 4 MB. It plays in a frame of any size, which can change while it plays: lay it out for the frame's own viewport and keep it fitting when that resizes, never for one fixed window height.",
    `4. Send it, with the ETag from headers.txt as If-Match: curl -sS --fail-with-body -X POST ${address} -H "Authorization: Bearer ${key}" -H 'If-Match: "<ETag>"' -H "Content-Type: text/html; charset=utf-8" --data-binary @game.html`,
    "Tell me what it answers. For every later change, start again from step 1.",
  ].join("\n");
}

// OpenAI documents this link for the ChatGPT desktop app on the Mac (it kept Codex's scheme): it opens a new chat with
// the words in the message box and never sends them. It can't choose the chat's mode, which is why the words
// themselves say to switch to Codex when commands can't run.
export const chatgptLink = (words: string) => `codex://new?prompt=${encodeURIComponent(words)}`;

// OpenAI's page for getting the ChatGPT apps, the Mac's among them.
export const CHATGPT_APP_URL = "https://chatgpt.com/download/";
