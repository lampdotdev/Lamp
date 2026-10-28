// Lamp's starters as the homepage shows them: one tape each on the shelf, with a remix of it beside it. The names,
// credits and remixes are the starters' own (Resources/Starters/<id>/starter.md and credits.json), and each picture
// is its preview.png, copied to src/assets/starters/<id>.png. A starter added there is added here by hand.

export type Starter = {
  id: string;
  name: string;
  /** Who made the original: the starter's upstream author, else Lamp. */
  by: string;
  /** The remix on the shelf beside it: one of the changes the starter suggests. */
  remix: string;
  /** What the remix does to the picture on its label (lib/tapes.ts). */
  treat?: "snow" | "frame";
};

export const STARTERS: Starter[] = [
  { id: "newyork", name: "New York", by: "Mr.doob", remix: "Make it a snowy winter night", treat: "snow" },
  { id: "homehq", name: "Home HQ", by: "Wes Bos", remix: "Put it on our photo frame", treat: "frame" },
  { id: "universalremote", name: "Universal Remote", by: "Lamp", remix: "Add a bedtime button" },
  { id: "buzzerbeater", name: "Buzzer Beater", by: "Lamp", remix: "Make it about reality TV" },
  { id: "fireside", name: "Fireside", by: "Lamp", remix: "Give it a vintage vinyl look" },
  { id: "localcrossings", name: "Local Crossings", by: "Lamp", remix: "Give it a vintage atlas look" },
  { id: "today", name: "Today", by: "Lamp", remix: "Give it a bullet journal look" },
  { id: "hotshelf", name: "Hot Shelf", by: "Lamp", remix: "Turn this into a beer tracker" },
  { id: "diskmap", name: "Disk Map", by: "Lamp", remix: "Draw the map as tiles" },
  { id: "hours", name: "Hours", by: "Lamp", remix: "Track mileage instead of hours" },
  { id: "weddingwords", name: "Wedding Words", by: "Lamp", remix: "Prep me for a job interview" },
  { id: "transcriber", name: "Transcriber", by: "Lamp", remix: "Make it a voice diary" },
  { id: "tidyup", name: "Tidy Up", by: "Lamp", remix: "Write the rules as sticky notes" },
  { id: "sitetoapp", name: "Site-to-App", by: "Lamp", remix: "Turn it into a news stand" },
];
