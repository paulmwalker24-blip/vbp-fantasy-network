# vbp-fantasy-network

A static site for the VBP Fantasy Network: league discovery, constitutions, and public format centers.

## Layout

- `index.html` plus the root `*-constitution.html` and `*-center.html` pages stay at the repo root so their public URLs remain simple and stable.
- `assets/css/` holds shared frontend styling.
- `assets/js/` holds the homepage and center-page client logic.
- `assets/images/` holds banners, aligned format artwork, and social thumbnails.
- `assets/reference/` holds non-wired reference files that should not clutter the live app surface.
- `data/`, `docs/`, `marketing/`, and `scripts/` keep commissioner data, process notes, reusable copy, and local automation separated from the web assets.

## Daily Navigation

- Website and league work: `docs/todo-website-leagues.md`
- Discord work: `docs/todo-discord.md`
- Fast recruiting copy: `marketing/recruiting-copy-ready.txt`
- League hooks: `notes/league-hooks.md`
- Local command catalog: `COMMANDS.md`
- Long completed-work archive: `TODO.md`

Keep new planning notes inside `docs/`, `marketing/`, `notes/`, or `ideas/` so the repo root stays mostly reserved for public pages and entry-point docs.

## Local Preview

```powershell
python -m http.server 8000
```

Then open `http://localhost:8000/index.html`.
