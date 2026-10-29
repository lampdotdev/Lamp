// Lamp's starters as the homepage shows them: one tape each on the shelf, with a remix of it beside it. The names,
// credits and remixes are the starters' own (Resources/Starters/<id>/starter.md, and the credits.json in its
// repository), each line about it is the description it shipped with, and each picture is its preview, copied to
// src/assets/starters/<id>.png. A starter added there is added here by hand.

export type Starter = {
  id: string;
  name: string;
  /** Who made the original: the starter's upstream author, else Lamp. */
  by: string;
  /** The remix on the shelf beside it: one of the changes the starter suggests. */
  remix: string;
  /** What the remix does to the picture on its label (lib/tapes.ts). */
  treat?: "snow" | "frame";
  /** What it is, in a line: the description Lamp's starter shipped with. */
  about: string;
};

export const STARTERS: Starter[] = [
  { id: "newyork", name: "New York", by: "Mr.doob", remix: "Make it a snowy winter night", treat: "snow", about: "Mr.doob's Slop New York: explore Manhattan on foot, by car, by bike or by helicopter." },
  { id: "homehq", name: "Home HQ", by: "Wes Bos", remix: "Put it on our photo frame", treat: "frame", about: "Wes Bos's family dashboard: the day, calendar, chores, shopping and photos at a glance." },
  { id: "universalremote", name: "Universal Remote", by: "Lamp", remix: "Add a bedtime button", about: "One remote you can tap or talk to for your TV, Roku and Sonos speakers." },
  { id: "buzzerbeater", name: "Buzzer Beater", by: "Lamp", remix: "Make it about reality TV", about: "A menu bar app that tells you when a live game gets close, wild or historic." },
  { id: "fireside", name: "Fireside", by: "Lamp", remix: "Give it a vintage vinyl look", about: "A campfire songbook that listens as you play and helps you learn songs by heart." },
  { id: "localcrossings", name: "Local Crossings", by: "Lamp", remix: "Give it a vintage atlas look", about: "A new crossword every morning, made from the streets, parks and corner spots around you." },
  { id: "today", name: "Today", by: "Lamp", remix: "Give it a bullet journal look", about: "A calm page for the day: three things to do, notes, and how the day's going." },
  { id: "hotshelf", name: "Hot Shelf", by: "Lamp", remix: "Turn this into a beer tracker", about: "Your hot sauces on a lit studio shelf, and which bottle to grab tonight." },
  { id: "diskmap", name: "Disk Map", by: "Lamp", remix: "Draw the map as tiles", about: "Shows where your disk space goes, as rings that fill in while it measures." },
  { id: "hours", name: "Hours", by: "Lamp", remix: "Track mileage instead of hours", about: "Tracks the hours you work for each client and turns them into an invoice." },
  { id: "weddingwords", name: "Wedding Words", by: "Lamp", remix: "Prep me for a job interview", about: "A personal Italian coach for your sister’s wedding, from dinner chats to the toast." },
  { id: "transcriber", name: "Transcriber", by: "Lamp", remix: "Make it a voice diary", about: "Records meetings, calls and lectures, transcribes them on your Mac, and sums them up." },
  { id: "tidyup", name: "Tidy Up", by: "Lamp", remix: "Write the rules as sticky notes", about: "Tidies your Downloads and Desktop by simple rules, and can put everything back." },
  { id: "sitetoapp", name: "Site-to-App", by: "Lamp", remix: "Turn it into a news stand", about: "Turns any website into a minimal Mac app of its own, with no title bar." },
];
