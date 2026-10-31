# Writes .work/jobs.json: one image to draw per line, an icon and a picture for each idea in briefs.txt, the picture
# framed by where the idea lives (its form in src/lib/ideas.ts, listed in .work/forms.txt by run.sh).
import json, re, os
here = os.path.dirname(os.path.abspath(__file__))
work = os.path.join(here, ".work")
forms = dict(line.split("|")[1:3] for line in open(os.path.join(work, "forms.txt")).read().splitlines())
pastel = {"blue": "sky blue", "indigo": "lavender", "purple": "lilac", "pink": "rose", "red": "coral", "orange": "apricot",
          "yellow": "butter yellow", "green": "mint", "teal": "aqua", "graphite": "cool gray", "white": "pearl gray"}
def slug(n): return re.sub(r"[^a-z0-9]+", "-", n.lower()).strip("-")
common = ("Landscape 3:2. The picture fills the whole frame. Any words on screen are a few short, correctly spelt labels in English; "
          "no long paragraphs, no lorem ipsum, no real brand names or logos, no watermark.")
jobs = []
for line in open(os.path.join(here, "briefs.txt")).read().splitlines():
    name, subject, bg, screen = line.split("|")
    form = forms[name]; tint = pastel[bg]; s = slug(name)
    # The icon's object alone, as Lamp asks for one (Icons.artPrompt), to go on Lamp's tile.
    icon = (f"A single {subject}, drawn as the object for a macOS app icon in Apple's own icon style: one tangible object with a simple, "
            f"instantly recognizable silhouette, smooth rounded forms, subtle soft gradients and gentle light from above, front or slight "
            f"three-quarter view. Two or three colors at most, chosen to stand out against a {bg} background. The object alone, centered, "
            f"filling about 70% of the frame, on a plain flat light gray background. No scene, no ground, no cast shadow, no background "
            f"elements, no text, no letters, no border, no frame, no rounded square tile, no app icon shape. Square 1:1.")
    if form == "Mac":
        thumb = (f"A clean, realistic screenshot of one macOS app window in light mode, floating with a soft shadow in front of a softly "
                 f"blurred {tint} gradient wallpaper. The window shows {screen}. Native macOS design: SF Pro type, a sidebar or toolbar "
                 f"where it fits, generous white space, calm colors.")
    elif form == "Menu bar":
        thumb = (f"A clean, realistic close-up of the top right of a macOS desktop in light mode: the translucent menu bar along the top "
                 f"edge with one small app icon highlighted, and a rounded frosted panel open just beneath it, showing {screen}. "
                 f"Softly blurred {tint} gradient wallpaper behind. Native macOS design, SF Pro type.")
    elif form == "Widget":
        thumb = (f"A clean, realistic close-up of a macOS desktop in light mode with a softly blurred {tint} gradient wallpaper, and on it "
                 f"{screen}. Native macOS widget design: rounded corners, SF Pro type.")
    elif form == "iPhone":
        thumb = (f"A clean, realistic product shot of a modern iPhone standing upright in the center, front view, on a plain soft {tint} "
                 f"background, its screen showing an iOS app: {screen}. Native iOS design, SF Pro type, light mode.")
    elif form == "iPad":
        thumb = (f"A clean, realistic product shot of a modern iPad in landscape, front view, on a plain soft {tint} background, its screen "
                 f"showing an iPadOS app: {screen}. Native iPadOS design, SF Pro type, light mode.")
    else:
        thumb = f"A polished, charming, colorful picture of a game: {screen}. Soft {tint} tones in the palette."
    jobs.append({"slug": s, "kind": "icon", "prompt": icon})
    jobs.append({"slug": s, "kind": "thumb", "prompt": thumb + " " + common})
# Each category's own picture for the page's row of categories: an object like an icon's, shown off its tile.
for line in open(os.path.join(here, "categories.txt")).read().splitlines():
    id, subject = line.split("|")
    jobs.append({"slug": f"category-{id}", "kind": "icon", "prompt": (
        f"A single {subject}, drawn as the object for a macOS app icon in Apple's own icon style: one tangible object with a "
        f"simple, instantly recognizable silhouette, smooth rounded forms, subtle soft gradients and gentle light from above, "
        f"front or slight three-quarter view. Two or three colors at most. The object alone, centered, filling about 70% of the "
        f"frame, on a plain flat light gray background. No scene, no ground, no cast shadow, no background elements, no text, "
        f"no letters, no border, no frame, no rounded square tile, no app icon shape. Square 1:1.")})
json.dump(jobs, open(os.path.join(work, "jobs.json"), "w"), indent=1)
