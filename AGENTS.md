# AGENTS.md

## Project Overview

This repository is a small static website for the VBP Fantasy Network.

- Primary entry page: `index.html`
- Shared styling: `styles.css`
- Main client logic: `app.js`
- Additional static content: `*-constitution.html`
- Visual assets: `banner.png` and `*_aligned.png`

There is no build system, package manager, framework, or server-side app in this repo. Changes are made directly to static HTML, CSS, and vanilla JavaScript.

## What The Site Does

The homepage acts as a hub for fantasy football leagues and league constitutions.

- It renders static marketing content and navigation.
- It fetches league availability data from a published Google Sheets CSV.
- It fetches donation project data from a separate published Google Sheets CSV.
- It links out to individual constitution pages for specific league formats.

The site is effectively data-driven through Google Sheets plus static HTML content.

## File Map

- `index.html`
  - Homepage structure.
  - Defines containers populated by `app.js`, including:
    - `#limitedSpotsContainer`
    - `#leaguesContainer`
    - `#donationProjectsContainer`
    - `#lastUpdated`

- `app.js`
  - Fetches and parses the two CSV sources.
  - Normalizes league and donation rows.
  - Renders league cards, grouped format sections, limited-spots cards, and donation cards.
  - Contains a custom CSV parser instead of using a dependency.

- `styles.css`
  - Shared styles for the homepage and constitution pages.
  - Contains layout styles, card styles, button styles, and constitution page section styles.

- `redraft-constitution.html`
- `dynasty-constitution.html`
- `bestball-constitution.html`
- `bracket-constitution.html`
  - Standalone static pages using the shared stylesheet.

- `app_updated_donation_gid0.js`
  - Appears to be an alternate or newer donation parsing variant.
  - Not currently wired into `index.html`.
  - Treat it as reference material unless the user explicitly wants it merged or promoted.

## Runtime Assumptions

- The site runs directly in the browser.
- `fetch()` must be available.
- The published Google Sheets CSV URLs in `app.js` must remain publicly accessible.
- The HTML structure and the element IDs expected by `app.js` must stay in sync.

If you rename or remove a container in `index.html`, update the corresponding logic in `app.js`.

## Data Contracts

### League CSV

`app.js` tolerates multiple possible header names and normalizes them with `pick()`.

Expected fields include variants of:

- league name
- league type / format
- team count
- filled spots
- buy-in
- join link

The current rendering depends on:

- `name`
- `format`
- `teams`
- `filled`
- `spotsLeft`
- `buyIn`
- `link`

Recognized normalized formats:

- `redraft`
- `dynasty`
- `bestball`
- `bracket`
- `keeper`
- `chopped`

If a new format is introduced, update `FORMAT_META` and `normalizeFormat()`.

### Donation CSV

Donation parsing is more brittle because the sheet may contain headers, form-response rows, or inconsistent column meaning. Existing code attempts to filter non-project rows heuristically.

If donation rendering breaks:

- inspect the published CSV shape first
- verify whether the correct sheet tab is being published
- prefer tightening row detection over hardcoding a single fragile row position

## Editing Guidance

### HTML

- Keep the site static and simple unless the user asks for a structural rewrite.
- Preserve IDs and section anchors that are referenced by buttons or scripts.
- Constitution pages follow a repeated pattern; keep new pages aligned with existing structure.

### CSS

- Reuse the design tokens in `:root` where possible.
- Keep homepage and constitution page styles shared unless a page-specific split is clearly warranted.
- Check mobile behavior when changing grids or card sizing.

### JavaScript

- Keep the code framework-free and browser-native.
- Prefer small helper functions over large inline render blocks.
- Preserve graceful fallback behavior when fetches fail.
- When changing parsing behavior, avoid assumptions that only match one temporary spreadsheet export.

## Known Issues And Hazards

- Text encoding appears inconsistent in several files. Characters such as bullets and arrows are rendering as mojibake like `â€¢` and `â†`.
- `app_updated_donation_gid0.js` suggests donation parsing has already been revised once; compare carefully before replacing current logic.
- Git operations may fail in some sandboxed environments because the repo can trigger a `safe.directory` ownership warning.
- Some constitution pages include duplicated or noisy generated section links and content formatting artifacts.

Do not silently "clean up" generated constitution content unless the user asks for content normalization, because those pages may have been exported from another source.

## Preferred Workflow For Agents

1. Read `index.html`, `styles.css`, and `app.js` first.
2. Confirm whether the task affects static content, styling, or CSV-driven rendering.
3. If the task touches donations or leagues, inspect the parser assumptions before editing UI.
4. Keep changes minimal and local unless the user asks for a broader refactor.
5. If behavior depends on live CSV data, note that full verification may require live network access in a browser.

## Verification Guidance

For most changes, verify with:

- static inspection of `index.html`, `styles.css`, and `app.js`
- checking that referenced IDs/classes still match
- checking that render paths still handle empty or failed fetch states
- checking mobile grid breakpoints in `styles.css`
- when verifying design or image changes locally, clear browser cache or do a hard refresh before judging the result, since localhost assets may be cached

If runtime verification is required, use a browser or local static server when available.

## Non-Goals

Unless requested by the user, do not:

- introduce a frontend framework
- add a build pipeline
- add package management just to solve a small issue
- rewrite constitution content for tone or policy
- remove alternate files that may reflect in-progress user work
