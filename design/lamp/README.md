# Lamp: onboarding artwork

The onboarding backdrop is now rendered offline in Blender Cycles. The app plays a camera move between
steps and pauses at each composition. It has no idle camera drift. `LampModel.swift` retains only the procedural geometry needed for export.
SceneKit tessellates that geometry during authoring; it is not used to render the app's backdrop.

The treatment is glazed white ceramic, a seamless warm-white page, large softboxes, diffuse bounced
light, and a shallow physical depth of field. The lid is the focus of the first two views; the handle is
the focus of the last. A narrow reflection strip makes the clear glaze readable during camera moves;
the material has no metallic component. The white ground remains in the scene for bounced light but is hidden from camera.
The transparent render is composited onto the same near-white page color (`#fefdfc`) used by the interface.
Keep that color in sync in `encode-onboarding.py` and `LampBackdrop.page`. Onboarding uses a fixed
1080 × 660 window, with the film filling its bounds and a 42.5%-opaque readability wash on later steps.

## Rebuild the artwork

Requires Blender (tested with 5.2.2 on Apple Silicon), Swift, Python 3, and FFmpeg with libx265 and zscale.
Blender and FFmpeg are only authoring dependencies; ordinary Lamp builds use the checked-in assets.

```bash
bash design/lamp/render.sh
```

This exports the lamp with every primitive's transform baked, renders 97 frames into
`build/onboarding/final`, and writes `Resources/Onboarding/onboarding.mp4` plus three resting PNGs.
The saved `build/onboarding/final/onboarding.blend` can also be opened directly in Blender for inspection.
Change the geometry in `LampModel.swift`, and lighting, material, framing, or focus in
`render-onboarding.py`. Set `BLENDER_BIN` if Blender is installed elsewhere.

The movie is 2160 × 1520 at 30 fps, encoded as 10-bit HEVC with explicit Rec. 709 color metadata.
Frames 0, 48, and 96 are the three steps; frames 97–192 return through the same views in reverse.
Each move lasts 1.6 seconds. Keep these positions in sync with `LampFilmView` when changing the timing.
The stills are decoded from the finished video and converted back to sRGB to match playback.
They cover initial loading, restored setup, Reduce Motion, and rapid navigation.

For a quick lighting check, run the export first, then:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python design/lamp/render-onboarding.py -- \
  --model build/onboarding/lamp.obj --output build/onboarding/preview --width 1080 --samples 64
```

## Preview and verify playback

The isolated harness uses the production backdrop without opening Lamp's store, signing in, installing
tools, or touching generated apps. It has Back and Continue controls and a resizable window.
Both the app and harness follow macOS Reduce Motion: each step cuts directly to its resting frame.

```bash
bash design/lamp/preview.sh
bash design/lamp/preview.sh --verify
```

The automatic checks cover startup, all four adjacent transitions, pausing at each step, rapid navigation,
Reduce Motion (including enabling it during a move), resizing, restored setup, and releasing the player
on teardown. The film uses aspect-fill when resized; unlike the original scene, its composition does not
change with window shape.
