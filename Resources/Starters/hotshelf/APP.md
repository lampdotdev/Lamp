Kind: collection
Look: all hot sauce. A shelf of something else gets a mood of its own: see "Making it about something else".

# Hot Shelf

One person's hot sauce collection on lit studio shelves, and the shelf is the whole interface: a deep red set
lit by one light from the upper left, the title big and white in SF Pro Expanded Black, and each flavour family's
name painted big on the wall behind its shelf (fruity, fermented, smoky, garlic, green, chili crisp, sweet,
vinegar-forward), with the bottles standing in front of it, sorted by heat and wrapping onto as many shelves as
the width needs. Finished bottles stand grey on the last shelves with their verdict. Every bottle is a cut-out
photo, and the light is drawn over the whole picture (a dodge and burn that stays put while the shelves scroll),
with each bottle's own highlight, shade and shadow on top, so any photo looks like part of the same shot.

- **A bottle**: its photo, its heat (1–10) and stars (1–10) on the shelf's edge under it, and a click opens a game-style dialog that flies in over the shelf, with the bottle on a sunburst, prev/next arrows and a
  paper card to edit it, rate it, change its label, or retire it with a verdict (typed, quick chips or dictated).
- **Adding one** (⇧⌘N): snap it with the camera (Continuity Camera too), drop, choose or paste a photo. A barcode is
  looked up on Open Food Facts; the AI reads the label and fills in maker, peppers, ingredients, heat, family and a
  cheeky tag.
- **Pictures**: a bottle without a photo gets its real label (Open Food Facts' photo when the AI agrees it's the
  right bottle, else an AI-made product photo), cut out on the Mac. Until then it stands as a plain painted bottle
  with its name on it.
- **What's cooking tonight?**: a bar where the AI picks one bottle for the dish; it lifts off the shelf with a note
  saying why. Also a Shortcuts/Siri action.
- **Nudges**: Friday at 6 pm, a bottle that hasn't left the shelf in a month; every quarter, finished vs bought.

Settings: the person's taste in their own words (used in every AI prompt), and the two nudges.

## Code

- `App.swift`: the window, the Add Bottle… command, the About box with the photo credit, Settings.
- `Model.swift`: `FlavorFamily` (raw values are saved: never rename), `Bottle`, `Pick`, the default taste
  profile, and `Shelf` (the one model: storage, seeding, changes, tonight's pick).
- `Seed.swift`: the example shelf.
- `ShelfView.swift`: the studio wall and its light (`StudioWall`, `StudioLighting`), the shelves and their painted
  names (`ShelfRow`, `StudioShelf`), what's on a shelf's edge (`RailText`), the empty shelf and the delete confirmation.
- `BottleView.swift`: a bottle, its light and shadows (`StudioLight`), its cap band, and the outline on an empty shelf.
- `BottleDialog.swift`: the game-style dialog (`FlyIn`, the sunburst panel). `BottleDetail.swift`: its paper card
  (`PepperRow`, `StarRow`, label options, retiring).
- `AddBottleView.swift`, `Camera.swift`: adding a bottle. `BottleReader.swift`: `BottleStyle` (the painted
  placeholders), `BottleImages` (where pictures are kept), cutting out, the cap's heat band, barcodes, Open Food
  Facts and the AI's reading of a label.
- `LabelFinder.swift`: finding a real label, one bottle at a time.
- `TonightView.swift`, `Nudges.swift`, `Dictation.swift`, `SettingsView.swift`,
  `Intents.swift`.
- `Theme.swift`: `Look`, the whole look of the shelf; `Zine`, the colours the dialogs and sheets still use.
  `Assets/`: the four painted bottle styles, and `Bottles/`, the example bottles' cut-out photos with `credits.txt`
  (Open Food Facts, CC BY-SA; the About box credits them).

## Data

LampStore: the `bottles` collection. Pictures are files in `LampStore.folder/Bottles`, named in a bottle's
`imageName` (its cut-out photo, or `style:<id>` for a painted placeholder). `labelTried` stops the label finder
from looking again.

Example content: on the first launch an empty shelf is filled once (`Shelf.seedIfNeeded`, flag `shelf.seeded` in
UserDefaults) with twenty-three bottles and three finished ones (`Seed.samples`, dates relative to that day). Each comes
with its photo, copied from `Assets/Bottles/<photo>.png` and marked as labelled, so nothing is looked up for
them. Bottles are deleted one at a time, from their dialog.

## Easy to change

- The families and what the AI is told each means: `FlavorFamily`.
- The look: a mood in `Look` (`Theme.swift`), below.
- The tag's wording, the ratings' scale: `BottleView`, `BottleDetail`.
- The nudges: `Nudges.swift`. The default taste: `defaultTasteProfile` in `Model.swift`.
- The example bottles: `Seed.samples` (a new one with no photo in `Assets/Bottles` gets its label looked up like any
  bottle; photos used here need a licence that allows it, credited in `credits.txt` and the About box).

## Making it about something else

The shelf works for anything kept in bottles, jars or tins: wine, whisky, tea, olive oil, perfume. Don't only
recolour it. Decide first what the new subject feels like, then make every choice for that feeling. Hot sauce is
loud and cheeky. Wine and whisky are quiet and elegant. Tea is calm and soft. Records would be graphic and bold.

1. **Write a new mood.** Add a `static let` beside `hotShelf` and `cellar` in `Look` and point `Look.current` at it.
   Write it whole rather than editing `hotShelf`, and set every field for the new feeling:
   - **Shelf names**: `.painted` (big type on the wall behind the bottles) is only for a loud mood. An elegant one
     uses `.caption`.
   - **Type**: wide black capitals are edgy. Elegant is a serif (`design: .serif`) at a regular weight in its own
     case, with small tracked capitals to support it. Calm is a light or regular sans.
   - **Light**: a hard light from a corner with a beam (`beam: 1`, high `contrast`) is dramatic. A soft light from
     above (`light` near the top middle, larger `reach`, `beam: 0`, lower `contrast`) is gentle. `glow` warms it:
     candle or lamplight for a cellar, white for a studio.
   - **Colour**: one colour for the set, with shelves of the same colour or of a material of their own (walnut,
     oak, stone). A dark wall suits a cellar, a pale one a pantry (then set `ink` dark and `scheme: .light`).
   - **Words**: the title, what's measured under each bottle and its symbol (heat and a flame; body and a drop),
     what finished bottles are called, the summary's last part (`mostLine`, or nil), the empty shelf, and the
     question at the foot of the shelf.
   `cellar` is the worked example of a quiet mood.
2. **Change what's still about hot sauce outside the mood**:
   - The families and what the AI is told each means (`FlavorFamily`).
   - The AI's prompts: reading a label and its heat scale (`BottleReader.read`), choosing a family, finding a label
     and the product photo it paints (`LabelFinder`), tonight's pick (`Shelf.pickForTonight`), and the default taste
     (`defaultTasteProfile`).
   - The `heat` field's meaning: it's what's measured. Keep the field and say what it now means.
   - The words in the add sheet and the bottle's card ("Peppers", "Heat"), the nudges (`Nudges.swift`), the Siri
     action (`Intents.swift`) and Settings.
   - The example shelf: replace `Seed.samples`, or clear it so it starts empty. Hot sauce photos have no place on a
     wine shelf: delete `Assets/Bottles` and its credits, and the About box's credit with them.
   - The app's name and icon.

