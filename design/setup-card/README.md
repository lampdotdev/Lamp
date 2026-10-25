# Offering a better setup

Lamp works with whatever it has: a builder's sign-in, a model on this Mac, nothing at all. Some things work
much better, or only work, with something more: an OpenRouter key, a model downloaded to this Mac, a
sign-in. This is how Lamp tells the person so, in the chat and in Settings, and how to add a new case.

## When to offer

Offer when **all** of these hold:

- **Something just mattered.** An app tried to do the thing and couldn't (the gateway's `needs`), Lamp itself
  wanted it (the icon's artwork), or the agent is building a feature that depends on it (`offer_setup`).
  Never offer on launch, on the welcome screen, or because a key is missing in general.
- **It would change what the person gets.** `AppAI.resolve` says `.none` (nothing answers) or `.works` (it
  answers, but not what they chose, or slower and less exact). Never offer at `.best`.
- **They haven't turned it down.** "Not Now" is remembered for every app for Lamp's own offers, and for that
  app for the agent's. Respect it; Settings is where they go when they change their mind.
- **It hasn't been offered in this chat.** One card per capability per app. `Store.offerSetup` checks all of
  this; call it rather than logging a card yourself.

Lamp offers by itself only at `.none`. At `.works` it leaves the offer to the agent, which knows whether the
feature at hand is worth the interruption.

## How it's built

- **One answer to "what answers this?"** `AppAI.resolve(capability, for: app, in: .mac | .phoneAway)`
  returns a `Resolution`: what answers, its `tier`, a `note` on why it isn't the best, and the `upgrades`
  that would make it better, best first. Everything reads it: the gateway, the card, Settings' menus and
  Not Ready rows, an app's info panel, the sharing review, the keys a phone takes away, the agent's status line. Don't work
  out availability anywhere else; add to `resolve`.
- **A new capability** is a case of `Capability` (title and SF Symbol), a branch in `resolve`, the gateway
  tagging its setup failures with `AppAI.Failure(…, needs:)`, a reason in `Store.offerReason`, a title and
  "all set" line in `SetupCard`, and the same name in LampSupport's `LampAI.Capability`.
- **A new way to make something better** is a case of `Upgrade`, a line in `UpgradeView.isOffered` when not
  every Mac can do it, and a row view built from `OptionRow`. The row has a long `detail` for the card and a
  short one for Settings (`compact`).
- **Raising the card:** Lamp's own offers go through `Store.offerSetup(project, SetupOffer(…), because:)`,
  usually from `Store.failed` when the gateway's failure carries `needs`. The agent raises the same card with
  `offer_setup`, which goes to the same function with `fromAgent: true`.
- **The agent's side:** it learns what the app has from `AIStatus.brief`, sent at the end of a request when
  a conversation starts and again only when the answer changes. Its rule is in `Agent.setupRules`: build the
  feature anyway, check `LampAI.isAvailable` in the app, call `offer_setup` once, and never ask for keys in prose.
- **Inside generated apps:** `LampAI.Failure.needsSetup` says what wasn't set up, and
  `LampAI.isAvailable(_:)` lets an app explain a feature instead of failing at it.

## The card

It is built like the build card above it in the chat, so the chat reads as one thing:

- **Header:** a 44pt tile with the capability's symbol on the accent colour (never the app's icon: this is
  Lamp asking, not the app), a headline, a status line under it, and **Not Now** on the right.
- **Body,** under a divider: one row per upgrade, best first. Each row has a symbol, a title, a line of detail,
  and a small standard button on the right ("Add Key…", "Download", "Sign In…", "Open…"). A key is typed in
  place: the row opens a field with Cancel and Save (Return saves), and a link to get one. Progress replaces
  the button while something downloads.
- **States:** offered; *works for now* (a last line says what's filling in); *all set* (the body folds
  away and the status line says what answers now, with a green check); *not now* (the body folds away and
  the status line says where to find it later). The card re-resolves when a key changes
  (`KeyStore.changed`) or a download finishes, so it never needs a refresh.
- **Settings** uses the same rows with `compact: true`: shorter detail, and a key opens its provider's sheet
  rather than a field. An upgrade every capability wants is offered once, under them all. Orange is only for
  `.none`; a `.works` note is secondary text, since nothing is broken.

## The copy

Write for someone who has never heard of OpenRouter, a model or a key. Every line should leave them knowing
what happened, what each option is, and what it costs.

- **Headline:** what they'd be able to do, as a verb: "Make pictures with AI", "Use AI in your apps", "Let
  your apps make quick judgments". Not the name of a provider or a setting.
- **Status line (the reason):** what just happened and what to do, in two sentences, naming the app: "Recipe
  Box just tried to make a picture, but nothing on this Mac can draw yet. Set up one of the ways below and it
  will work the next time." The agent's reason names the feature: "Recipe Box can draw a picture of each dish."
- **Each option:** the title says the action ("Add an OpenRouter key", "Download a picture model to this
  Mac"). The detail explains the thing and its cost in plain words: what OpenRouter is, that a download is
  free and private and how big it is, that a sign-in uses a plan they already have.
- **Say what's true now.** "All set. Pictures are now made by FLUX.2 klein 4B on this Mac." "No problem. You
  can set this up any time in Lamp's Settings, under AI Providers."
- **Don't:** use "provider", "route", "endpoint", "API" (except a product's own name for it), "LLM",
  "inference"; blame the person; say "just" about anything they have to do; repeat in the status line what a
  row already says.
- **Keep it short in Settings,** where the person went on purpose and the menus already say what answers. Settings speaks only when nothing answers (see `docs/development/interface.md`).
