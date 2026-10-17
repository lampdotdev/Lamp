import type { ImageMetadata } from "astro";

// The apps Lamp comes with, read from the app's own Resources/Starters at build time, so the site shows exactly
// what Lamp ships: a starter added there shows here, and one taken out goes. Each opens the real app in Lamp
// (`starterLink` in lib/wish.js), put back on the person's desk if it isn't there, rather than a wish to make it
// again. Lamp finds it by the name in its starter.md.

const notes = import.meta.glob<string>("../../../Resources/Starters/*/starter.md", { eager: true, query: "?raw", import: "default" });
const abouts = import.meta.glob<{ description?: string }>("../../../Resources/Starters/*/about.json", { eager: true, import: "default" });
const icons = import.meta.glob<ImageMetadata>("../../../Resources/Starters/*/icon/icon.png", { eager: true, import: "default" });
const previews = import.meta.glob<ImageMetadata>("../../../Resources/Starters/*/preview.png", { eager: true, import: "default" });

export type Starter = { folder: string; name: string; about: string; icon?: ImageMetadata; preview?: ImageMetadata };

const root = "../../../Resources/Starters";

/** starter.md's `name:` line, as Lamp reads it (Starters.parse): quotes around it are not part of it. */
export function starterName(note: string): string | null {
  const line = note.match(/^name:\s*(.+?)\s*$/m)?.[1];
  return line ? line.replace(/^(["'])(.*)\1$/, "$2") : null;
}

// In the order of their folders, as Lamp puts them on the desk.
export const STARTERS: Starter[] = Object.keys(notes)
  .map((path) => path.split("/").at(-2)!)
  .sort()
  .flatMap((folder) => {
    const name = starterName(notes[`${root}/${folder}/starter.md`]);
    if (!name) return [];
    return [{
      folder,
      name,
      about: abouts[`${root}/${folder}/about.json`]?.description ?? "",
      icon: icons[`${root}/${folder}/icon/icon.png`],
      preview: previews[`${root}/${folder}/preview.png`],
    }];
  });
