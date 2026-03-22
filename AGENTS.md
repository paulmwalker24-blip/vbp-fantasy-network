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
- It fetches league availability data from a local JSON file.
- It can optionally enrich league entries with Sleeper API data when a `sleeperLeagueId` is present in the local JSON.
- It fetches donation project data from a separate published Google Sheets CSV.
- It links out to individual constitution pages for specific league formats.

The site is effectively data-driven through local league JSON, Google Sheets donation data, and static HTML content.

## File Map

- `index.html`
  - Homepage structure.
  - Defines containers populated by `app.js`, including:
    - `#limitedSpotsContainer`
    - `#formatFilters`
    - `#leaguesContainer`
    - `#donationProjectsContainer`
    - `#lastUpdated`

- `app.js`
  - Fetches local league JSON and donation CSV data.
  - Can optionally fetch Sleeper league details for entries with `sleeperLeagueId`.
  - Preserves local display names while still using Sleeper to refresh counts and season data.
  - Caps hydrated filled counts so the homepage does not show impossible roster counts.
  - Treats `filled` as the number of roster slots with an assigned `owner_id`, not simply the number of league members.
  - Normalizes league and donation rows.
  - Preserves league display order by internal ID sequence within each format.
  - Handles homepage format-filter interactions.
  - Renders league cards, grouped format sections, limited-spots cards, and donation cards.
  - Contains a custom CSV parser instead of using a dependency.

- `data/leagues.json`
  - Primary source of league data for the homepage.
  - Stores manual league fields such as invite link, LeagueSafe link, buy-in, constitution page, and optional Sleeper IDs.
  - LeagueSafe links are stored here for operations, but are not currently displayed on the homepage.

- `data/league-intake-template.md`
  - Reusable questionnaire for adding or updating leagues in `data/leagues.json`.

- `styles.css`
  - Shared styles for the homepage and constitution pages.
  - Contains layout styles, card styles, button styles, and constitution page section styles.

- `scripts/`
  - Local maintenance automation for league intake, Sleeper sync, validation, preview, and pre-push checks.
  - Current scripts include:
    - `set-sleeper-league-id.ps1`
    - `sync-sleeper-leagues.ps1`
    - `validate-leagues-json.ps1`
    - `get-next-league-id.ps1`
    - `upsert-league-record.ps1`
    - `open-preview.ps1`
    - `check-site.ps1`
  - `README.md` in this folder documents how each local script is intended to be run.

- `COMMANDS.md`
  - Repo-local prompt catalog for asking Codex to run repeatable local automations without manually typing PowerShell commands.

- `.github/workflows/`
  - `validate-site.yml` runs the local site-check script on push and pull request.
  - `sleeper-sync.yml` provides an optional automated Sleeper sync path for `data/leagues.json`.

- `docs/league-data-ownership.md`
  - Documents the current flat league-data model and a future `manual` / `synced` split if automation expands further.

- `redraft-constitution.html`
- `dynasty-constitution.html`
- `bestball-constitution.html`
- `bracket-constitution.html`
- `chopped-constitution.html`
  - Standalone static pages using the shared stylesheet.

- `app_updated_donation_gid0.js`
  - Appears to be an alternate or newer donation parsing variant.
  - Not currently wired into `index.html`.
  - Treat it as reference material unless the user explicitly wants it merged or promoted.

## Runtime Assumptions

- The site runs directly in the browser.
- `fetch()` must be available.
- The local `data/leagues.json` file must remain accessible from the site root.
- Sleeper API access is optional and only applies to leagues with a `sleeperLeagueId`.
- The published Google Sheets donation CSV URL in `app.js` must remain publicly accessible.
- The HTML structure and the element IDs expected by `app.js` must stay in sync.

If you rename or remove a container in `index.html`, update the corresponding logic in `app.js`.

## Data Contracts

### League JSON

The current league rendering depends on:

- `id`
- `sleeperLeagueId` (optional)
- `sleeperSeason`
- `name`
- `format`
- `division`
- `teams`
- `filled`
- `buyIn`
- `inviteLink`
- `leagueSafeLink`
- `constitutionPage`
- `status`

Recognized normalized formats:

- `redraft`
- `dynasty`
- `bestball`
- `bracket`
- `keeper`
- `chopped`

If a new format is introduced, update `FORMAT_META` and `normalizeFormat()`.

When adding or updating leagues, prefer using `data/league-intake-template.md` so the required fields stay consistent.
For new leagues, ask the league type first and infer the internal ID by format sequence rather than asking the user to choose the ID manually.
If the user provides a Sleeper league URL instead of a raw ID, parse the numeric league ID from the URL and store it in `sleeperLeagueId`.
Current ID prefixes are:

- `RD` for redraft
- `DYN` for dynasty
- `BBU` for best ball
- `RDB` for bracket
- `KP` for keeper
- `CH` for chopped

Current league notes:

- `division` is currently used as draft type for bracket leagues, such as `Fast` or `Slow`.
- `CH1` is a live chopped league and should continue pointing to `chopped-constitution.html`.
- LeagueSafe links should remain stored data unless the user explicitly asks to expose them in the homepage UI.
- The local maintenance scripts intentionally treat `inviteLink`, `leagueSafeLink`, `constitutionPage`, `buyIn`, and curated `name` values as commissioner-owned fields unless the user explicitly opts into overwriting them.
- For Sleeper-backed leagues, `filled` should reflect paid/assigned teams by counting roster slots with an `owner_id`. Do not treat raw league member count as the true fill number.

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
- Preserve the format filter markup and `data-format` values in `#formatFilters` unless the filtering behavior is being intentionally changed.
- Constitution pages follow a repeated pattern; keep new pages aligned with existing structure.
- `index.html` now includes a live Chopped constitution card; do not revert it to a placeholder unless requested.

### CSS

- Reuse the design tokens in `:root` where possible.
- Keep homepage and constitution page styles shared unless a page-specific split is clearly warranted.
- Check mobile behavior when changing grids or card sizing.
- `index.html` currently uses query-string cache busting on `styles.css` and `app.js`; update those version strings when local browser caching is interfering with verification.

### JavaScript

- Keep the code framework-free and browser-native.
- Prefer small helper functions over large inline render blocks.
- Preserve graceful fallback behavior when fetches fail.
- When changing parsing behavior, avoid assumptions that only match one temporary spreadsheet export.
- Keep league ordering stable by internal ID sequence within each format unless the user explicitly asks for a different sort order.
- Keep the format filter functional when changing homepage league rendering.
- Do not reintroduce behavior that overwrites curated local league names with raw Sleeper names unless the user explicitly asks for that.

### Local Automation

- Prefer using the scripts in `scripts/` for repeatable data-maintenance tasks instead of redoing one-off manual JSON edits.
- If a task can be handled by an existing local script, use that script and then summarize the result for the user.
- Keep local scripts conservative about which fields they mutate.
- Validation and check scripts should be safe to run repeatedly.
- If you add a new repeatable automation, update:
  - `scripts/README.md`
  - `COMMANDS.md`
  - the relevant `TODO.md` entry

## Known Issues And Hazards

- Text encoding appears inconsistent in several files. Characters such as bullets and arrows are rendering as mojibake like `â€¢` and `â†`.
- `app_updated_donation_gid0.js` suggests donation parsing has already been revised once; compare carefully before replacing current logic.
- Git operations may fail in some sandboxed environments because the repo can trigger a `safe.directory` ownership warning.
- Some constitution pages include duplicated or noisy generated section links and content formatting artifacts.

Do not silently "clean up" generated constitution content unless the user asks for content normalization, because those pages may have been exported from another source.

## Preferred Workflow For Agents

1. Read `index.html`, `styles.css`, and `app.js` first.
2. Confirm whether the task affects static content, styling, or CSV-driven rendering.
3. If the task touches leagues, inspect `data/leagues.json` and `data/league-intake-template.md` before editing UI.
4. For new league intake, ask the league type first and infer the next internal ID from the existing entries in `data/leagues.json`.
5. If the user provides a Sleeper league URL, extract the numeric league ID and store it in `sleeperLeagueId`.
6. If a league has a `sleeperLeagueId`, preserve the Sleeper-enrichment path in `app.js`.
7. If the task touches donations, inspect the parser assumptions before editing UI.
8. Keep changes minimal and local unless the user asks for a broader refactor.
9. If behavior depends on live CSV data, note that full verification may require live network access in a browser.
10. If the task touches chopped leagues, inspect `chopped-constitution.html` and the `CH1` record in `data/leagues.json` before making assumptions about the format.
11. If you add a new repeatable automation or recurring local workflow, add a matching prompt entry to `COMMANDS.md`.
12. Before creating a new automation, check whether the behavior belongs in an existing script instead of adding another narrowly scoped file.
13. If a task is “run the checks” or “what still needs attention,” prefer `scripts/check-site.ps1`, `scripts/validate-leagues-json.ps1`, and `scripts/sync-sleeper-leagues.ps1` over ad hoc inspection.

## Verification Guidance

For most changes, verify with:

- static inspection of `index.html`, `styles.css`, and `app.js`
- static inspection of `data/leagues.json` when league data changes
- checking that referenced IDs/classes still match
- checking that render paths still handle empty or failed fetch states
- checking mobile grid breakpoints in `styles.css`
- checking that homepage format filters still work when league rendering changes
- checking that league order within a format still follows the internal IDs
- when verifying design or image changes locally, clear browser cache or do a hard refresh before judging the result, since localhost assets may be cached

Local runtime notes:

- A simple local server can be started from repo root with `py -m http.server 8000`.
- The homepage can then be opened at `http://localhost:8000/index.html`.
- If script or stylesheet changes are not visible, hard refresh first and then consider bumping the cache-busting query strings in `index.html`.
- The local preview helper `scripts/open-preview.ps1` already handles cache-busted localhost URLs and should be preferred for repeat preview checks.

If runtime verification is required, use a browser or local static server when available.

## Non-Goals

Unless requested by the user, do not:

- introduce a frontend framework
- add a build pipeline
- add package management just to solve a small issue
- rewrite constitution content for tone or policy
- remove alternate files that may reflect in-progress user work
