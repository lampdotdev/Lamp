# Lamp docs

Lamp's public documentation, meant for [docs.lamp.dev](https://docs.lamp.dev). It is a self-contained
[Mintlify](https://mintlify.com) workspace: the pages, navigation, branding and assets all live in this
folder.

## Structure

- `docs.json`: navigation, theme, colours and logo.
- `*.mdx`: the pages. Each is listed by its file name (without the extension) in `docs.json`. `icon` in a
  page's frontmatter is a Lucide icon name, shown beside the page in the sidebar.
- `lamp.css`: small styling touches. Mintlify loads CSS placed at the root of the workspace by itself.
- `logo/`: the light and dark logos for the navbar (the app icon beside the name).
- `favicon.png`: the app icon, scaled down from `Resources/AppIcon.png`.

## Local preview

The scripts download a pinned Mintlify CLI, so nothing needs installing globally (Node 20.17 or later).

```bash
cd docs
npm run dev      # preview at http://localhost:3000
npm run check    # what CI runs: validate, then look for broken links
```

`.github/workflows/docs.yml` runs `npm run check` on every pull request that touches this folder.

## Who this is for

People who use Lamp, most of whom have never built software. See [`AGENTS.md`](./AGENTS.md) for what
belongs here and how to write it.
