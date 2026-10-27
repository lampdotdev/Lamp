// The family's data. The example content (marked `ex`) is made afresh at each launch relative to "today", so it
// always looks current, until Clear Examples in the settings sheet takes it away for good. What the family adds or
// changes (their own events, the shopping list, chores ticked off today, stars, favorites, settings) is saved with
// LampStore (Web/lamp.js) under "homehq" by `save()`, which app.js calls whenever the data changes.
window.DATA = (function () {
  var base = new Date();
  base.setHours(0, 0, 0, 0);

  function at(d, hm) {
    var p = hm.split(':');
    var x = new Date(base);
    x.setDate(x.getDate() + d);
    x.setHours(+p[0], +p[1], 0, 0);
    return x;
  }
  var n = 0;
  function ev(d, s, e, title, people, extra) {
    return Object.assign({ id: 'e' + (++n), start: at(d, s), end: at(d, e), title: title, people: people, ex: true }, extra || {});
  }
  function allDay(d, days, title, people, extra) {
    return Object.assign({ id: 'e' + (++n), allDay: true, start: at(d, '00:00'), end: at(d + days, '00:00'), title: title, people: people, ex: true }, extra || {});
  }

  // The family, one color each. Kids (with an age) earn stars for chores.
  var people = [
    { id: 'alex', name: 'Alex', color: '#2D5BFF', rgb: '45 91 255', ink: '#FFFFFF' },
    { id: 'jordan', name: 'Jordan', color: '#E4007C', rgb: '228 0 124', ink: '#FFFFFF' },
    { id: 'maya', name: 'Maya', age: 10, color: '#00A36C', rgb: '0 163 108', ink: '#FFFFFF' },
    { id: 'otto', name: 'Otto', age: 6, color: '#FFB000', rgb: '255 176 0', ink: '#111111' }
  ];
  var ALL = people.map(function (p) { return p.id; });
  var family = { id: 'family', name: 'Family', color: '#111111', rgb: '17 17 17', ink: '#FFFFFF' };

  // ---------------------------------------------------------------- calendar
  var events = [
    // Today
    allDay(0, 1, 'Pajama Day at school', ['otto']),
    allDay(0, 1, 'Garbage + recycling night', ALL),
    ev(0, '07:00', '07:45', 'Gym', ['jordan'], { loc: 'Iron Works' }),
    ev(0, '08:15', '08:40', 'School drop-off', ['alex'], { travel: 10, loc: 'Parkdale Elementary' }),
    ev(0, '09:30', '10:30', 'Design review', ['jordan'], { loc: 'Office · Room 4B' }),
    ev(0, '12:00', '12:45', 'Dentist', ['maya', 'jordan'], { travel: 15, loc: 'Bright Smiles Dental' }),
    ev(0, '13:00', '14:00', 'Lunch with Sam', ['alex'], { loc: 'Café Rustica' }),
    ev(0, '15:45', '16:30', 'Piano lesson', ['otto'], { travel: 12, loc: "Ms. Park's Studio", notes: 'Bring the blue theory book.' }),
    ev(0, '16:05', '16:30', 'Drive Maya to soccer', ['jordan']),
    ev(0, '16:25', '16:50', 'Pick up Otto', ['jordan'], { loc: "Ms. Park's Studio" }),
    ev(0, '16:30', '18:00', 'Soccer practice', ['maya'], { travel: 20, loc: 'Lakeshore Fields', notes: 'Shin guards + water bottle. Rain likely — pack a jacket.' }),
    ev(0, '17:00', '17:30', 'Parent–teacher call', ['alex', 'jordan'], { loc: 'Zoom' }),
    ev(0, '18:30', '19:30', "Dinner at Nonna's", ALL, { travel: 20, loc: "Nonna's", notes: 'Bring the lemon cake.' }),
    ev(0, '20:00', '20:30', 'Bath + books', ['otto']),

    // Tomorrow → +6
    allDay(1, 3, 'Alex in Montréal', ['alex'], { loc: 'Hotel William Gray' }),
    ev(1, '07:00', '07:45', 'Gym', ['jordan'], { loc: 'Iron Works' }),
    ev(1, '08:15', '08:40', 'School drop-off', ['jordan'], { travel: 10 }),
    ev(1, '10:30', '11:15', 'Vet — Biscuit', ['jordan'], { travel: 10, loc: 'Riverdale Animal Clinic' }),
    ev(1, '15:30', '16:30', 'Art club', ['maya'], { loc: 'School' }),
    ev(1, '16:00', '18:00', 'Playdate with Leo', ['otto'], { travel: 8, loc: "Leo's house" }),
    ev(1, '19:00', '21:00', 'Book club', ['jordan'], { travel: 10, loc: "Priya's" }),

    ev(2, '09:00', '14:00', 'Science Center trip', ['otto'], { loc: 'Ontario Science Center' }),
    ev(2, '13:00', '13:45', 'Haircuts', ['maya', 'otto'], { travel: 10, loc: 'Snip Snip Kids' }),
    ev(2, '16:30', '18:00', 'Soccer practice', ['maya'], { travel: 20, loc: 'Lakeshore Fields' }),
    ev(2, '18:00', '19:30', 'Pizza night', ALL),

    ev(3, '10:00', '10:45', 'Swim lessons', ['otto'], { travel: 12, loc: 'Wellesley Pool' }),
    ev(3, '11:00', '12:00', 'Grocery run', ['jordan']),
    ev(3, '13:00', '15:30', "Zoe's birthday party", ['maya'], { travel: 15, loc: 'Pottery Place' }),
    ev(3, '19:00', '21:00', 'Movie night', ALL),

    ev(4, '10:30', '12:00', 'Sunday brunch', ALL, { travel: 15, loc: 'Lady Marmalade' }),
    ev(4, '17:05', '18:20', 'Flight home · AC 418', ['alex'], { loc: 'YUL → YYZ' }),

    ev(5, '07:00', '07:45', 'Gym', ['jordan']),
    ev(5, '15:45', '16:30', 'Piano lesson', ['otto'], { travel: 12 }),
    ev(5, '16:30', '18:00', 'Soccer practice', ['maya'], { travel: 20 }),
    ev(5, '19:00', '20:00', 'Yoga', ['jordan']),

    allDay(6, 2, 'Grandma visits', ALL),
    ev(6, '09:00', '09:45', 'Dentist', ['otto'], { travel: 15, loc: 'Bright Smiles Dental' }),
    ev(6, '16:30', '18:00', 'Soccer practice', ['maya'], { travel: 20 })
  ];

  // Background recurring events so the month view has texture
  for (var d = -40; d <= 45; d++) {
    if (d >= 0 && d <= 6) continue;
    var dow = new Date(at(d, '00:00')).getDay();
    if (dow === 1) events.push(ev(d, '15:45', '16:30', 'Piano lesson', ['otto']));
    if (dow === 2 || dow === 4) events.push(ev(d, '16:30', '18:00', 'Soccer practice', ['maya']));
    if (dow === 3) events.push(ev(d, '19:00', '20:00', 'Yoga', ['jordan']));
    if (dow === 6) events.push(ev(d, '10:00', '10:45', 'Swim lessons', ['otto']));
    if (dow === 0) events.push(ev(d, '17:30', '19:30', "Dinner at Nonna's", ALL));
    if (dow === 5 && d % 2 === 0) events.push(ev(d, '18:00', '19:30', 'Pizza night', ALL));
    if (d % 9 === 0) events.push(ev(d, '12:00', '13:00', 'Lunch meeting', ['alex']));
    if (d % 11 === 0) events.push(ev(d, '09:00', '10:00', 'Doctor', ['jordan']));
  }
  events.push(allDay(12, 1, "Maya's birthday 🎂", ALL));
  events.push(allDay(-8, 3, 'Cottage weekend', ALL));

  // ---------------------------------------------------------------- chores
  var routines = [
    { id: 'morning', name: 'Morning', range: '6 – 11 AM', from: 0, to: 11 },
    { id: 'after', name: 'After school', range: '11 AM – 5 PM', from: 11, to: 17 },
    { id: 'evening', name: 'Evening', range: '5 – 10 PM', from: 17, to: 24 }
  ];
  var cid = 0;
  function chore(r, who, title, emoji, stars, done, extra) {
    return Object.assign({ id: 'c' + (++cid), r: r, who: who, title: title, emoji: emoji, stars: stars, done: !!done, ex: true }, extra || {});
  }
  var chores = [
    chore('morning', 'maya', 'Make bed', '🛏️', 1, true),
    chore('morning', 'maya', 'Brush teeth', '🪥', 1, true),
    chore('morning', 'maya', 'Pack backpack', '🎒', 1, true),
    chore('morning', 'otto', 'Make bed', '🛏️', 1, true),
    chore('morning', 'otto', 'Brush teeth', '🪥', 1, true),
    chore('morning', 'otto', 'Get dressed', '👕', 1, false),
    chore('morning', 'alex', 'School drop-off', '🚗', 0, true),
    chore('morning', 'jordan', 'Pack lunches', '🥪', 0, true),
    chore('morning', 'any', 'Feed Biscuit', '🐶', 1, true),

    chore('after', 'maya', 'Unpack lunchbox', '🥪', 1, true),
    chore('after', 'maya', 'Homework', '📚', 2, false),
    chore('after', 'maya', 'Pack soccer bag', '⚽', 1, false),
    chore('after', 'otto', 'Unpack lunchbox', '🥪', 1, true),
    chore('after', 'otto', 'Read for 20 min', '📖', 2, false),
    chore('after', 'otto', 'Practice piano', '🎹', 2, false),
    chore('after', 'otto', 'Tidy the Lego', '🧱', 1, false),
    chore('after', 'alex', 'Take out recycling', '♻️', 0, false, { overdue: true }),
    chore('after', 'alex', 'Call the plumber', '☎️', 0, true),
    chore('after', 'jordan', 'Fold laundry', '🧺', 0, false),
    chore('after', 'jordan', 'Order Zoe’s gift', '🎁', 0, true),
    chore('after', 'any', 'Water the plants', '🪴', 1, false),
    chore('after', 'any', 'Empty dishwasher', '🍽️', 2, false),
    chore('after', 'any', 'Walk Biscuit', '🐕', 2, true),

    chore('evening', 'maya', 'Set the table', '🍴', 1, false),
    chore('evening', 'maya', 'Lay out clothes', '👕', 1, false),
    chore('evening', 'maya', 'Shower', '🚿', 1, false),
    chore('evening', 'otto', 'Clear plates', '🍽️', 1, false),
    chore('evening', 'otto', 'Bath', '🛁', 1, false),
    chore('evening', 'otto', 'Lay out clothes', '👕', 1, false),
    chore('evening', 'alex', 'Lock up', '🔐', 0, false),
    chore('evening', 'jordan', 'Run dishwasher', '🫧', 0, false),
    chore('evening', 'any', 'Wipe counters', '🧽', 1, false),
    chore('evening', 'any', 'Garbage to curb', '🗑️', 2, false)
  ];
  var stars = { maya: 42, otto: 57 };
  // Mon..Sun, 1 = all chores done, 0 = missed, null = future
  var week = { maya: [1, 1, 0, 1, 1, 0, 1], otto: [1, 0, 1, 1, 1, 1, 0] };

  // ---------------------------------------------------------------- shopping
  var stores = [{ id: 'grocer', name: 'FreshCo' }, { id: 'costco', name: 'Costco' }];
  var catOrder = {
    all: ['Produce', 'Bakery', 'Meat & Fish', 'Dairy & Eggs', 'Pantry', 'Frozen', 'Snacks', 'Household'],
    grocer: ['Produce', 'Bakery', 'Meat & Fish', 'Dairy & Eggs', 'Pantry', 'Frozen', 'Snacks', 'Household'],
    costco: ['Household', 'Pantry', 'Snacks', 'Dairy & Eggs', 'Meat & Fish', 'Frozen', 'Produce', 'Bakery']
  };
  var gid = 0;
  function g(name, cat, qty, store, done, note) {
    return { id: 'g' + (++gid), name: name, cat: cat, qty: qty, store: store, done: !!done, note: note || '', ex: true };
  }
  var groceries = [
    g('Bananas', 'Produce', 1, 'grocer', false, 'Bunch, not too ripe'),
    g('Baby spinach', 'Produce', 1, 'grocer'),
    g('Avocados', 'Produce', 3, 'grocer'),
    g('Honeycrisp apples', 'Produce', 6, 'grocer'),
    g('Sourdough loaf', 'Bakery', 1, 'grocer'),
    g('Bagels', 'Bakery', 2, 'costco', false, 'Everything'),
    g('Chicken thighs', 'Meat & Fish', 1, 'grocer', false, 'Boneless'),
    g('Salmon fillets', 'Meat & Fish', 2, 'grocer'),
    g('Milk 2%', 'Dairy & Eggs', 2, 'costco'),
    g('Eggs', 'Dairy & Eggs', 1, 'costco', false, '2 dozen'),
    g('Greek yogurt', 'Dairy & Eggs', 1, 'grocer'),
    g('Aged cheddar', 'Dairy & Eggs', 1, 'grocer'),
    g('Rigatoni', 'Pantry', 2, 'grocer'),
    g('Olive oil', 'Pantry', 1, 'costco'),
    g('Coffee beans', 'Pantry', 1, 'grocer', false, 'Dark roast'),
    g('Frozen peas', 'Frozen', 1, 'grocer'),
    g('Waffles', 'Frozen', 1, 'grocer'),
    g('Goldfish crackers', 'Snacks', 1, 'costco'),
    g('Granola bars', 'Snacks', 1, 'grocer'),
    g('Paper towels', 'Household', 1, 'costco'),
    g('Dish soap', 'Household', 1, 'grocer'),
    g('Lemons', 'Produce', 2, 'grocer', true),
    g('Butter', 'Dairy & Eggs', 1, 'grocer', true),
    g('Tortillas', 'Bakery', 1, 'grocer', true)
  ];
  var catalog = [
    ['Apples', 'Produce'], ['Avocados', 'Produce'], ['Bananas', 'Produce'], ['Baby spinach', 'Produce'], ['Blueberries', 'Produce'],
    ['Broccoli', 'Produce'], ['Carrots', 'Produce'], ['Cucumber', 'Produce'], ['Garlic', 'Produce'], ['Grapes', 'Produce'],
    ['Lemons', 'Produce'], ['Limes', 'Produce'], ['Onions', 'Produce'], ['Potatoes', 'Produce'], ['Strawberries', 'Produce'],
    ['Tomatoes', 'Produce'], ['Bread', 'Bakery'], ['Bagels', 'Bakery'], ['Croissants', 'Bakery'], ['Sourdough loaf', 'Bakery'],
    ['Tortillas', 'Bakery'], ['Hamburger buns', 'Bakery'], ['Bacon', 'Meat & Fish'], ['Chicken breasts', 'Meat & Fish'],
    ['Chicken thighs', 'Meat & Fish'], ['Ground beef', 'Meat & Fish'], ['Salmon fillets', 'Meat & Fish'], ['Shrimp', 'Meat & Fish'],
    ['Butter', 'Dairy & Eggs'], ['Cheddar', 'Dairy & Eggs'], ['Cream cheese', 'Dairy & Eggs'], ['Eggs', 'Dairy & Eggs'],
    ['Greek yogurt', 'Dairy & Eggs'], ['Milk 2%', 'Dairy & Eggs'], ['Oat milk', 'Dairy & Eggs'], ['Parmesan', 'Dairy & Eggs'],
    ['Black beans', 'Pantry'], ['Cereal', 'Pantry'], ['Coffee beans', 'Pantry'], ['Flour', 'Pantry'], ['Honey', 'Pantry'],
    ['Maple syrup', 'Pantry'], ['Olive oil', 'Pantry'], ['Pasta sauce', 'Pantry'], ['Peanut butter', 'Pantry'], ['Rice', 'Pantry'],
    ['Rigatoni', 'Pantry'], ['Spaghetti', 'Pantry'], ['Sugar', 'Pantry'], ['Tea', 'Pantry'], ['Frozen peas', 'Frozen'],
    ['Frozen berries', 'Frozen'], ['Ice cream', 'Frozen'], ['Pizza', 'Frozen'], ['Waffles', 'Frozen'], ['Chips', 'Snacks'],
    ['Crackers', 'Snacks'], ['Dark chocolate', 'Snacks'], ['Goldfish crackers', 'Snacks'], ['Granola bars', 'Snacks'],
    ['Popcorn', 'Snacks'], ['Dish soap', 'Household'], ['Dishwasher pods', 'Household'], ['Garbage bags', 'Household'],
    ['Laundry detergent', 'Household'], ['Paper towels', 'Household'], ['Toilet paper', 'Household'], ['Toothpaste', 'Household']
  ];
  var usuals = ['Milk 2%', 'Eggs', 'Bananas', 'Bread', 'Apples', 'Coffee beans', 'Greek yogurt', 'Cheddar', 'Butter', 'Baby spinach', 'Chicken thighs', 'Paper towels'];

  // ---------------------------------------------------------------- weather (index = hour of day, °C)
  // An example day until a place is chosen in the settings sheet; then js/weather.js fills it from Open-Meteo.
  var weather = {
    example: true,
    hi: 17, lo: 8, feels: -2, humidity: 71, wind: 18,
    t: [9, 9, 8, 8, 8, 8, 9, 10, 11, 12, 13, 15, 16, 17, 16, 15, 14, 13, 12, 12, 11, 10, 10, 9],
    c: ['moon', 'moon', 'moon', 'moon', 'moon', 'moon', 'partly', 'partly', 'sun', 'sun', 'sun', 'partly', 'partly', 'cloud', 'cloud', 'cloud', 'rain', 'rain', 'rain', 'rain', 'cloud', 'cloud', 'moon', 'moon'],
    p: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 10, 20, 25, 40, 80, 90, 70, 55, 20, 10, 0, 0]
  };

  // ---------------------------------------------------------------- photos
  // Example pictures are drawn by App.img (js/system.js) from their seed; the family's own come from their Photos
  // library on the Mac, iPhone or iPad (Sources/Native.swift) with a `src`.
  var t = new Date(base);
  var mmdd = ('0' + (t.getMonth() + 1)).slice(-2) + '-' + ('0' + t.getDate()).slice(-2);
  var photos = [
    { seed: 'tofino-surf', o: 'l', date: '2021-' + mmdd, place: 'Tofino, BC', from: 'jordan', tag: 'tofino', ex: true },
    { seed: 'cottage-dock', o: 'l', date: '2023-08-12', place: 'Lake of Bays', from: 'alex', tag: 'cottage', ex: true },
    { seed: 'maya-kite', o: 'p', date: '2024-05-19', place: 'Humber Bay Park', from: 'jordan', tag: 'spring24', ex: true },
    { seed: 'otto-kite', o: 'p', date: '2024-05-19', place: 'Humber Bay Park', from: 'alex', tag: 'spring24', ex: true },
    { seed: 'autumn-walk', o: 'l', date: '2022-10-09', place: 'High Park', from: 'alex', tag: 'fall22', ex: true },
    { seed: 'birthday-cake', o: 'p', date: '2025-10-12', place: 'Home', from: 'jordan', tag: 'bday25', ex: true },
    { seed: 'candles-lit', o: 'p', date: '2025-10-12', place: 'Home', from: 'alex', tag: 'bday25', ex: true },
    { seed: 'mountain-lake', o: 'l', date: '2019-' + mmdd, place: 'Banff, AB', from: 'alex', tag: 'banff', ex: true },
    { seed: 'snow-day', o: 'l', date: '2024-01-21', place: 'Riverdale Hill', from: 'jordan', tag: 'winter24', ex: true },
    { seed: 'beach-dunes', o: 'l', date: '2023-07-02', place: 'Sandbanks', from: 'maya', tag: 'sandbanks', ex: true },
    { seed: 'city-night', o: 'l', date: '2022-12-18', place: 'Nathan Phillips Sq.', from: 'jordan', tag: 'xmas22', ex: true },
    { seed: 'garden-bloom', o: 'p', date: '2025-06-08', place: 'Backyard', from: 'otto', tag: 'garden', ex: true },
    { seed: 'tomato-haul', o: 'p', date: '2025-06-08', place: 'Backyard', from: 'maya', tag: 'garden', ex: true },
    { seed: 'road-trip', o: 'l', date: '2024-08-04', place: 'Cabot Trail, NS', from: 'alex', tag: 'ns', ex: true },
    { seed: 'campfire', o: 'l', date: '2024-08-06', place: 'Cape Breton', from: 'jordan', tag: 'ns', ex: true },
    { seed: 'forest-path', o: 'l', date: '2020-09-26', place: 'Algonquin', from: 'alex', tag: 'algonquin', ex: true },
    { seed: 'pancakes', o: 'p', date: '2026-03-14', place: 'Home', from: 'maya', tag: 'pancakes', ex: true },
    { seed: 'sugar-shack', o: 'p', date: '2026-03-14', place: 'Sugar Shack', from: 'jordan', tag: 'pancakes', ex: true },
    { seed: 'harbour-sail', o: 'l', date: '2025-07-19', place: 'Toronto Harbour', from: 'otto', tag: 'sail', ex: true },
    { seed: 'pumpkins', o: 'l', date: '2025-10-25', place: "Chudleigh's", from: 'maya', tag: 'fall25', ex: true }
  ];

  // The examples as made, for the sync to tell them from the family's own (js/sync.js).
  var examples = { groceries: groceries.map(function (g) { return Object.assign({}, g); }) };

  var D = {
    examples: examples,
    people: people, family: family, ALL: ALL,
    events: events,
    routines: routines, chores: chores, stars: stars, week: week,
    stores: stores, catOrder: catOrder, groceries: groceries, catalog: catalog, usuals: usuals,
    weather: weather, photos: photos,
    // The settings sheet's choices: the weather's place, the family's own calendars and photos.
    // `example`: this screen was asked to show the example family rather than the welcome.
    settings: { place: null, calendars: null, calendarName: null, calendarsBy: null, album: null, albumBy: null, example: false },
    cleared: false,
    edited: { people: false, chores: false },
    _gid: function () { return 'u' + Date.now().toString(36) + (++gid); },
    _eid: function () { return 'u' + Date.now().toString(36) + (++n); }
  };

  // ---------------------------------------------------------------- saving
  var KEY = 'homehq';
  function dayKey(d) { return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate(); }
  function store() { return window.LampStore || null; }
  function own(e) {
    return { id: e.id, title: e.title, people: e.people, allDay: !!e.allDay, start: +e.start, end: +e.end, loc: e.loc || '', notes: e.notes || '' };
  }

  // Everything the family changed, as parts: saved whole on this device (`save`), and each part shared with the screen's
  // other copies, on the TV, the iPad, the frame (js/sync.js). Only ever add parts or fields here, never rename one,
  // since what's saved is read back by every later version.
  D.snapshot = function () {
    var done = {};
    D.chores.forEach(function (c) { if (c.done) done[c.id] = c.doneBy || true; });
    return {
      cleared: D.cleared,
      events: D.events.filter(function (e) { return !e.ex && !e.cal; }).map(own),
      groceries: D.groceries,
      // The family and the chore list once changed in the editor (js/views/editor.js) or cleared; until then the
      // examples, made afresh each launch.
      people: D.edited.people ? D.people : null,
      chores: D.cleared || D.edited.chores ? D.chores.map(function (c) { return { id: c.id, r: c.r, who: c.who, title: c.title, emoji: c.emoji, stars: c.stars }; }) : null,
      // The day it is now, not the day the page opened: a screen on the wall stays open for days.
      done: { day: dayKey(new Date()), ids: done },
      stars: { stars: D.stars, week: D.week },
      favs: D.photos.filter(function (p) { return p.fav; }).map(function (p) { return p.id || p.seed; }),
      settings: D.settings
    };
  };
  D.save = function () {
    var s = store();
    if (s) s.save(D.snapshot(), KEY);
  };

  // Takes the examples away: events, chores, the shopping list's and the photos. The family stays, for the agent to
  // rename when asked.
  D.clearExamples = function () {
    D.cleared = true;
    D.events = D.events.filter(function (e) { return !e.ex; });
    // A chore list the family changed is theirs, examples and all; a shopping item they changed is theirs too.
    D.chores = D.edited.chores ? D.chores.map(function (c) { delete c.ex; return c; }) : D.chores.filter(function (c) { return !c.ex; });
    var made = {};
    examples.groceries.forEach(function (g) { made[g.id] = JSON.stringify([g.name, g.qty, g.note, g.store, g.cat]); });
    D.groceries = D.groceries.filter(function (g) { return !g.ex || made[g.id] !== JSON.stringify([g.name, g.qty, g.note, g.store, g.cat]); })
      .map(function (g) { delete g.ex; return g; });
    D.photos = D.photos.filter(function (p) { return !p.ex; });
    Object.keys(D.stars).forEach(function (k) { D.stars[k] = 0; });
    Object.keys(D.week).forEach(function (k) { D.week[k] = [0, 0, 0, 0, 0, 0, 0]; });
    D.save();
  };
  D.hasExamples = function () {
    return !D.cleared;
  };
  // Everyone, as an event for the whole family has them: the people, not the pets.
  D.humanIds = function () { return D.people.filter(function (p) { return !p.pet; }).map(function (p) { return p.id; }); };
  // Set up: the first-run setup (js/views/setup.js) was finished, here or on another copy, which took the examples away.
  // Until then the examples show (renamed or not in the editor), behind the welcome unless the person chose to look at
  // them.
  D.isSetUp = function () { return D.cleared; };
  // Something of the family's own: their people or chores changed, their calendar, place or album, an event or a
  // shopping item they added. The examples go then, for good (js/views/setup.js), with no setup to finish first.
  D.ownsSomething = function () {
    var s = D.settings;
    return D.edited.people || D.edited.chores || !!s.calendars || !!s.place || s.album != null ||
      D.events.some(function (e) { return !e.ex && !e.cal; }) || D.groceries.some(function (g) { return !g.ex; });
  };

  // Puts back what a snapshot holds, any of its parts: what this device saved, or a part another copy shared.
  D.restore = function (p) {
    if (p.settings) D.settings = Object.assign(D.settings, p.settings);
    if (p.people && p.people.length) {
      D.people = p.people; D.edited.people = true;
      D.ALL = D.humanIds();
    }
    if (p.cleared && !D.cleared) {
      D.cleared = true;
      D.events = D.events.filter(function (e) { return !e.ex; });
      D.photos = D.photos.filter(function (x) { return !x.ex; });
      if (!p.chores) D.chores = D.chores.filter(function (c) { return !c.ex; });
      if (!p.groceries) D.groceries = D.groceries.filter(function (g) { return !g.ex; });
    }
    if (p.chores) {
      var was = {};
      D.chores.forEach(function (c) { was[c.id] = c; });
      D.chores = p.chores.map(function (c) { var old = was[c.id]; return Object.assign({}, c, { done: old ? old.done : false, doneBy: old && old.doneBy }); });
      D.edited.chores = true;
    }
    if (p.events) {
      D.events = D.events.filter(function (e) { return e.ex || e.cal; }).concat(p.events.map(function (e) {
        return Object.assign({}, e, { start: new Date(e.start), end: new Date(e.end) });
      }));
    }
    if (p.groceries) D.groceries = p.groceries;
    if (p.stars) {
      // Saved before the two went together: { stars } and { week } apart.
      D.stars = p.stars.stars || p.stars;
      if (p.stars.week) D.week = p.stars.week;
    }
    if (p.week) D.week = p.week;
    // Everyone who earns stars has a week to show, a kid added in the editor too.
    D.people.forEach(function (x) { if (x.age && D.stars[x.id] == null) D.stars[x.id] = 0; });
    Object.keys(D.stars).forEach(function (k) { if (!D.week[k]) D.week[k] = [0, 0, 0, 0, 0, 0, 0]; });
    // Chores ticked off today stay ticked; a new day starts them all again.
    if (p.done) {
      var today = p.done.day === dayKey(new Date());
      D.chores.forEach(function (c) {
        var by = today ? p.done.ids[c.id] : null;
        c.done = !!by;
        c.doneBy = typeof by === 'string' ? by : undefined;
      });
    }
    if (p.favs) D.photos.forEach(function (x) { x.fav = p.favs.indexOf(x.id || x.seed) > -1; });
  };

  (function load() {
    var s = store(), saved = s ? s.load(KEY, null) : null;
    if (saved) D.restore(saved);
  })();

  return D;
})();
