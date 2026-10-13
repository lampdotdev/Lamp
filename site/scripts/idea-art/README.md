# The ideas page's pictures

Each wish on `/ideas` has an icon and a picture of it in use, in `src/assets/ideas/` (`icons/<slug>.png`,
`thumbs/<slug>.jpg`, the slug made from the idea's name by `slug` in `src/lib/ideas.ts`). They're drawn by an
image model, through Codex signed in with ChatGPT, from a line in `briefs.txt`:

```
Name|the icon's object|the icon's background|what the picture shows
```

- **The icon** is drawn as Lamp draws an app's: one object on a plain background (the request is
  `Icons.artPrompt`'s), cut out and put on Lamp's own tile (`tile.swift` does what `Icons.drawnTile` does, with
  its gradients), so the icons look like the ones Lamp makes. The background is one of `Icons.backgrounds`.
- **The picture** is framed by where the idea lives: a Mac window, a menu bar panel, a desktop widget, an iPhone
  or iPad, or, for a game, the game itself (`prompts.py`). Keep what it shows short and concrete: a few labels
  and the one thing that makes the idea what it is.

`run.sh` draws whatever isn't drawn yet, eight at a time, and `finish.sh` puts the results in place without
replacing pictures that are already there. To add an idea, add its line to `briefs.txt` and run `run.sh`; to
redraw one, delete its files in `src/assets/ideas/` and `.work/raw/`, and run it again. An idea without
pictures still shows on the page, without them.
