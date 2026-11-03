---
name: game-physics
description: For a web game at home on the Mac whose fun is things behaving as bodies - they fall, roll, stack, topple, bounce off each other, ride on wheels, swing on joints, or a board tilts under them - with Rapier in 3D, or Phaser's Matter in a flat game. Choose it by the mechanics, not the words: a car that drives on its wheels needs it, stars that fall to be caught don't. Not for steering, simple gravity or checking what touches what: the guide's setup does those.
sections: 3d-game#Physics
---

# Things that behave like things

The web-game guide and game-feel hold; this is the physics a game of bodies needs, with Rapier, which Lamp ships for a
game drawn in 3D. A flat game whose things must tumble, stack or swing on joints uses Phaser's Matter instead
(`physics: { default: 'matter' }` to `phaser()`), with the same reasons for when it's worth it.

{{sections}}
