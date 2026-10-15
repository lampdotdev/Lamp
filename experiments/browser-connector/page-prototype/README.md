# Prototype: the sidebar as a page Lamp serves

An exploration, not part of the connector. The side panel stays the extension's own page (`panel.html`), but
most of it is an iframe of a page served on this Mac, so an app could draw its sidebar with its own HTML, CSS
and JavaScript instead of the data the real extension draws.

- `serve.py` stands in for Lamp: it serves one app's page at `http://recipe-box.localhost:47123/`, answers
  only that host name, and allows only this extension to frame it (`frame-ancestors`).
- The panel keeps the app's name, the consent line and the message shown when nothing answers, and frames
  the page sandboxed without popups or top navigation.
- The page has no extension APIs. It asks the panel for the page's text by `postMessage`; the panel checks
  the message's source and origin and reads only while it has a fresh click (a click inside the frame counts),
  with the access the click on the toolbar icon gave.

Try it: `python3 -I serve.py`, load `extension/` unpacked, open a website, click the extension's icon.
