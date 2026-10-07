// Ties a passage's last two words together with a no-break space, so its last line never holds a single word.
// `text-wrap: pretty` (in global.css) asks for the same, but not every browser does it.
export const together = (text: string) => text.trim().replace(/\s+(\S+)$/, " $1");
