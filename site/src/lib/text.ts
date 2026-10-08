// Ties a passage's last two words together with a no-break space, so its last line never holds a single word.
// `text-wrap: pretty` (in global.css) asks for the same, but not every browser does it.
export const together = (text: string) => text.trim().replace(/\s+(\S+)$/, " $1");

// A heading's sentences, each kept on one line where there are several ("Change your mind. No regrets."), so
// it breaks between them rather than leaving a word of the second one at the end of the first line.
export const sentences = (text: string) => text.trim().split(/(?<=[.!?])\s+/);

