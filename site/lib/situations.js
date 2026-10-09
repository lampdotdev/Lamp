// The everyday situations the homepage's first-idea section asks about, shared by the page and the server.
// Each belongs to a shape: something done by hand that an app could do instead. Visitors never see the shapes
// named; they decide which situations come next and tell the model what the visitor meant. Life away from
// work counts as much as work: most people's first app is for home, family or a hobby, so the shapes cover
// both and every round mixes them.

export const SHAPES = {
  checking: "looking at something to see if it changed",
  chasing: "waiting on other people and nudging them",
  remembering: "keeping track of things in their head",
  copying: "moving information from one place to another by hand",
  gathering: "pulling bits from several places before something",
  repeating: "doing the same steps every time something happens",
  tidying: "cleaning up after files arrive",
  finding: "searching for the same things again and again",
  collecting: "saving things they love or want to try, then never finding them again",
  planning: "planning something that comes around again and again",
  habits: "trying to keep up a habit or routine",
  household: "keeping a household or family on the same page",
};

export const SITUATIONS = {
  "checking-1": { shape: "checking", text: "You open the same website most days, just to see if anything's new." },
  "checking-2": { shape: "checking", text: "You keep checking on something until it's ready: a delivery, a price, a reply." },
  "chasing-1": { shape: "chasing", text: "You send emails and lose track of which ones never got an answer." },
  "chasing-2": { shape: "chasing", text: "You remind people about the same things again and again." },
  "remembering-1": { shape: "remembering", text: "You keep track of something in your head: who owes you, what you lent, when something's due." },
  "remembering-2": { shape: "remembering", text: "There's a note somewhere that you keep adding to and rarely look at." },
  "copying-1": { shape: "copying", text: "You copy numbers or details out of emails or PDFs into a spreadsheet." },
  "copying-2": { shape: "copying", text: "You type the same information into more than one place." },
  "gathering-1": { shape: "gathering", text: "Before a meeting or a call, you dig through emails and notes to remember where things stand." },
  "gathering-2": { shape: "gathering", text: "At the end of the month, you hunt down receipts and bills from all over." },
  "repeating-1": { shape: "repeating", text: "Every week you do the same handful of steps, in the same order." },
  "repeating-2": { shape: "repeating", text: "Whenever a certain kind of email arrives, you do the same thing with it." },
  "tidying-1": { shape: "tidying", text: "Your Downloads folder or desktop fills up until you can't find anything." },
  "tidying-2": { shape: "tidying", text: "You rename files so you'll be able to find them later." },
  "finding-1": { shape: "finding", text: "You're always searching for the same few files, emails or links." },
  "finding-2": { shape: "finding", text: "You type the same replies, addresses or phrases over and over." },
  "collecting-1": { shape: "collecting", text: "You screenshot recipes, books or places to go, and they vanish into your photos." },
  "collecting-2": { shape: "collecting", text: "Friends recommend shows, books or restaurants, and you can't remember which when you want one." },
  "planning-1": { shape: "planning", text: "Every week you work out what to cook, then write the shopping list." },
  "planning-2": { shape: "planning", text: "A trip's bookings, tickets and plans end up scattered across your email and a dozen tabs." },
  "habits-1": { shape: "habits", text: "You keep meaning to do something regularly: exercise, read, water the plants." },
  "habits-2": { shape: "habits", text: "You start keeping a log of something, like runs, sleep or how you feel, and it fizzles out." },
  "household-1": { shape: "household", text: "At home, nobody's sure who's doing what: chores, pickups, whose turn it is." },
  "household-2": { shape: "household", text: "Kids' activities, school emails and family plans are spread across everyone's calendars." },
};

// The longest a visitor's own words and each of their answers may be: the page stops typing there and the
// server refuses longer.
export const TYPED = { words: 500, answer: 300 };

// Four at a time. Each round mixes home and work, and no shape comes back until every other has had its turn,
// so "None of these" always moves somewhere new.
export const ROUNDS = [
  ["collecting-1", "checking-2", "tidying-1", "chasing-1"],
  ["planning-1", "remembering-1", "finding-1", "copying-1"],
  ["habits-1", "household-1", "gathering-1", "repeating-1"],
  ["collecting-2", "household-2", "checking-1", "copying-2"],
  ["planning-2", "remembering-2", "tidying-2", "chasing-2"],
  ["habits-2", "finding-2", "gathering-2", "repeating-2"],
];

// What the page asks when the model can't be reached (a quota, an outage), so the section never dead-ends:
// one question per shape, and a request written from the answer.
export const SCRIPT = {
  checking: ["What is it you check, and what are you hoping to see?", ["A website, for anything new", "A price going down", "Whether something's ready"],
    (a) => `A desktop widget that keeps an eye on ${a} for me and shows what changed, so I don't have to keep checking. Send me a notification when something new turns up.`],
  chasing: ["Who do you usually end up waiting on?", ["Clients", "Colleagues", "Family or friends"],
    (a) => `A menu bar app that looks through the emails I've sent to ${a} and shows which ones haven't had a reply after a few days. For each, it drafts a friendly follow-up that opens in Mail for me to check and send.`],
  remembering: ["What are you keeping track of?", ["Money people owe me", "Things I lent", "Dates and deadlines"],
    (a) => `A menu bar app that keeps track of ${a}. Adding something takes a few seconds, and it reminds me at the right time.`],
  copying: ["Where does it start, and where does it end up?", ["Emails into a spreadsheet", "PDFs into a spreadsheet", "Screenshots into notes"],
    (a) => `A Mac app for ${a}: I drop them in, it pulls out the details and shows me what it found to check, then adds it where it belongs.`],
  gathering: ["Before what, usually?", ["Meetings", "Calls with clients", "The end of the month"],
    (a) => `A menu bar app that, before ${a}, gathers what I need from my email, calendar and notes into one short page, ready when I need it.`],
  repeating: ["What kicks it off?", ["A day of the week", "A certain email arriving", "A file showing up"],
    (a) => `A menu bar app that does the steps I always do when ${a} comes up, and shows me what it did. A button in the menu also lets me run it myself.`],
  tidying: ["Which place gets messy?", ["Downloads", "Desktop", "Screenshots"],
    (a) => `A menu bar app that watches my ${a} folder and suggests where each new file should go, with a clear name for it. Nothing moves until I say yes.`],
  finding: ["What do you look for most?", ["Files", "Emails", "Things I type a lot"],
    (a) => `A Mac app that keeps the ${a} I need most one keyboard shortcut away, from any app, so I can find them and use them in a second.`],
  collecting: ["What do you save the most?", ["Recipes", "Books and shows to try", "Places to go"],
    (a) => `A Mac app where I keep ${a}: I drop in a screenshot or a link and it saves what matters with a short note, so I can find the right one when I want it.`],
  planning: ["What do you plan most often?", ["Meals for the week", "Trips", "Weekends with the family"],
    (a) => `A Mac app that helps me plan ${a}: it suggests a plan from what I like, I change what I want, and it puts what needs doing in Reminders and on my calendar.`],
  habits: ["What would you like to keep up?", ["Exercise", "Reading", "Watering the plants"],
    (a) => `A menu bar app that helps me keep up with ${a}: it reminds me at a good time, I tick it off in one click, and it shows how I've done over the past few weeks.`],
  household: ["What's hardest to keep straight?", ["Chores", "Kids' activities", "Whose turn it is"],
    (a) => `A Mac app with a desktop widget that keeps track of ${a} for our household, so everyone can see at a glance what's coming up and who's on it. It reminds us the day before.`],
};
