Kind: collection
Look: all hot sauce, so a shelf of something else gets a look of its own. The pink wall with crayon grain and
scattered chilies (`ShelfView`, `Assets/chili.png`), the warm reds and navy lines (`Zine` in `Theme.swift`), the
drawing style every label is redrawn in (`Illustrator.style`, which names hot sauce; bump `version`), the painted
placeholder bottles (`Assets/`), heat as peppers and the cap's heat band, the flavour families, "What's cooking
tonight?", the cheeky tags and the hot sauce bottle icon.

# Hot Shelf

One person's hot sauce collection as an illustrated shelf, like a food illustrator's print, and the shelf is the
whole interface: a flat pink wall with crayon grain and scattered chilies, a hand-lettered title, and chunky flat
planks with navy outlines. Bottles stand on planks by flavour family (fruity, fermented, smoky, garlic, green,
chili crisp, sweet, vinegar-forward), wrapping onto as many planks as the width needs and sorted by heat; finished
bottles stand grey on the last planks with a verdict. Everything is drawn in one style: gouache and crayon, navy
pencil lines, a white sticker border.

- **A bottle**: its drawing, a hanging tag with its ratings (heat as 1–10 peppers, liking as 1–10 stars), and a
  click opens a game-style dialog that flies in over the shelf, with the bottle on a sunburst, prev/next arrows and a
  paper card to edit it, rate it, change its label, or retire it with a verdict (typed, quick chips or dictated).
- **Adding one** (⇧⌘N): snap it with the camera (Continuity Camera too), drop, choose or paste a photo. A barcode is
  looked up on Open Food Facts; the AI reads the label and fills in maker, peppers, ingredients, heat, family and a
  cheeky tag.
- **Pictures**: a bottle without a photo gets its real label (Open Food Facts' photo when the AI agrees it's the
  right bottle, else an AI-painted likeness), and every label is then redrawn in the shelf's style
  (`LampAI.editImage`) and cut out on the Mac. Until then it stands as a plain painted bottle with its name
  handwritten.
- **What's cooking tonight?**: a bar where the AI picks one bottle for the dish; it lifts off the shelf with a note
  saying why. Also a Shortcuts/Siri action.
- **Taste map** (⇧⌘T): an AI summary of the person's taste from their ratings, favourites, and one to three gaps,
  which also stand on the shelf as ghost bottles.
- **Nudges**: Friday at 6 pm, a bottle that hasn't left the shelf in a month; every quarter, finished vs bought.

Settings: the person's taste in their own words (used in every AI prompt), and the two nudges.

## Code

- `App.swift`: the window, Add Bottle… and Taste Map commands, Settings.
- `Model.swift`: `FlavorFamily` (raw values are saved: never rename), `Bottle`, `TasteMap`, `Pick`, the default taste
  profile, and `Shelf` (the one model: storage, seeding, changes, tonight's pick, the taste map).
- `Seed.swift`: the example shelf and its taste map.
- `ShelfView.swift`: the wall, planks, rows, ghost bottles, the empty shelf and the delete confirmation.
- `BottleView.swift`: a bottle, its cap band and its hanging tag.
- `BottleDialog.swift`: the game-style dialog (`FlyIn`, the sunburst panel). `BottleDetail.swift`: its paper card
  (`PepperRow`, `StarRow`, label options, retiring).
- `AddBottleView.swift`, `Camera.swift`: adding a bottle. `BottleReader.swift`: `BottleStyle` (the painted
  placeholders), `BottleImages` (where pictures are kept), cutting out, the cap's heat band, barcodes, Open Food
  Facts and the AI's reading of a label.
- `LabelFinder.swift`: finding a real label, one bottle at a time. `Illustrator.swift`: redrawing labels in the
  shelf's style (`style`, `version`), two at a time.
- `TonightView.swift`, `TasteMapView.swift`, `Nudges.swift`, `Dictation.swift`, `SettingsView.swift`,
  `Intents.swift`.
- `Theme.swift`: the colours. `Assets/`: the chili on the wall, the four painted bottle styles, and `Bottles/`, the
  example bottles' drawings.

## Data

LampStore: the `bottles` collection and the `taste` value. Pictures are files in `LampStore.folder/Bottles`, named
in a bottle's `imageName` (its photo, or `style:<id>` for a painted placeholder) and `artName` (its drawing, made in
`Illustrator.version` `artStyle`). `labelTried` stops the label finder from looking again; bumping
`Illustrator.version` redraws every bottle.

Example content: on the first launch an empty shelf is filled once (`Shelf.seedIfNeeded`, flag `shelf.seeded` in
UserDefaults) with eighteen bottles and three retired ones (`Seed.samples`, dates relative to that day). Each comes
with its drawing, copied from `Assets/Bottles/<name as a slug>.png`, already marked as labelled and drawn, so
nothing is looked up or drawn for them; the taste map is saved with it, marked as made for that shelf, so the AI
writes a new one only once the shelf or the taste changes. Bottles are deleted one at a time, from their dialog.

## Easy to change

- The families and what the AI is told each means: `FlavorFamily`.
- The drawing style: `Illustrator.style` (bump `version` to redraw everything).
- The wall, planks and colours: `ShelfView` and `Theme.swift`.
- The tag's wording, the ratings' scale: `BottleView`, `BottleDetail`.
- The nudges: `Nudges.swift`. The default taste: `defaultTasteProfile` in `Model.swift`.
- The example bottles: `Seed.samples` (a new one with no drawing in `Assets/Bottles` gets its label looked up and
  drawn like any bottle).
