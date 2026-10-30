// Lamp's starters as the homepage shows them: one sleeve each on the shelf, with a remix of it beside it. The names,
// credits and remixes are the starters' own (Resources/Starters/<id>/starter.md, and the credits.json in its
// repository), each line about it is the description it shipped with, its changes are its starter.md's tweaks, its
// kind and places are what Lamp makes of it (a game, a screen, else a Mac app), and each picture is its preview, copied
// to src/assets/starters/<id>.png. A starter added there is added here by hand.

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
  /** What kind of thing it is, and where it runs, as its sleeve says (a place's icon is the homepage's). */
  kind: string;
  places: string[];
  /** The page anyone can play it on in a browser, where its repository publishes one. */
  page?: string;
  /** The changes the starter suggests (its starter.md), on the back of its sleeve. */
  tweaks: string[];
};

export const STARTERS: Starter[] = [
  { id: "newyork", page: "https://lampdotdev.github.io/newyork/", name: "New York", by: "Mr.doob", remix: "Make it a snowy winter night", treat: "snow", about: "Mr.doob's Slop New York: explore Manhattan on foot, by car, by bike or by helicopter.", kind: "Game \u00b7 3D", places: ["Mac", "iPad", "Xbox", "TV"], tweaks: ["Make it a snowy winter night", "Make it a lot more fun", "Move the city to the Moon"] },
  { id: "homehq", name: "Home HQ", by: "Wes Bos", remix: "Put it on our photo frame", treat: "frame", about: "Wes Bos's family dashboard: the day, calendar, chores, shopping and photos at a glance.", kind: "Screen", places: ["Mac", "iPad", "TV"], tweaks: ["Put it on our kitchen tablet", "Put it on our photo frame", "Add a countdown to school"] },
  { id: "thelittlehouse", name: "The Little House", by: "remvze", remix: "Make it a rainy Tokyo night", about: "A cozy little room on a rainy night, with a fire and a ticking clock to listen to.", kind: "Web app \u00b7 3D", places: ["Mac", "iPad", "TV"], tweaks: ["Make it a starry night sky", "Wake me gently with birdsong", "Make it a rainy Tokyo night"] },
  { id: "universalremote", name: "Universal Remote", by: "Lamp", remix: "Add a bedtime button", about: "One remote you can tap or talk to for your TV, Roku and Sonos speakers.", kind: "Mac app", places: ["Mac"], tweaks: ["Put the remote on my iPhone", "Add a bedtime button", "A kids' mode with their apps"] },
  { id: "buzzerbeater", name: "Buzzer Beater", by: "Lamp", remix: "Make it about reality TV", about: "A menu bar app that tells you when a live game gets close, wild or historic.", kind: "Mac app", places: ["Mac"], tweaks: ["Add a scoreboard desktop widget", "Remind me before big games", "Make it about reality TV"] },
  { id: "fireside", name: "Fireside", by: "Lamp", remix: "Give it a vintage vinyl look", about: "A campfire songbook that listens as you play and helps you learn songs by heart.", kind: "Mac app", places: ["Mac"], tweaks: ["Give it a vintage vinyl look", "Add a metronome for practice", "Make it a ukulele songbook"] },
  { id: "localcrossings", name: "Local Crossings", by: "Lamp", remix: "Give it a vintage atlas look", about: "A new crossword every morning, made from the streets, parks and corner spots around you.", kind: "Mac app", places: ["Mac"], tweaks: ["Give it a vintage atlas look", "Pin each answer on the map", "Make it about my favorite city"] },
  { id: "today", name: "Today", by: "Lamp", remix: "Give it a bullet journal look", about: "A calm page for the day: three things to do, notes, and how the day's going.", kind: "Mac app", places: ["Mac"], tweaks: ["Give it a bullet journal look", "Add a water counter", "Turn it into a gratitude journal"] },
  { id: "hotshelf", name: "Hot Shelf", by: "Lamp", remix: "Turn this into a beer tracker", about: "Your hot sauces on a lit studio shelf, and which bottle to grab tonight.", kind: "Mac app", places: ["Mac"], tweaks: ["Make it a realistic kitchen cabinet", "Show ingredients on every tag", "Turn this into a beer tracker"] },
  { id: "diskmap", name: "Disk Map", by: "Lamp", remix: "Draw the map as tiles", about: "Shows where your disk space goes, as rings that fill in while it measures.", kind: "Mac app", places: ["Mac"], tweaks: ["Draw the map as tiles", "Find big files I never open", "Map where my week's hours go"] },
  { id: "hours", name: "Hours", by: "Lamp", remix: "Track mileage instead of hours", about: "Tracks the hours you work for each client and turns them into an invoice.", kind: "Mac app", places: ["Mac"], tweaks: ["Give invoices a classic letterhead look", "Remind me if no timer runs", "Track mileage instead of hours"] },
  { id: "weddingwords", name: "Wedding Words", by: "Lamp", remix: "Prep me for a job interview", about: "A personal Italian coach for your sister’s wedding, from dinner chats to the toast.", kind: "Mac app", places: ["Mac"], tweaks: ["Give it a Neapolitan postcard look", "Time my toast run-throughs", "Prep me for a job interview"] },
  { id: "transcriber", name: "Transcriber", by: "Lamp", remix: "Make it a voice diary", about: "Records meetings, calls and lectures, transcribes them on your Mac, and sums them up.", kind: "Mac app", places: ["Mac"], tweaks: ["Show transcripts as chat bubbles", "Email me the action items", "Make it a voice diary"] },
  { id: "tidyup", name: "Tidy Up", by: "Lamp", remix: "Write the rules as sticky notes", about: "Tidies your Downloads and Desktop by simple rules, and can put everything back.", kind: "Mac app", places: ["Mac"], tweaks: ["Write the rules as sticky notes", "Show what's taking up space", "Sort my photos into albums"] },
  { id: "sitetoapp", name: "Site-to-App", by: "Lamp", remix: "Turn it into a news stand", about: "Turns any website into a minimal Mac app of its own, with no title bar.", kind: "Mac app", places: ["Mac"], tweaks: ["Give it a vintage Mac look", "Show two sites side by side", "Turn it into a news stand"] },
];
