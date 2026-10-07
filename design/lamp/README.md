# Lamp: onboarding artwork

The onboarding backdrop is now rendered offline in Blender Cycles. The app plays a camera move between
steps and pauses at each composition. It has no idle camera drift. The original SceneKit scene is kept
in `SceneKitBackdrop.swift` as the editable procedural geometry source; it is no longer part of the app.

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
Change the geometry in `SceneKitBackdrop.swift`, and lighting, material, framing, or focus in
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

## Earlier SceneKit exploration

An exploration of rebranding Lamp as **Lamp** ("wish software into existence"), starting with the welcome.
The screenshots and tour below record the earlier SceneKit treatment.

The direction settled on: a detailed white porcelain lamp on a white page, shown only by soft light and
shadow, in a different cropped framing for each welcome step. The camera circles to the next framing when
the step changes, and drifts slowly back while a step is showing.

- `welcome-tour.mp4`: the three steps with the camera moving between them.
- `step0.png`, `step1.png`, `step2.png`: each step's framing under stand-in content.
- `antialiasing-before-after.png`, `spout-closeup.png`: why the lamp is rendered at twice the size and scaled down.

## LampLab

The harness that renders these. The lamp is modelled in code (`Lamp.swift`, from the helpers in `Mesh.swift`),
so there's no model file to license or ship. `Clay.swift` has the lighting, the framings and the camera
movement; `Steps.swift` is the stand-in content.

```bash
cd design/lamp/LampLab
swift build
.build/debug/LampLab steps out   # a still per step
.build/debug/LampLab tour out    # frames for the video, in out/tour
ffmpeg -framerate 30 -i out/tour/%04d.png -c:v libx264 -pix_fmt yuv420p -crf 16 out/tour.mp4
```

`Icon.swift` made an earlier app icon from the same lamp, with golden smoke on its own layer. The app no
longer uses it: its icon is now a painted lamp at sunset (`Resources/Icon/`), and running
`.build/debug/LampLab icon out ../../../Resources` would replace that with the porcelain one.

`Scene3D.swift` and `Welcome.swift` are the earlier gold version (lamp, smoke, and the apps as blocks rising
out of it, reflected in the gold), kept for reference: `.build/debug/LampLab still out` and `video out`.
