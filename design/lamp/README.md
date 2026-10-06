# Lamp: welcome exploration

An exploration of rebranding Lamp as **Lamp** ("wish software into existence"), starting with the welcome.
Nothing here is wired into the app yet.

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

`Icon.swift` makes the app icon from the same lamp, with golden smoke on its own layer:
`.build/debug/LampLab icon out ../../../Resources` (from this folder) writes the Icon Composer document and
replaces the app's icon files; copy `out/AppIcon.icon` to `Resources/Icon/` too.

`Scene3D.swift` and `Welcome.swift` are the earlier gold version (lamp, smoke, and the apps as blocks rising
out of it, reflected in the gold), kept for reference: `.build/debug/LampLab still out` and `video out`.
