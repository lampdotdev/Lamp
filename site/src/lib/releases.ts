import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// Lamp's releases as RELEASE_NOTES.md at the top of the repository has them, read when the site is built (from site/,
// so the notes are one folder up): the changelog page shows them all, and the homepage names the newest. The notes
// stay the one place release notes are written; a build without them (the site alone) has no changelog to show and
// points to GitHub's releases instead.

export type Release = { version: string; notes: string[] };

export const REPO_URL = "https://github.com/lampdotdev/Lamp";
export const RELEASES_URL = `${REPO_URL}/releases`;

/** One line of the notes as HTML: `code`, **bold** and [links](…), with everything else escaped. */
function inline(text: string): string {
  const escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return escaped
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2">$1</a>');
}

function read(): string | null {
  try {
    return readFileSync(resolve(process.cwd(), "../RELEASE_NOTES.md"), "utf8");
  } catch {
    return null;
  }
}

/** Every release, newest first: its version and its notes, one HTML string for each point (a point's wrapped lines
 * joined). */
export function releases(): Release[] {
  const text = read();
  if (!text) return [];
  const found: Release[] = [];
  let current: Release | undefined;
  for (const line of text.split("\n")) {
    const heading = line.match(/^##\s+(\S+)/);
    if (heading) {
      current = { version: heading[1], notes: [] };
      found.push(current);
    } else if (current && /^\s*-\s+/.test(line)) {
      current.notes.push(line.replace(/^\s*-\s+/, ""));
    } else if (current && current.notes.length && /^\s+\S/.test(line)) {
      current.notes[current.notes.length - 1] += ` ${line.trim()}`;
    }
  }
  for (const release of found) release.notes = release.notes.map(inline);
  return found;
}

/** The newest release's version, if the notes are there. */
export const latestVersion = (): string | undefined => releases()[0]?.version;
