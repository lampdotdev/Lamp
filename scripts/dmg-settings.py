# The DMG's window, for dmgbuild (release.sh): Lamp on the left, Applications on the right, and the night sky
# with an arrow between them behind. dmgbuild writes the window's layout itself instead of asking Finder, so
# it works the same on a CI runner. Positions and the window size must match scripts/dmg-background.swift.
#
#   dmgbuild -s scripts/dmg-settings.py -D app=dist/Lamp.app -D background=Resources/DMG/background.tiff Lamp dist/Lamp.dmg
#
# dmgbuild doesn't tell a settings file where it is, so the paths come in as defines.
import os

app = defines["app"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {os.path.basename(app): (180, 190), "Applications": (480, 190)}

background = defines["background"]
window_rect = ((200, 200), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
