// The wishes on the ideas page (src/pages/ideas.astro). Each is software nobody was ever going to make: too
// small, too particular or too personal to sell, so the person did it by hand, in their head, or not at all.
// That's what the page is for: someone reads one and thinks "I don't have that, but I have something like it".
//
// Each wish is one person's, in their own words, with the details that make it theirs (names, numbers, places),
// like the carousel's on the homepage. `about` is two short lines on the card: who it's for and the trouble it
// saves them. `form` is where it lives on their Mac or phone (a menu bar item or a widget is as much a wish as a
// window), which shapes its picture (scripts/idea-art); the card shows only its platform (`platform`). Nothing
// here should be a thing you'd find in the App Store already, done well enough.
// British spelling, as the rest of the site.

export type Form = "Mac" | "iPhone" | "iPad" | "Menu bar" | "Widget" | "Game";
export type Platform = "Mac" | "iPhone" | "iPad";

// Each category's picture in the page's row of categories is src/assets/ideas/objects/<id>.png (scripts/idea-art).
export type Category = { id: string; title: string };

export type Idea = { category: string; name: string; about: string; form: Form; wish: string };

// In the order the page shows them: office work first, as most people who find Lamp spend their days at a desk.
// Their names are short, to fit ten to a row on a laptop and five to a row on a phone; a longer one wraps.
export const CATEGORIES: Category[] = [
  { id: "office", title: "At the office" },
  { id: "trades", title: "On the job" },
  { id: "mac", title: "Your Mac" },
  { id: "money", title: "Paperwork" },
  { id: "home", title: "Home" },
  { id: "school", title: "School" },
  { id: "play", title: "Fun" },
  { id: "hobbies", title: "Hobbies" },
  { id: "friends", title: "Friends" },
];

export const IDEAS: Idea[] = [
  // ---------- At the office ----------
  {
    category: "office", name: "Waiting On", about: "Emails still waiting on a reply, how long each has waited, and a nudge.", form: "Menu bar",
    wish: "The emails I've sent that still need an answer, in my menu bar, with how many days each has been waiting, and a short, friendly nudge drafted in Mail for the ones past three days.",
  },
  {
    category: "office", name: "Friday Update", about: "Your weekly update to your boss, drafted from what you actually did.", form: "Mac",
    wish: "Every Friday at three, a draft of my update to my boss from what I actually did this week (my calendar, the emails I sent, the documents I worked on), in the three headings she likes, for me to edit.",
  },
  {
    category: "office", name: "Back From Leave", about: "Two weeks of email sorted into what needs you and what sorted itself out.", form: "Mac",
    wish: "Back from two weeks off: everything in my inbox sorted into what needs me, what's just for my information and what sorted itself out while I was away, with one line on each.",
  },
  {
    category: "office", name: "Meeting Diet", about: "What each recurring meeting really costs you, and the ones you could drop.", form: "Mac",
    wish: "Every recurring meeting in my calendar, how many hours each has cost me this quarter, how often I actually spoke or was needed, and the five I could quietly drop.",
  },
  {
    category: "office", name: "Monthly Merge", about: "Three spreadsheets in three layouts, merged into the one your boss wants.", form: "Mac",
    wish: "The three regional sales spreadsheets, each in its own layout with its own column names, merged every month into the one format my director wants, with anything odd flagged before I send it.",
  },
  {
    category: "office", name: "Board Pack", about: "The month's numbers in the same eight slides, with the commentary drafted.", form: "Mac",
    wish: "The numbers from our monthly spreadsheets into the same eight slides in our template, charts and all, with a first draft of the commentary on what moved and why.",
  },
  {
    category: "office", name: "What's Different", about: "Every change a customer made to your contract, in plain words.", form: "Mac",
    wish: "When a customer sends back our contract, it compares it to our standard terms and lists every change in plain words, with the ones legal will care about at the top.",
  },
  {
    category: "office", name: "Quote in a Minute", about: "All your pricing and its exceptions, so a quote on a call is always right.", form: "Mac",
    wish: "Our pricing with all its tiers, discounts and exceptions, so I can quote a customer in a minute on a call and know it's right, and send the quote as a tidy PDF afterwards.",
  },
  {
    category: "office", name: "Who's Who", about: "Learn 200 new colleagues' names and faces, starting with this week's.", form: "Mac",
    wish: "Names, faces and teams of the 200 people at my new company, from the directory, as flashcards, starting with the people I'm meeting this week.",
  },
  {
    category: "office", name: "New Starter", about: "A new hire's first two weeks, from laptop to introductions, ticked off.", form: "Mac",
    wish: "Each new starter's first two weeks: laptop, accounts, who they should meet and when, ticked off as it's done, with the welcome email and the calendar invites drafted.",
  },
  {
    category: "office", name: "House Style", about: "Drop in a document and see everything that breaks your style guide.", form: "Mac",
    wish: "I drop in a document or a deck and it checks it against our style guide: product names spelt right, the words we don't use, dates written our way, and lists what to fix.",
  },
  {
    category: "office", name: "Tomorrow", about: "What tomorrow's meetings need from you, and what to read before them.", form: "Menu bar",
    wish: "At the end of each day, a page for tomorrow: my meetings, what each one needs from me, the documents to read first, and anything I promised to do by then.",
  },
  {
    category: "office", name: "One-to-Ones", about: "Notes from every one-to-one, and what you promised each person.", form: "Mac",
    wish: "Notes from my one-to-ones with each of my seven reports, what I promised them and haven't done yet, and before each meeting, a short page of what to bring up.",
  },

  {
    category: "office", name: "Client Timesheet", about: "Your hours filled into the client's clunky timesheet site, every Friday.", form: "Mac",
    wish: "Every Friday it opens the client's timesheet portal, fills in my hours from my calendar, project by project, and stops to show me before it presses Submit.",
  },
  {
    category: "office", name: "Monday Export", about: "The CRM report you rebuild by hand every Monday, done for you.", form: "Mac",
    wish: "Every Monday I export the same report from our CRM, delete four columns, filter it to my region and paste it into the team's sheet. It does that, and tells me if the numbers look strange.",
  },
  {
    category: "office", name: "Brag Jar", about: "Save wins as they happen, and have your self-review half-written.", form: "Menu bar",
    wish: "When someone thanks me or something I did goes well, I drop it in from the menu bar. At review time it turns the year into my self-assessment, with the evidence for each point.",
  },
  {
    category: "office", name: "Handover", about: "What your cover needs before your holiday: open threads and who's waiting.", form: "Mac",
    wish: "Before I go on leave, a handover for whoever covers me: every open thread, who's waiting on what, where the files are, and what to do if the Henderson order goes wrong.",
  },
  {
    category: "office", name: "Office Days", about: "Who's in the office which day, and the day most of the team overlaps.", form: "Menu bar",
    wish: "Which days each of my team is coming in this week, from their calendars, and the day most of us overlap, so I know when to book the long lunch.",
  },
  {
    category: "office", name: "Deliveries Due", about: "Every order and when it's due, with the late ones and a chaser on top.", form: "Mac",
    wish: "Every purchase order we've placed and when it's due, read from the suppliers' confirmation emails, with the late ones at the top and a chaser drafted for each.",
  },
  {
    category: "office", name: "Say It Right", about: "How to say each customer's name, a click away before every call.", form: "Menu bar",
    wish: "How to say each of my customers' names, with a line on who they are and what we last talked about, a click away before every call.",
  },

  // ---------- Around your Mac ----------
  // How the Mac itself works, not the files on it: often the first thing someone asks Lamp for.
  {
    category: "mac", name: "Desk Setups", about: "One click puts every window where it goes, for writing or for calls.", form: "Menu bar",
    wish: "One click puts my windows where they go for writing (the document left, notes right, Slack hidden) or for calls (the call big, my notes beside it), on the laptop alone or with the big screen.",
  },
  {
    category: "mac", name: "Presenting", about: "Desktop hidden, notifications off and personal tabs closed as you share.", form: "Menu bar",
    wish: "When I plug into the projector or share my screen, it hides the files on my desktop, turns off notifications, closes my personal tabs, and opens the deck. Back to normal when I stop.",
  },
  {
    category: "mac", name: "Mic Check", about: "Checks your mic, camera and AirPods a minute before every call.", form: "Menu bar",
    wish: "A minute before each call in my calendar, it makes sure the right microphone and camera are chosen, my volume's up and my AirPods are actually connected, and tells me if not.",
  },
  {
    category: "mac", name: "Heads Up", about: "Who's in your next meeting and what you promised them, with a Join button.", form: "Menu bar",
    wish: "A notification five minutes before each meeting with who's in it, what we last emailed about and what I promised them. Clicking it joins the call.",
  },
  {
    category: "mac", name: "Stay Awake", about: "Keeps your Mac awake through a long export, then lets it sleep.", form: "Menu bar",
    wish: "Keeps my Mac awake while a big download, an export or a backup is running, or while I'm presenting, and lets it sleep the moment it's done, so I stop babysitting the screen.",
  },
  {
    category: "mac", name: "Quitting Time", about: "One click ends the workday: work apps quit, tabs saved, notifications off.", form: "Menu bar",
    wish: "One click at six: Slack and Mail quit, the work tabs close and are saved for tomorrow, notifications go quiet till nine, and my evening playlist starts.",
  },
  {
    category: "mac", name: "Team Clocks", about: "Who on your team is awake now, and whether 4pm is rude for anyone.", form: "Menu bar",
    wish: "My team in Lisbon, Austin and Singapore in my menu bar: who's awake right now, who's on holiday, and whether 4pm my time is rude for anyone.",
  },
  {
    category: "mac", name: "Morning Wallpaper", about: "A new wallpaper every morning, painted from the weather and your day.", form: "Mac",
    wish: "A new wallpaper each morning, painted from today's weather and what's on my calendar: a rainy Monday of meetings looks different from a sunny Friday off.",
  },

  // ---------- Home & family ----------
  {
    category: "home", name: "Movie Night", about: "Five films the whole family will agree on, nothing too scary or seen.", form: "iPad",
    wish: "Friday movie night for the four of us: five films to choose from on what we're in the mood for, nothing we've already seen, nothing scarier than a PG for Ivy, and it keeps track of whose turn it is to have the final say."
  },
  {
    category: "home", name: "Whose Turn", about: "A fair chore rota on the kitchen iPad, so nobody argues whose turn it is.", form: "iPad",
    wish: "Dishwasher, bins, feeding the cat: a rota for our three kids that's fair over the month, not just the week, with swaps allowed, on the old iPad on the kitchen counter, saying whose turn it is right now."
  },
  {
    category: "home", name: "Grandma's Cards", about: "Handwritten family recipes typed up, her notes kept, portions scaled.", form: "Mac",
    wish: "I photograph my grandmother's handwritten recipe cards and it types them up, keeping her notes in the margins, scales them for however many we're feeding, and turns her ounces into grams.",
  },
  {
    category: "home", name: "Bedtime Stories", about: "A new illustrated story every night, starring your child and their toy.", form: "iPad",
    wish: "A new bedtime story every night starring Maya and her stuffed giraffe Kevin, with a picture on each page, picking up where last night's left off, never longer than ten minutes read aloud.",
  },
  {
    category: "home", name: "The House Book", about: "Everything about your house, from the boiler to the good plumber.", form: "Mac",
    wish: "Everything about our house in one place: the boiler model, the paint color in each room, when the gutters were last cleared, the plumber who was actually good. I ask it in plain words and it answers.",
  },
  {
    category: "home", name: "Tooth Fairy Ledger", about: "What the tooth fairy paid for each tooth, so the twins never compare.", form: "iPhone",
    wish: "What the tooth fairy paid for each tooth, which tooth it was and when, so the twins never compare notes and find out she's inconsistent.",
  },
  {
    category: "home", name: "Fridge Rescue", about: "Photograph the fridge and get tonight's dinner from what's about to go off.", form: "iPhone",
    wish: "I photograph the inside of the fridge and it tells me what I can cook tonight with what's about to go off, for two adults and a fussy six-year-old, in thirty minutes or less.",
  },
  {
    category: "home", name: "Mum's Week", about: "A parent's tablets, appointments and visitors, shared with the family.", form: "Mac",
    wish: "Mum's tablets, her appointments and who's visiting which day, kept by me, with a message to my two brothers every Sunday saying what's coming up and which days still need someone."
  },
  {
    category: "home", name: "Has Biscuit Eaten?", about: "Two big buttons by the bowl, so the dog stops getting two dinners.", form: "iPad",
    wish: "The old iPad by her bowl with two big buttons, Fed and Walked, saying when each last happened, so Biscuit stops getting two dinners. And a nudge when her flea treatment's due."
  },
  {
    category: "home", name: "Fridge Gallery", about: "The kids' drawings saved before the recycling, and made into a book.", form: "Mac",
    wish: "I photograph the kids' drawings before they go in the recycling, and it files them by child and age, and at Christmas makes each grandparent a little printed book of the year's best.",
  },
  {
    category: "home", name: "Deep Freeze", about: "What's in the freezer and since when, so nothing sits there for years.", form: "iPhone",
    wish: "What's in the chest freezer and since when, added by saying it out loud as I put it in, with the oldest things at the top so the 2024 lasagne finally gets eaten.",
  },

  // ---------- Just for fun ----------
  // Spins: a game everyone knows, turned into one only this person would want.
  {
    category: "play", name: "Frank the Snake", about: "Snake, starring your dachshund and the socks he really steals.", form: "Game",
    wish: "Snake, but the snake is our dachshund Frank and he's eating the socks he actually steals. Each level is a room in our house, the cat is an obstacle that moves, and the high score board has the whole family on it.",
  },
  {
    category: "play", name: "Escape Room Maker", about: "A whole escape room for a party at home, made from what's in the house.", form: "Game",
    wish: "An escape room for my daughter's tenth birthday, in a theme she chooses: puzzles made from things we have in the house, clues to print and hide, and a countdown on the iPad with a hint button for when they're stuck.",
  },
  {
    category: "play", name: "Murder at Number 12", about: "A murder mystery dinner written for your friends, a character each.", form: "Game",
    wish: "A murder mystery written for our eight friends, each with a character that teases something true about them, a booklet per guest, clues to reveal with each course, and the answer on the Mac in a sealed envelope.",
  },
  {
    category: "play", name: "Nan's Rules", about: "The family card game with Nan's house rules, so the grandkids learn it.", form: "Game",
    wish: "Racing Demon the way Nan played it, with her house rules (including the one she made up to win), against the computer or each other, so the grandkids can learn it properly.",
  },
  {
    category: "play", name: "Family Trumps", about: "Top Trumps of your family and the dog, rated for grumpiness and snacks.", form: "Game",
    wish: "Top Trumps where the cards are us: the four of us, the grandparents, the cousins and the dog, each with a drawn portrait and scores for grumpiness, snack theft and dancing, to play on the iPad or print.",
  },
  {
    category: "play", name: "Inbox Invaders", about: "Space Invaders, where the invaders are the emails you haven't answered.", form: "Game",
    wish: "Space Invaders where the invaders are the subject lines of the emails I haven't answered, getting faster the older they are. Nothing happens to the real emails, sadly.",
  },
  {
    category: "play", name: "Monday Bingo", about: "Bingo for the weekly all-hands, with the phrases you hear every week.", form: "Game",
    wish: "Bingo cards for our Monday all-hands, with the phrases our team actually hears every week, a new card each Monday, and a leaderboard over the year. For my eyes only.",
  },
  {
    category: "play", name: "Fig", about: "A pet in your menu bar that's your real houseplant, thirsty and all.", form: "Game",
    wish: "A little pet in my menu bar that's our real fiddle-leaf fig: it perks up when I water it, droops when I forget, sulks if I move it, and gets a new leaf for every real one.",
  },
  {
    category: "play", name: "Are We Nearly There", about: "Spotting games along your actual route, for a long drive with kids.", form: "Game",
    wish: "A road trip game on the iPad for our drive to Cornwall: things to spot on our actual route, points for each, a question about every town we pass, and a picture of how far we've got.",
  },
  {
    category: "play", name: "Our Street, the Board Game", about: "Monopoly on a board made of your own town and your family's stories.", form: "Game",
    wish: "Monopoly, but the board is our town: our school, the chip shop, Auntie Jo's house as Mayfair, and chance cards about things that really happened to us.",
  },

  // ---------- Work away from a desk ----------
  {
    category: "trades", name: "Lesson Notes", about: "What each music student is working on, who's paid, and notes to parents.", form: "iPad",
    wish: "My 22 piano students: what each is working on, what I set last week and who's paid for the term, and after each lesson a two-line note to their parents written from what I say out loud.",
  },
  {
    category: "trades", name: "Shot List", about: "A wedding's shot list and family groups, ticked off on your phone.", form: "iPhone",
    wish: "Each couple's shot list, the day's timings and the family groups (Gran can't stand for long, the uncles mustn't be in one photo), as a checklist on my phone on the day.",
  },
  {
    category: "trades", name: "Quote From the Van", about: "Talk through the job on site, and the quote's written before you leave.", form: "iPhone",
    wish: "I talk through a job on site into my phone and it writes up the quote, with the parts, my day rate and my usual terms, ready to email from the van before I've driven off.",
  },
  {
    category: "trades", name: "Freezer Map", about: "Which sample is in which slot of which box in the lab freezer.", form: "Mac",
    wish: "Which sample is in which slot of which box on which shelf of the −80, who put it there and when, searchable, so nobody has to stand with the door open reading tiny labels.",
  },
  {
    category: "trades", name: "Color Formulas", about: "Every client's color formula and how it turned out, found in seconds.", form: "iPad",
    wish: "Each client's color formula, the developer and timing, with a photo of the result and a note on what to change next time, found by typing the first few letters of their name.",
  },
  {
    category: "trades", name: "Tonight's Covers", about: "Tonight's bookings with every allergy pulled out, and the regulars' usual.", form: "iPad",
    wish: "Tonight's bookings with every allergy pulled out of the notes, which regulars are coming in and what they had last time, on the iPad by the pass at five o'clock.",
  },
  {
    category: "trades", name: "Agenda Watch", about: "Council agendas read every morning for the stories you cover.", form: "Menu bar",
    wish: "Every morning it reads the agendas the three councils I cover have published, and tells me if my keywords (planning, the bypass, school closures) are in any of them, with the page.",
  },

  // ---------- School ----------
  {
    category: "school", name: "School Dates", about: "Every date buried in school emails, on the family calendar.", form: "Menu bar",
    wish: "Every date buried in the school's emails, newsletters and PDFs (non-uniform day, trip money, the early finish) pulled out and put on our family calendar, with what we need to do before each one.",
  },
  {
    category: "school", name: "What to Bring", about: "What each child needs today: PE kit, library book, swimming bag.", form: "Widget",
    wish: "A widget that says what each kid needs today: PE kit for Sam on Tuesdays, Ella's library book on Thursdays, swimming every other Friday, plus anything the school emailed about this week.",
  },
  {
    category: "school", name: "Spelling Coach", about: "This week's spelling list, read aloud and practised until it sticks.", form: "iPad",
    wish: "I photograph this week's spelling list and it reads the words aloud, one at a time, for my eight-year-old to type, brings back the ones he gets wrong, and gives him a star for each perfect round.",
  },
  {
    category: "school", name: "Explain, Don't Answer", about: "Homework explained the way the school teaches it, without the answer.", form: "Mac",
    wish: "A photo of my son's maths homework, explained step by step the way his school teaches it, with hints he can ask for one at a time, and never just the answer.",
  },
  {
    category: "school", name: "Report Season", about: "Your notes on each pupil, turned into report comments in your voice.", form: "Mac",
    wish: "My notes on each pupil turned into a first draft of their report comment, in my voice, never saying the same thing twice in a class, ready for me to change before it goes anywhere.",
  },
  {
    category: "school", name: "Revision Timetable", about: "A revision timetable that reshuffles itself when you skip a day.", form: "Mac",
    wish: "My GCSE exams, the topics for each and how confident I feel about them, turned into a revision timetable that shuffles things along when I skip a day, without me starting again.",
  },

  // ---------- Money & paperwork ----------
  {
    category: "money", name: "Letter Pile", about: "Scan the post and see what each letter is, and what to do by when.", form: "Mac",
    wish: "I scan the letters that come and it tells me what each is, who it's from and whether I need to do anything by when, and files the rest where I'll find them.",
  },
  {
    category: "money", name: "Tax Shoebox", about: "Receipts photographed through the year, sorted for your tax return.", form: "iPhone",
    wish: "Receipts I photograph through the year, read and sorted into the categories my tax return asks for, with this year's totals ready in January.",
  },
  {
    category: "money", name: "Renewal Season", about: "Every renewal date and last year's price, a month before it renews.", form: "Widget",
    wish: "My car, home and pet insurance, broadband and phone: when each renews, what I paid last year, and a nudge a month before so I can haggle.",
  },
  {
    category: "money", name: "Warranties", about: "Every receipt and warranty in the house, for when something breaks.", form: "Mac",
    wish: "Every receipt and warranty for things in the house, found in my email, with when each warranty runs out, so I know whether to call the shop before I call the repair man.",
  },
  {
    category: "money", name: "Three Flats", about: "Rent, repairs, certificates and deposits for a few rented flats.", form: "Mac",
    wish: "My three flats: rent in each month, repairs open, gas safety and electrical certificates with their due dates, and where every tenant's deposit is protected.",
  },

  // ---------- Hobbies & obsessions ----------
  {
    category: "hobbies", name: "Game Shelf", about: "Which board game fits tonight: how many of you, and how long you've got.", form: "iPhone",
    wish: "Which of our 60 board games fit tonight: how many of us there are, how long we've got and how much brain we have left, and the ones we haven't played in ages first.",
  },
  {
    category: "hobbies", name: "Row Counter", about: "Your knitting pattern one row at a time, with your place always saved.", form: "iPad",
    wish: "My knitting pattern's PDF, read and shown one row at a time, with a big button to move on, and it remembers where I stopped on each project.",
  },
  {
    category: "hobbies", name: "Year List", about: "Every bird you've seen this year, on a map, with a count to beat.", form: "iPhone",
    wish: "Birds I've seen this year, where and when, on a map, with my life list and the first sighting of each, and a count to beat my brother's.",
  },
  {
    category: "hobbies", name: "Campaign Notes", about: "Your D&D campaign's characters and secrets, and a recap each session.", form: "Mac",
    wish: "My D&D campaign: every character the party's met, what they know and what they don't, and at the start of each session a dramatic recap of last time from my scrappy notes.",
  },
  {
    category: "hobbies", name: "Crate Digger", about: "Photograph your record shelves and never buy the same album twice.", form: "iPhone",
    wish: "I photograph the spines on my record shelves and it lists what I own, so in a shop I can check I don't have it already, and see the gaps in each artist's albums.",
  },
  {
    category: "hobbies", name: "Family Tree", about: "Grandad's recorded stories, turned into a family tree that grows.", form: "Mac",
    wish: "Recordings of Grandad's stories, turned into the people, places and dates they mention, with a family tree that grows as I add more.",
  },
  {
    category: "hobbies", name: "Weak Rounds", about: "Practice questions on the quiz rounds your team always loses.", form: "iPhone",
    wish: "Practice questions on the rounds our team always loses (flags, 1970s music, rivers), with our scores each week, so we finally beat the Quizlamic Extremists.",
  },

  // ---------- Friends & neighbors ----------
  {
    category: "friends", name: "Secret Santa", about: "A Secret Santa draw with your group's rules, and nobody sees the list.", form: "Mac",
    wish: "Secret Santa for our 14, drawn so no couple gets each other and nobody gets who they had last year, with each person's name sent to them by message, and nobody (me included) seeing the list.",
  },
  {
    category: "friends", name: "Good Friend", about: "The friends you don't want to drift from, and who to call this week.", form: "Menu bar",
    wish: "The friends I don't want to drift from, when we last spoke (from my messages and calendar), and on Sunday, the two I should get in touch with, with what was going on for them.",
  },
  {
    category: "friends", name: "Dinner Party Book", about: "Who came to dinner, what you cooked, and what each guest doesn't eat.", form: "Mac",
    wish: "Who came to dinner, what I cooked and who doesn't eat what, so I never serve Sarah the same tagine twice and always remember Tom's allergy.",
  },
  {
    category: "friends", name: "Wedding Tables", about: "A seating plan that knows who must sit together and who mustn't.", form: "Mac",
    wish: "Our 112 guests on 12 tables, knowing who must sit together and who mustn't, moved by dragging, with the place cards and the table plan printed when it's done.",
  },

  {
    category: "home", name: "Physio Sheet", about: "Your physio's exercises with a timer for every hold, and a streak.", form: "iPad",
    wish: "The exercises from my physio's sheet, with timers for each hold and rest, a tick when I've done today's, and a streak to keep me honest before my next appointment.",
  },
  {
    category: "home", name: "Safe to Eat", about: "Restaurants where your child with a nut allergy ate safely.", form: "iPhone",
    wish: "The restaurants near us where my son can eat safely with his nut allergy, what he ordered and how it went, and a photo of a menu checked for what to ask about.",
  },
];

/** The name of an idea's pictures in src/assets/ideas/ (icons/<slug>.png, thumbs/<slug>.jpg). */
export const slug = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

// Where each game is played: on the Mac, or on an iPad passed round the table or the car.
const GAMES: Record<string, Platform> = {
  "Frank the Snake": "Mac",
  "Escape Room Maker": "iPad",
  "Murder at Number 12": "Mac",
  "Nan's Rules": "iPad",
  "Family Trumps": "iPad",
  "Inbox Invaders": "Mac",
  "Monday Bingo": "Mac",
  "Fig": "Mac",
  "Are We Nearly There": "iPad",
  "Our Street, the Board Game": "iPad",
};

/** The device an idea runs on: menu bar items and widgets are the Mac's. */
export const platform = (idea: Idea): Platform =>
  idea.form === "iPhone" || idea.form === "iPad" ? idea.form : idea.form === "Game" ? (GAMES[idea.name] ?? "Mac") : "Mac";
