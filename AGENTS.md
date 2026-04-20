# AGENTS.md

## Project Overview

This repository is a small static website for the VBP Fantasy Network.

- Primary entry page: `index.html`
- Shared styling: `assets/css/styles.css`
- Main client logic: `assets/js/app.js`
- Additional static content: `*-constitution.html`
- Public pages stay at the repo root so deployed URLs remain simple.
- Visual assets live under `assets/images/`.

There is no build system, package manager, framework, or server-side app in this repo. Changes are made directly to static HTML, CSS, and vanilla JavaScript.

## What The Site Does

The homepage acts as a hub for fantasy football leagues and league constitutions.

- It renders static marketing content and navigation.
- It fetches league availability data from a local JSON file.
- It can optionally enrich league entries with Sleeper API data when a `sleeperLeagueId` is present in the local JSON.
- It fetches donation project data from a local JSON file.
- It links out to individual constitution pages for specific league formats.

The site is effectively data-driven through local league JSON, local donation JSON, and static HTML content.

## File Map

- `index.html`
  - Homepage structure.
  - Defines containers populated by `assets/js/app.js`, including:
    - `#limitedSpotsContainer`
    - `#formatFilters`
    - `#leaguesContainer`
    - `#donationProjectsContainer`
    - `#lastUpdated`

- `assets/js/app.js`
  - Fetches local league JSON and local donation JSON data.
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

- `data/donations.json`
  - Local source of donation project data for the homepage.
  - Stores the current project slot, title, state, donated amount, goal amount, remaining amount, and DonorsChoose link.

- `data/league-intake-template.md`
  - Reusable questionnaire for adding or updating leagues in `data/leagues.json`.
  - Includes the recommended local workflow for writing, validating, and optionally syncing league updates.

- `data/keeper-ledger.json`
  - Local keeper tracker that merges Sleeper manager and current-roster pulls for keeper leagues with manual commissioner-entered keeper slots.
  - Intended to be the working dataset for keeper declarations, keeper rounds, and future-year tracking.

- `data/bracket-groups.json`
  - Commissioner-owned config that defines which `RDB` league records belong to the same combined bracket tournament group.
  - Current source of truth is one 2026 group containing `RDB1` through `RDB5`.

- `data/bracket-ledger.json`
  - Local bracket tracker that merges Sleeper manager and standings pulls across grouped bracket leagues.
  - Intended to be the working dataset for combined playoff seeding, wild cards, bracket outputs, and flat 1-60 style overall standings review.

- `assets/css/styles.css`
  - Shared styles for the homepage and constitution pages.
  - Contains layout styles, card styles, button styles, and constitution page section styles.

- `assets/images/`
  - Shared banner, format artwork, and social/center image assets used by the public HTML pages.
  - Includes the refined square social asset `sleeper-thumbnail-general.png` for general Sleeper or social sharing.

- `scripts/`
  - Local maintenance automation for league intake, Sleeper sync, validation, preview, and pre-push checks.
  - Current scripts include:
    - `sync-bracket-ledger.ps1`
    - `export-bracket-report.ps1`
    - `sync-keeper-ledger.ps1`
    - `bump-cache-bust.ps1`
    - `check-constitutions.ps1`
    - `league-data-diff-report.ps1`
    - `release-helper.ps1`
    - `create-general-thumbnail.ps1`
    - `validate-donations-json.ps1`
    - `set-sleeper-league-id.ps1`
    - `sync-sleeper-leagues.ps1`
    - `validate-leagues-json.ps1`
    - `get-next-league-id.ps1`
    - `upsert-league-record.ps1`
    - `open-preview.ps1`
    - `check-site.ps1`
  - `check-site.ps1` now includes constitution-page and donation-data validation alongside the broader homepage and league-data checks.
  - `README.md` in this folder documents how each local script is intended to be run.

- `COMMANDS.md`
  - Repo-local prompt catalog for asking Codex to run repeatable local automations without manually typing PowerShell commands.

- `TODO.md`
  - Active backlog lives at the top of the file.
  - Completed items are preserved and moved to the bottom instead of being deleted.

- `LOCAL-PREVIEW.md`
  - Tiny repo-root reminder file for the localhost command and homepage URL.
  - Use this when the user wants a quick explorer-visible preview reference instead of a longer doc.

- `marketing/recruiting-playbook.md`
  - Canonical recruiting strategy and source-copy file for the VBP Fantasy Network.
  - Consolidates the old Facebook, Reddit, generic, and other-platform notes into one reusable playbook.
  - Use this when the user wants recruiting ideas, platform guidance, title angles, or reusable outreach patterns captured in-repo.

- `marketing/recruiting-copy-ready.txt`
  - Plain-text recruiting copy bank for direct copy/paste without markdown formatting.
  - Use this when the user wants the simplest possible paste-ready version of the current recruiting posts.

- `.github/workflows/`
  - `validate-site.yml` runs the local site-check script on push and pull request.
  - `sleeper-sync.yml` provides an optional automated Sleeper sync path for `data/leagues.json`.

- `docs/league-data-ownership.md`
  - Documents the current flat league-data model and a future `manual` / `synced` split if automation expands further.

- `docs/donation-update-workflow.md`
  - Documents the lightweight manual process for applying Google Form donation responses to `data/donations.json`.

- `redraft-constitution.html`
- `dynasty-constitution.html`
- `bestball-constitution.html`
- `bracket-constitution.html`
- `bracket-center.html`
- `keeper-constitution.html`
- `chopped-constitution.html`
  - Standalone static pages using the shared stylesheet.

- `assets/js/bracket-center.js`
  - Client-side renderer for the public Bracket Center page.
  - Reads `data/bracket-ledger.json` and renders division counts plus full combined standings.
  - Falls back to a clearly labeled sample 60-team preview when the live grouped bracket data is still pre-draft, incomplete, or not yet showing meaningful standings.
  - Also fetches live Sleeper matchup data by division so the center can expose current-week scoreboard tabs for grouped bracket leagues.
  - Live scoreboards should refresh from Sleeper in the browser when users reload the page, while standings remain a commissioner-published snapshot from local generated data.

- `assets/js/bestball-center.js`
  - Client-side renderer for the public Best Ball Union Center page.
  - Pulls Best Ball Union league data and renders league leaders, an overall points leaderboard, and weekly overall high-score tracking across all BBU leagues.
  - Uses a clearly labeled Week 5 sample preview until live BBU scoring is meaningful enough to support the public view.
  - The overall points leaderboard is intentionally capped at the top 20 teams, and weekly high scores refer to the single highest scorer across all BBU leagues for each week.

- `assets/reference/app_updated_donation_gid0.js`
  - Appears to be an alternate or newer donation parsing variant.
  - Not currently wired into `index.html`.
  - Treat it as reference material unless the user explicitly wants it merged or promoted.

## Runtime Assumptions

- The site runs directly in the browser.
- `fetch()` must be available.
- The local `data/leagues.json` file must remain accessible from the site root.
- Sleeper API access is optional and only applies to leagues with a `sleeperLeagueId`.
- The local `data/donations.json` file must remain accessible from the site root.
- The local `data/keeper-ledger.json` file is commissioner-owned working data and is not used by the homepage.
- The local `data/bracket-groups.json` and `data/bracket-ledger.json` files are commissioner-owned working data and are not used by the homepage.
- The HTML structure and the element IDs expected by `assets/js/app.js` must stay in sync.

If you rename or remove a container in `index.html`, update the corresponding logic in `assets/js/app.js`.

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
- `sleeperFilled` (optional reference copy of Sleeper owner-assigned roster count)
- `buyIn`
- `inviteLink`
- `leagueSafeLink`
- `leagueSafeLinksBySeason` (optional, for dynasty or other multi-season payment tracking)
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
If the user provides a Sleeper league URL or invite link instead of a raw ID, resolve the live numeric league ID and store it in `sleeperLeagueId`.
Current ID prefixes are:

- `RD` for redraft
- `DYN` for dynasty
- `BBU` for best ball
- `RDB` for bracket
- `KP` for keeper
- `CH` for chopped

Current league notes:

- `division` is currently used as draft type for bracket leagues, such as `Fast` or `Slow`.
- Bracket league cards should display `division` on the homepage as `Fast Draft` or `Slow Draft`.
- Current bracket automation assumes a 2026 combined tournament group of `RDB1` through `RDB5`, representing five separate 12-team leagues and 60 total teams.
- For bracket groups, the five division winners are always identified first, then ranked among themselves by `record` and `points for` to two decimals for Seeds `1-5`.
- For bracket groups, Seeds `6-30` are the next best teams by `record` then `points for` to two decimals.
- For bracket groups, Seeds `31-32` are the two highest `points for` teams among the remaining non-qualifiers, with `record` used only as a fallback tiebreaker when needed.
- `data/bracket-ledger.json` should keep `seasonDataReady` and `seedingReady` separate so pre-draft or partially filled bracket groups stay clearly provisional.
- Use `data/bracket-groups.json`, `data/bracket-ledger.json`, `scripts/sync-bracket-ledger.ps1`, and `scripts/export-bracket-report.ps1` to manage combined bracket seeding and commissioner-facing standings reports across multiple `RDB` leagues.
- Public format-center pages should live as standalone pages on the same site rather than becoming homepage focal sections.
- Public format-center pages may use a clearly labeled sample preview until the live data is full enough to support a strong public-facing view.
- For League Centers, live current-week scoreboards may fetch directly from Sleeper in the browser, but official standings, cut lines, and custom playoff logic should remain manually generated and published by the commissioner.
- The Bracket Center sample preview should turn off automatically once the grouped leagues are season-ready, fully populated, and showing meaningful live standings data rather than all-zero placeholders.
- The Best Ball Union Center sample preview should remain clearly labeled and may stay in place until live BBU results are meaningful enough to replace it cleanly.
- For the Best Ball Union Center, weekly high scores refer to the single highest-scoring team across all BBU leagues for that week, not per-division weekly winners.
- For the Best Ball Union Center, the public overall points leaderboard is intentionally limited to the top 20 teams.
- `CH1` is a live chopped league and should continue pointing to `chopped-constitution.html`.
- `RD4` is a live 2026 redraft league at `$100` buy-in and currently uses the direct Sleeper predraft URL as its public link.
- `KP1` and `KP2` are the initial 2026 keeper leagues at `$25` and `$50` buy-ins. Their `sleeperLeagueId` values and public Sleeper invite links are now stored, and they are live `open` records even though their LeagueSafe links are still pending.
- In keeper leagues, only trades reset keeper years. Drops, waivers, and free-agent re-adds do not reset keeper years, regardless of which manager acquires the player.
- In keeper leagues, future draft picks may be traded up to two years out, and managers must be paid through the farthest traded season before the trade is processed.
- In keeper leagues, Round 1 is the keeper-cost floor. If a player's next cost would move earlier than Round 1, the player may be kept at a 1st-round cost for the final eligible season and then becomes ineligible afterward.
- Use `data/keeper-ledger.json` and `scripts/sync-keeper-ledger.ps1` to pull current keeper-league managers from Sleeper and preserve manual keeper-slot entries between syncs.
- The keeper ledger should expose current roster players for each manager so the commissioner can fill keeper declarations from a single explorer file.
- Prelaunch league records that are not yet joinable should usually use `coming-soon` rather than `open` until the Sleeper invite and LeagueSafe links exist, unless the user explicitly wants the league opened early with a known temporary LeagueSafe gap.
- LeagueSafe links should remain stored data unless the user explicitly asks to expose them in the homepage UI.
- If a league needs separate LeagueSafe links for future seasons, store the current season in `leagueSafeLink` and add an optional `leagueSafeLinksBySeason` object keyed by season, such as `2026`, `2027`, and `2028`.
- Keeper leagues may use season-keyed `leagueSafeLinksBySeason` data the same way dynasty leagues do once the yearly payment links exist.
- The local maintenance scripts intentionally treat `inviteLink`, `leagueSafeLink`, `constitutionPage`, `buyIn`, and curated `name` values as commissioner-owned fields unless the user explicitly opts into overwriting them.
- `DYN1`, `DYN2`, and `DYN3` now use season-keyed `leagueSafeLinksBySeason` data for `2026`, `2027`, and `2028` alongside the current-season `leagueSafeLink`.
- Sleeper invite links can point to a newer live league than the currently stored `sleeperLeagueId`, especially on renewed dynasty leagues. If live counts look wrong, resolve the invite page's `league_id` before assuming the invite link is stale.
- If the user provides a direct Sleeper league URL instead of a share invite, it is acceptable to store that direct league URL in `inviteLink` so the record can stay publicly actionable while still resolving and storing the numeric `sleeperLeagueId`.
- When checking dynasty future-pick payment obligations, use Sleeper traded-pick data and only flag managers who traded away future picks. Do not flag the managers who received those picks unless they also traded away their own future picks.
- `filled` is the commissioner-published occupancy count used by the site and local copy.
- Optional `sleeperFilled` can store the live Sleeper owner-assigned roster count as reference data when local published occupancy intentionally differs.
- Do not treat raw league member count as the true fill number.

Current donation notes:

- The homepage donation cards now read from `data/donations.json`.
- Donation cards should prefer a stored `remaining` value when present, since DonorsChoose exposes "still needed" amounts more reliably than a stable total-goal payload.
- The donation section includes a public `Report Your Donation` CTA that links to a Google Form. Keep the CTA in a professional secondary position below the cards unless the user explicitly asks for a different layout.
- Google Form responses are the intake queue; `data/donations.json` remains the published homepage source of truth.
- Use `docs/donation-update-workflow.md` for the lightweight manual workflow when applying form responses.
- Use `scripts/validate-donations-json.ps1` to validate donation data before push or after manual updates.

### Donation CSV

The donation section now reads from `data/donations.json` instead of a live Google Sheets CSV.

If donation rendering breaks:

- inspect `data/donations.json` first
- verify that the `projects` array exists
- verify that each project includes `name`, `state`, `goal`, and `link`
- if a `remaining` field is present, treat it as the homepage source of truth for the "remaining" display

## Editing Guidance

### HTML

- Keep the site static and simple unless the user asks for a structural rewrite.
- Preserve IDs and section anchors that are referenced by buttons or scripts.
- Preserve the format filter markup and `data-format` values in `#formatFilters` unless the filtering behavior is being intentionally changed.
- Constitution pages follow a repeated pattern; keep new pages aligned with existing structure.
- `index.html` now includes live Chopped and Keeper constitution cards; do not revert them to placeholders unless requested.
- Standalone public standings/scoreboard destinations should live in a separate `League Centers` block under the constitutions area rather than being mixed into the constitution card grid.

### CSS

- Reuse the design tokens in `:root` where possible.
- Keep homepage and constitution page styles shared unless a page-specific split is clearly warranted.
- Check mobile behavior when changing grids or card sizing.
- `index.html` currently uses query-string cache busting on `assets/css/styles.css` and `assets/js/app.js`; update those version strings when local browser caching is interfering with verification.
- `index.html` now also carries basic Open Graph and Twitter meta tags for link previews; keep the live site URL and banner image path aligned if the public domain or hero asset changes.

### JavaScript

- Keep the code framework-free and browser-native.
- Prefer small helper functions over large inline render blocks.
- Preserve graceful fallback behavior when fetches fail.
- When changing parsing behavior, avoid assumptions that only match one temporary spreadsheet export.
- Keep league ordering stable by internal ID sequence within each format unless the user explicitly asks for a different sort order.
- Keep the format filter functional when changing homepage league rendering.
- Keep planned empty formats visible in Active Leagues unless the user explicitly asks to hide them.
- Do not reintroduce behavior that overwrites curated local league names with raw Sleeper names unless the user explicitly asks for that.
- Do not overwrite commissioner-published `filled` counts from Sleeper unless the user explicitly asks for that sync behavior.

### Local Automation

- Prefer using the scripts in `scripts/` for repeatable data-maintenance tasks instead of redoing one-off manual JSON edits.
- If a task can be handled by an existing local script, use that script and then summarize the result for the user.
- Keep local scripts conservative about which fields they mutate.
- Bracket-ledger syncs should preserve the configured bracket groups while only refreshing Sleeper-owned standings and manager identity fields.
- Bracket report exports should read from `data/bracket-ledger.json` and avoid mutating the grouped bracket data.
- Keeper-ledger syncs should preserve manual keeper slot entries and notes while only refreshing Sleeper-owned league and manager identity fields.
- Validation and check scripts should be safe to run repeatedly.
- Use `release-helper.ps1` when the user wants a quick answer on whether the site is ready to push.
- Use `league-data-diff-report.ps1` when the user wants a reviewer-friendly summary of changes in `data/leagues.json`.
- Keep `TODO.md` organized with incomplete work first and a preserved completed section at the bottom.
- If a constitution encoding issue has actually been fixed, remove the stale encoding-specific TODO rather than leaving it duplicated next to the broader formatting cleanup item.
- If you add a new repeatable automation, update:
  - `scripts/README.md`
  - `COMMANDS.md`
  - the relevant `TODO.md` entry

### Marketing Copy

- For Reddit league-promotion requests, treat `VBP Fantasy Network` as an active brand with live leagues, not something that is still being built, unless the user explicitly wants a softer in-progress angle.
- Default early Reddit posts to short, direct recruiting copy focused on open spots, active owners, competitive formats, and clear rules.
- Keep the network name in the title or first sentence so the brand still gets repeated exposure even when the body copy stays simple.
- Use constitutions and clear rules as trust signals, but do not overload short recruiting posts with too much backstory unless the user asks for a fuller pitch.
- When the user wants reusable outreach ideas, store them in the relevant consolidated file under `marketing/` so future prompts can build from past examples instead of starting from scratch.
- If the user asks for a response-driving version, prefer a direct CTA such as `DM me or reply if interested.`
- For bracket league recruiting copy, prefer an early `Year 3` or established-league hook so the format does not read like an unproven startup and the commissioner experience comes through quickly.
- For weaker dynasty rebuilds or questionable orphan takeovers, prefer trusted private outreach language over broad public promotion.
- Keep public-facing recruiting copy lean. Avoid internal commissioner shorthand such as `DYN5+` unless the user explicitly wants internal context kept in the copy.
- Do not over-explain familiar formats like best ball in public ad copy unless the user explicitly wants a beginner-facing pitch.
- If the user wants raw copy/paste output, prefer the `*-copy-ready.txt` marketing files over the markdown source files so pasted text does not inherit markdown formatting behavior.

## Known Issues And Hazards

- `DYN3` now has a live invite link stored and should no longer be treated as the accepted missing-invite warning case.
- `assets/reference/app_updated_donation_gid0.js` suggests donation parsing has already been revised once; compare carefully before replacing current logic.
- Git operations may fail in some sandboxed environments because the repo can trigger a `safe.directory` ownership warning.
- On this machine, the Windows Store `py` / `python` app alias can break local preview startup or leave `localhost:8000` returning empty responses if the wrong interpreter path is used.
- Some constitution pages may still include minor export-style formatting artifacts, but the noisiest redraft, best ball, bracket, and dynasty sections have already been normalized. Do not treat remaining cleanup as urgent unless the user asks for another polish pass.

Do not silently "clean up" generated constitution content unless the user asks for content normalization, because those pages may have been exported from another source.

## Preferred Workflow For Agents

1. Read `index.html`, `assets/css/styles.css`, and `assets/js/app.js` first.
2. Confirm whether the task affects static content, styling, or CSV-driven rendering.
3. If the task touches leagues, inspect `data/leagues.json` and `data/league-intake-template.md` before editing UI.
4. For new league intake, ask the league type first and infer the next internal ID from the existing entries in `data/leagues.json`.
5. If the user provides a Sleeper league URL or invite link, resolve the live numeric league ID and store it in `sleeperLeagueId`.
6. If a league has a `sleeperLeagueId`, preserve the Sleeper-enrichment path in `assets/js/app.js`.
7. If the task touches donations, inspect the parser assumptions, `docs/donation-update-workflow.md`, and `scripts/validate-donations-json.ps1` before editing UI or data.
8. Keep changes minimal and local unless the user asks for a broader refactor.
9. If behavior depends on live CSV data, note that full verification may require live network access in a browser.
10. If the task touches chopped leagues, inspect `chopped-constitution.html` and the `CH1` record in `data/leagues.json` before making assumptions about the format.
11. If you add a new repeatable automation or recurring local workflow, add a matching prompt entry to `COMMANDS.md`.
12. Before creating a new automation, check whether the behavior belongs in an existing script instead of adding another narrowly scoped file.
13. If a task is `run the checks` or `what still needs attention,` prefer `scripts/check-site.ps1`, `scripts/validate-leagues-json.ps1`, `scripts/validate-donations-json.ps1`, `scripts/sync-sleeper-leagues.ps1`, and `scripts/release-helper.ps1` over ad hoc inspection. `scripts/check-site.ps1` already includes the constitution-page and donation-data validation passes.
14. If the user asks to verify constitution back links, banner images, or section structure, prefer `scripts/check-constitutions.ps1`.
15. After `/init`, if the user needs a local preview, provide exactly two copyable lines: the terminal command to run from repo root and the browser URL to open. Keep both short and do not include the full folder path unless the user asks for it.
16. If the user asks for Reddit, Facebook, or recruiting copy, inspect `marketing/recruiting-playbook.md` first and extend it when a new pattern, title style, or CTA is worth reusing later. Use `marketing/recruiting-copy-ready.txt` when the user wants raw paste-ready output.
17. If the user wants a keeper-manager dataset, commissioner worksheet, or a future keeper process, prefer `scripts/sync-keeper-ledger.ps1` and `data/keeper-ledger.json`.
18. If the user wants combined bracket seeding, weekly bracket standings reports, or grouped `RDB` automation, prefer `scripts/sync-bracket-ledger.ps1`, `scripts/export-bracket-report.ps1`, `data/bracket-groups.json`, and `data/bracket-ledger.json`.

## Verification Guidance

For most changes, verify with:

- static inspection of `index.html`, `assets/css/styles.css`, and `assets/js/app.js`
- static inspection of `data/leagues.json` when league data changes
- checking that referenced IDs/classes still match
- checking that render paths still handle empty or failed fetch states
- checking mobile grid breakpoints in `assets/css/styles.css`
- checking that homepage format filters still work when league rendering changes
- checking that league order within a format still follows the internal IDs
- running `scripts/validate-donations-json.ps1` when donation data changes
- running `scripts/league-data-diff-report.ps1` after large league-data edits or syncs when you want a clean review summary
- running `scripts/check-constitutions.ps1` when constitution back links, banner images, or section structure need verification
- running `scripts/check-site.ps1` when you want the broadest single-pass check, including constitution validation
- running `scripts/release-helper.ps1` when you want a push-readiness summary plus optional preview reopen
- when verifying design or image changes locally, clear browser cache or do a hard refresh before judging the result, since localhost assets may be cached

Local runtime notes:

- Prefer `python -m http.server 8000` from repo root for manual local preview.
- The homepage can then be opened at `http://localhost:8000/index.html`.
- Do not default to `py -m http.server 8000` in user-facing instructions for this repo unless the user explicitly asks for `py`, because the Windows app alias can be unreliable here.
- If the user asks what to paste into `cmd` after opening a terminal in the repo folder, answer with only `python -m http.server 8000`.
- If the user asks what to type into the browser, answer with only `http://localhost:8000/index.html`.
- When the user asks to `generate local host` or open the local preview, prefer `scripts/open-preview.ps1` so the page opens with a cache-busting query string.
- If script or stylesheet changes are not visible, hard refresh first and then consider bumping the cache-busting query strings in `index.html`.
- If script or stylesheet changes are not visible after a hard refresh, `scripts/bump-cache-bust.ps1` can update the homepage asset version strings for you.
- The local preview helper `scripts/open-preview.ps1` already handles cache-busted localhost URLs and should be preferred for repeat preview checks.

If runtime verification is required, use a browser or local static server when available.

## Non-Goals

Unless requested by the user, do not:

- introduce a frontend framework
- add a build pipeline
- add package management just to solve a small issue
- rewrite constitution content for tone or policy
- remove alternate files that may reflect in-progress user work
