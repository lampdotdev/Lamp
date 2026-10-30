---
name: android-design
description: How a good Android app looks and behaves - Material 3 theme and color roles, layouts for phones, foldables and tablets, navigation and predictive back, which component for which job, empty, loading and error states, motion and accessibility. Read before designing or restyling an Android app's screens.
---

# Designing an Android app

The person should feel they're holding an app Google might have made: calm surfaces, one accent, rounded shapes, big
readable type, and everything where Android people expect it. It's Jetpack Compose with Material 3 (version 1.4 in
these apps). Everything below compiles with the libraries already in app/build.gradle.kts.

## Theme

- Keep the scaffold's `AppTheme`: dynamic color from the wallpaper on Android 12 and later, and a scheme of your own
  before that. Make that scheme from the app's one accent: `lightColorScheme(primary = …, primaryContainer = …,
  secondary = …, tertiary = …)` and its dark twin, each container a lighter (light theme) or deeper (dark theme) tone
  of its color, with its `on…` color legible on it.
- Color by role, never by hex in a screen: `primary` for the one most important action, `primaryContainer` and
  `secondaryContainer` for things to stand out softly (a selected card, a highlighted number), `tertiaryContainer` for
  a contrasting accent, `surface` with `surfaceContainerLow` … `surfaceContainerHighest` for layers (a card on a page
  is one step higher than the page), `onSurfaceVariant` for secondary text, `outlineVariant` for dividers, `error` and
  `errorContainer` for problems. A color that isn't a role (a category's own color, a chart's series) still gets a
  light and a dark value.
- Type from `MaterialTheme.typography` only: `displayLarge`/`displayMedium` for a hero number or a timer,
  `headlineSmall`…`headlineLarge` for a screen's big title, `titleMedium`/`titleLarge` for a card's or a list item's
  title, `bodyLarge` for reading, `bodyMedium` for supporting text, `labelLarge` for buttons and `labelMedium`/
  `labelSmall` for chips and captions. A number that changes uses `fontFeatureSettings = "tnum"` so it doesn't jiggle.
  Sizes are in sp, so the person's font size applies.
- Shapes from `MaterialTheme.shapes`: `extraLarge` (28 dp) for a hero card or a sheet, `large` for cards, `medium`
  for smaller containers, `small` for chips and fields, `CircleShape` for avatars and icon buttons. Current Android is
  generous with roundness and size: a big rounded card with a large number in it reads better than a dense table.

## Edge to edge and insets

- The app draws behind the status and navigation bars (`enableEdgeToEdge()` in MainActivity). `Scaffold` hands its
  content the padding that keeps it clear of them and of its own bars: pass it on, and for a list give it as
  `contentPadding` (`LazyColumn(contentPadding = innerPadding)`), so the list scrolls under the bars and its last item
  ends above the gesture bar rather than being cut off.
- A text field near the bottom needs `Modifier.imePadding()` (or the Scaffold's `contentWindowInsets`) so the keyboard
  doesn't cover it. A screen without a Scaffold uses `Modifier.safeDrawingPadding()`.
- A game or a full-screen viewer can hide the system bars with `WindowCompat.getInsetsController(window,
  window.decorView).hide(WindowInsetsCompat.Type.systemBars())`, with `systemBarsBehavior =
  BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`; nothing else should.

## Every screen size

Phones, foldables and tablets run the same app, and the window can be resized. Choose the layout by the width the app
has, read at the top of the screen with `BoxWithConstraints` (no extra library): under 600 dp is compact (a phone held
upright), 600 to 840 medium (a foldable open, a small tablet, a phone on its side), 840 and over expanded.

- Compact: one pane, a bottom `NavigationBar` for three to five top-level destinations.
- Medium and expanded: a `NavigationRail` at the start edge in place of the bottom bar, and a list beside its detail
  (the list about 360 dp wide, the detail filling the rest) where a phone would go from one to the other. Selecting
  in the list changes the pane beside it, not the screen.
- Content never stretches across a wide window: reading text and forms stay within about 640 dp, centered or beside
  something else. Grids use `LazyVerticalGrid(GridCells.Adaptive(minSize = 160.dp))` so columns follow the width.
- Never lock the orientation, and don't assume the window is the screen.

## Navigation and back

- Screens are destinations in Navigation 3: each a `@Serializable` class or object implementing `NavKey`, the stack
  `rememberNavBackStack(Home)` (it survives Lamp's reopen and Android's), and `NavDisplay` showing its top with an
  `entryProvider`. Going to a screen adds to the stack; back removes from it.
- Back is the system's gesture, with its predictive preview of where it leads (on by default for these apps): let
  `NavDisplay` handle it. Use `BackHandler` only to close something on the screen itself (a search, a selection, a
  sheet's own state), never to ask "are you sure you want to leave?".
- Top-level destinations (the bottom bar's) don't stack on each other: switching to one replaces the stack's root, and
  each keeps its own scroll position.
- The top app bar: `CenterAlignedTopAppBar` or `TopAppBar` for an ordinary screen; `LargeTopAppBar` with
  `TopAppBarDefaults.exitUntilCollapsedScrollBehavior()` for a collection's home, whose big title shrinks into the bar
  as the list scrolls (connect it with `Modifier.nestedScroll(scrollBehavior.nestedScrollConnection)`). An up arrow
  (`Icons.AutoMirrored.Rounded.ArrowBack`) only on screens below the top level. At most two or three action icons;
  the rest in an overflow menu (`DropdownMenu` from `Icons.Rounded.MoreVert`).

## The right component for the job

- The one main thing to create: a `FloatingActionButton`, or `ExtendedFloatingActionButton` with a word when the icon
  alone isn't obvious, shrinking to its icon as the list scrolls (`expanded = !listState.canScrollBackward`). One per
  screen, and none on a screen whose job is reading.
- Rows of things: `ListItem` (headline, supporting text, a leading icon, avatar or picture, a trailing value, switch or
  chevron) in a `LazyColumn`, with `HorizontalDivider` only where items run together. Cards (`Card`, `ElevatedCard`,
  `OutlinedCard`) for things that are each a little page (a recipe, a place), not for every row.
- Choosing: `FilterChip`s in a scrolling row for filters, `SingleChoiceSegmentedButtonRow` for two to five views of the
  same thing, `Switch` for on and off (in a `ListItem`'s trailing slot for settings), `RadioButton`s or a menu
  (`ExposedDropdownMenuBox`) for one of many, `Slider` for an amount, `DatePickerDialog` and `TimePicker` for when.
- Searching: a `SearchBar` at the top of a collection, or a search action that opens one.
- More about one thing, or a few actions on it: a `ModalBottomSheet`. A dialog (`AlertDialog`) only for a choice that
  can't wait or can't be undone.
- After deleting or archiving: do it at once and offer Undo in a `Snackbar` (`SnackbarHost` in the Scaffold), rather
  than asking first. Lists can delete or archive with a swipe (`SwipeToDismissBox`), with the same Undo.
- Content fetched from the network or the AI: `PullToRefreshBox` around the list.
- Icons from `Icons.Rounded` throughout (one style per app), `Icons.AutoMirrored.Rounded` for ones with a direction.
- `TopAppBar`, the search bar, bottom sheets, date and time pickers, `SwipeToDismissBox`, `PullToRefreshBox` and
  `ExposedDropdownMenuBox` need `@OptIn(ExperimentalMaterial3Api::class)`: put `@file:OptIn(ExperimentalMaterial3Api::class)`
  at the top of a file that uses them.
- Not in this version of Material, so don't reach for them: `MaterialExpressiveTheme`, `LoadingIndicator`,
  `ButtonGroup`, `FloatingToolbar`, `SplitButton`, `FloatingActionButtonMenu`, `NavigationSuiteScaffold` and the
  adaptive list-detail scaffolds. The layouts above do their jobs with what's here.

## Every state

Design each screen in every state it can be in, since the person will see all of them:

- Empty: an icon (48 to 64 dp, `onSurfaceVariant`), a short headline, one sentence and the one action that fills it,
  centered in the space. Not a blank list.
- Loading: a `CircularProgressIndicator` in the space the content will take, or a `LinearProgressIndicator` under the
  top bar while what's on screen is refreshed; for a list, a few placeholder rows in `surfaceContainerHigh` shapes
  reads calmer than a spinner. An AI call shows what it's doing ("Writing a summary…"), and its result arrives with
  a fade.
- Failed: say what went wrong in plain words and offer Try Again, in place of the content; a failure of something in
  the background is a Snackbar.
- Lots: long names wrap or end in an ellipsis (`maxLines`, `overflow = TextOverflow.Ellipsis`), and a list of
  thousands is still a `LazyColumn` with `key = { it.id }`.
- Big text: at the largest font size (twice the default) nothing overlaps or is cut off; rows grow taller, and a row of
  buttons wraps (`FlowRow`).
- Dark: everything by role, so it follows the system; check that a picture or a custom color still reads.

## Motion

Motion says where something came from and where it went, quickly and with a little spring.

- Appearing and disappearing: `AnimatedVisibility` (fade with expand or slide), `AnimatedContent` or `Crossfade`
  when one thing becomes another, `Modifier.animateContentSize()` when something grows.
- Lists: `Modifier.animateItem()` on each item, so adding, removing and reordering move rather than jump.
- Values: `animateFloatAsState`, `animateColorAsState` and friends with `spring(dampingRatio =
  Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow)` for things the person touched,
  `tween(200 to 300 ms)` for fades.
- Feel: `LocalHapticFeedback.current.performHapticFeedback(HapticFeedbackType.LongPress)` on a long press, a toggle
  or a completed drag; not on every tap.

## Touch and accessibility

- Every touch target at least 48 by 48 dp (an `IconButton` already is), with 8 dp between neighbors.
- Icon-only buttons have a `contentDescription` saying what they do ("Delete note"), decorative images `null`.
  Headings are marked `Modifier.semantics { heading() }`; a row that's one thing to tap is one element
  (`Modifier.clickable` on the row, `mergeDescendants`).
- Text contrast at least 4.5 to 1 on its background (the `on…` roles are), and never color alone to say something:
  pair it with an icon or a word.

## Games

A game draws itself: a `Canvas` filling the screen, its loop in `LaunchedEffect` with `withFrameNanos`, input from
`pointerInput` (`detectTapGestures`, `detectDragGestures`). Material's controls are for its menus and score screen
only. Hide the system bars while playing, keep the game's state in a class the Canvas reads, and save the score and
progress with LampStore.

A game has sound: a short effect (under a second) for each thing the player does or meets, from `SoundPool` with each
sound loaded once (files in `app/src/main/res/raw`, .ogg or .wav, or what the `assets` tool brought into
`app/src/main/assets`, opened with `context.assets.openFd("<pack>/<file>")`), and music only when it suits, quiet (0.3
to 0.4) under effects at 0.6 to 0.8, from a `MediaPlayer` with `isLooping`. With no sound files, make the effects in code: a
few hundredths of a second of a wave written into an `AudioTrack` (`MODE_STATIC`), with soft ends so it doesn't click.
Pause the music when the activity stops and release both when it's destroyed. Its settings turn sound and music on and
off, kept with LampStore. The emulator plays it on the Mac's speakers.

## Checking it

Look at each screen with `look_at_app` as you build it, with real-looking content in it (several items, long and short
names) and empty. Compare against the list above: the bars clear of the system's, one accent, roles not hex, the
type scale, nothing smaller than 48 dp to tap, and every state designed.
