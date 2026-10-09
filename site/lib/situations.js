// The everyday situations the homepage's first-idea section asks about, shared by the page and the server.
// Each belongs to a shape: something done by hand that an app could do instead. Visitors never see the shapes
// named; they decide which situations come next and tell the model what the visitor meant.

export const SHAPES = {
  checking: "looking at something to see if it changed",
  chasing: "waiting on other people and nudging them",
  remembering: "keeping track of things in their head",
  copying: "moving information from one place to another by hand",
  gathering: "pulling bits from several places before something",
  repeating: "doing the same steps every time something happens",
  tidying: "cleaning up after files arrive",
  finding: "searching for the same things again and again",
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
};

// Four at a time. Each round spans different kinds of situation and shows only shapes the rounds before it
// didn't, so "None of these" always moves somewhere new.
export const ROUNDS = [
  ["checking-1", "copying-1", "tidying-1", "chasing-1"],
  ["remembering-1", "gathering-1", "finding-1", "repeating-1"],
  ["checking-2", "gathering-2", "tidying-2", "chasing-2"],
  ["remembering-2", "copying-2", "finding-2", "repeating-2"],
];

// What the page asks when the model can't be reached (a quota, an outage), so the section never dead-ends:
// one question per shape, and a request written from the answer.
export const SCRIPT = {
  checking: ["What is it you check, and what are you hoping to see?", ["A website, for anything new", "A price going down", "Whether something's ready"],
    (a) => `Keep an eye on ${a} for me and tell me as soon as something changes, so I don't have to keep checking. Show it on my desktop as a widget.`],
  chasing: ["Who do you usually end up waiting on?", ["Clients", "Colleagues", "Family or friends"],
    (a) => `Look through the emails I've sent to ${a} and show me which ones haven't had a reply after a few days. Draft a friendly follow-up for each that opens in Mail for me to check and send.`],
  remembering: ["What are you keeping track of?", ["Money people owe me", "Things I lent", "Dates and deadlines"],
    (a) => `Help me keep track of ${a}. Adding something should take a few seconds from the menu bar, and remind me at the right time.`],
  copying: ["Where does it start, and where does it end up?", ["Emails into a spreadsheet", "PDFs into a spreadsheet", "Screenshots into notes"],
    (a) => `I move ${a} by hand. Let me drop them in and pull out the details for me, show me what it found to check, then add it where it belongs.`],
  gathering: ["Before what, usually?", ["Meetings", "Calls with clients", "The end of the month"],
    (a) => `Before ${a}, gather what I need from my email, calendar and notes into one short page, ready when I need it.`],
  repeating: ["What kicks it off?", ["A day of the week", "A certain email arriving", "A file showing up"],
    (a) => `When ${a} comes up, do the steps I always do for me, and show me what it did. Put a button in the menu bar so I can also run it myself.`],
  tidying: ["Which place gets messy?", ["Downloads", "Desktop", "Screenshots"],
    (a) => `Watch my ${a} folder and suggest where each new file should go and a clear name for it. Nothing moves until I say yes.`],
  finding: ["What do you look for most?", ["Files", "Emails", "Things I type a lot"],
    (a) => `Keep the ${a} I need most one shortcut away from any app, so I can find them and use them in a second.`],
};
