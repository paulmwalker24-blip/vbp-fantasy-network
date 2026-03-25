# vbp-fantasy-network

A static site for the VBP Fantasy Network: league discovery, constitutions, and public format centers.

## Layout

- `index.html` plus the root `*-constitution.html` and `*-center.html` pages stay at the repo root so their public URLs remain simple and stable.
- `assets/css/` holds shared frontend styling.
- `assets/js/` holds the homepage and center-page client logic.
- `assets/images/` holds banners, aligned format artwork, and social thumbnails.
- `assets/reference/` holds non-wired reference files that should not clutter the live app surface.
- `data/`, `docs/`, `marketing/`, and `scripts/` keep commissioner data, process notes, reusable copy, and local automation separated from the web assets.

## Local Preview

```powershell
python -m http.server 8000
```

Then open `http://localhost:8000/index.html`.
