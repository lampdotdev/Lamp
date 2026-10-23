---
name: games-2d
description: 2D games with SpriteKit - scenes, movement and collisions, sprites from make_art, the camera, keys and touches, SwiftUI over the game, keeping every frame smooth, and looking at motion. Read before writing or changing a 2D game.
---

# 2D games

- SpriteKit, in a SpriteView, one SKScene subclass for each screen with `scaleMode = .resizeFill`.
- Movement in `update(_:)` scaled by the time since the last frame; collisions with SKPhysicsBody, its category and
  contact masks, and an SKPhysicsContactDelegate.
- Sprites are `make_art` pictures on a transparent background, loaded as SKTexture; an SKCameraNode follows the player
  through a world bigger than the screen.
- Keys come from `NSEvent.addLocalMonitorForEvents` on the Mac, touches on iPhone.
- Score, pause and menus are SwiftUI over the SpriteView.
- Keep it smooth: nothing that runs during play may take longer than a frame (about 16 ms), so load each texture once
  and reuse it, reuse nodes for things that come and go (bullets, enemies, particles) rather than making new ones each
  time, and prepare a level before it starts.
- After changing anything that moves, look_at_app with `motion` shows what changes frame to frame and catches flicker
  that a single picture hides.
