# TODO

## Immediate

- [ ] Resolve the Best Ball Union lineup mismatch: the constitution says `3 WR` starters, while Sleeper currently reports `2 WR` starters for completed `BBU1` through `BBU6` and open `BBU7` through `BBU10`.
- [ ] Verify and record the pending Mandalore LeagueSafe refund in `DYN8`; the league is now full and paid, so this remains a historical payment-record follow-up rather than a recruiting blocker.
- [ ] Add public rendered ranking destinations for future completed Redraft, Keeper, Chopped, Redraft Bracket, and Dynasty Bracket boards before their first board is promoted as live.

## Next Automation Ideas

- [ ] Decide whether to add an optional Tuesday GitHub Action that republishes bracket standings snapshots automatically, or keep standings updates fully manual while live scoreboards continue to refresh from Sleeper in the browser.

## Completed

### Immediate

- [x] Split the Bracket Center into redraft and dynasty views inside the same page and scaffold the dynasty-bracket ledger path so both formats can share the same public center pattern.
- [x] Add the LeagueSafe links for `DYN4`, `KP1`, and `KP2`, clearing the remaining active league-data validation warnings.
- [x] Add dated addendum and revision-history sections to the public constitutions, and update the draft-timing language to reflect the post-NFL-draft rule change.
- [x] Save a commissioner-ready dynasty rookie draft order worksheet for `DYN1`, `DYN2`, and `DYN3`, including the reason for each slot and the manual best-ball rule for `1.07` and `1.08`.
- [x] Verify the homepage format filters work correctly in Chrome after cache-busting.
- [x] Add the `DYN3` invite link once the current manager leaves and the open spot is actually available.
- [x] Save trusted private outreach copy for the weaker `DYN3` orphan in the marketing docs.
- [x] Keep the weaker `DYN3` year-2 orphan in-house by taking over the team instead of advertising the opening.
- [x] Store the public Sleeper invite links for `KP1` and `KP2` while keeping the keeper leagues in `coming-soon` status until their LeagueSafe links are ready.
- [x] Flip `KP1` and `KP2` from `coming-soon` to `open` once their public Sleeper invite links are ready, even before the LeagueSafe links are added.
- [x] Confirm league cards render in internal ID order within each format, especially `RD1`, `RD2`, `RD3`.
- [x] Create and store the dynasty LeagueSafe links for `DYN1`, `DYN2`, and `DYN3`, including future-season links for `2027` and `2028`.
- [x] Push the dynasty LeagueSafe, validator, and preview workflow updates to `origin/main`.
- [x] Keep LeagueSafe links stored in data only and do not expose them on the homepage UI.
- [x] Populate current active league records with real `sleeperLeagueId` values and current `leagueSafeLink` values where available.

### League Data Migration

- [x] Replace placeholder or manual `filled` values with Sleeper-synced values wherever a valid `sleeperLeagueId` exists.
- [x] Populate `sleeperLeagueId` for dynasty, bracket, and best ball leagues where available.
- [x] Confirm each league entry points to the correct `constitutionPage`, and enforce the format-to-page mapping in the validator.
- [x] Display bracket draft pace from `division` on homepage league cards as `Fast Draft` or `Slow Draft`.
- [x] Review league status values and keep `DYN3` marked `open` as an accepted temporary exception while waiting on a manager exit.
- [x] Add the first `KP1` and `KP2` keeper league placeholder records for 2026 with `$25` and `$50` buy-ins.
- [x] Treat `coming-soon` league records as prelaunch placeholders in validation and homepage rendering rather than as open joinable spots.

### Donation Section

- [x] Decide whether to keep donations on Google Sheets or migrate donations to local JSON later.
- [x] Verify the donation progress bars and local donation JSON rendering on the homepage.
- [x] Adopt a lightweight donation-update workflow that uses Google Form responses as intake and `data/donations.json` as the published source of truth.

### Constitutions

- [x] Confirm banner images and `Back to Hub` links are present and structurally valid on all constitution pages.
- [x] Publish the first keeper constitution page and replace the Keeper homepage placeholder card.
- [x] Normalize the noisiest export-style heading and list formatting in the redraft, best ball, bracket, and dynasty constitutions.

### Automation Recommendations

- [x] Add a reusable 100 Yard Rush helper for league draft-order races using the VBP defaults of 3-8 yards, 2-6 seconds, Fast speed, and no luck.
- [x] Upgrade generated power rankings to verify live league scoring settings and publish owner-by-position boards without public player breakdowns.
- [x] Move the Best Ball Union Top 20 board onto generated completed-room rankings and add format-specific ranking profiles for current league setups.
- [x] Add an organized private payment center with generic single-league LeagueSafe import, Sleeper reconciliation, and an all-league payment index, starting with `DYN8`.
- [x] Add a top-level private `PAYMENT-CENTER` explorer view with one league sheet per record and a confirmed-manager master list.
- [x] Extend the payment center with a cross-league running manager directory and unmatched paid/Sleeper BBU queues.
- [x] Add a fast BBU Payment Center refresh workflow that skips slow Excel formatting by default and preserves prior outputs on Sleeper fetch failures.
- [x] Add Redraft Bracket LeagueSafe import and reconciliation sheets to the private payment workbook.
- [x] Add a Best Ball Gauntlet LeagueSafe import for the new BG1 payment export.
- [x] Add a private BBU LeagueSafe export importer that replaces the current raw export and normalized paid-row CSV.
- [x] Add a formatted Excel workbook exporter for the private BBU payment reconciliation sheets.
- [x] Add a private BBU payment reconciliation pilot that compares Sleeper managers with local LeagueSafe payment rows and reusable identity matches.
- [x] Add a league occupancy report so published `filled` counts can be reviewed quickly without reading raw JSON.
- [x] Add a missing-data autofill assistant that suggests likely `constitutionPage` and default format-specific fields for new league records.
- [x] Add a first public Bracket Center page that renders division playoff counts and full combined standings from the local bracket ledger.
- [x] Add live per-division scoreboard tabs to the Bracket Center so visitors can follow current-week matchup scores across Titan, Apex, Iron, Vanguard, and Dominion.
- [x] Add a bracket report generator that outputs division playoff counts plus full combined group standings from the local bracket ledger.
- [x] Add a small local script to parse a Sleeper league URL and auto-fill `sleeperLeagueId` into a league record.
- [x] Add a local sync script that refreshes Sleeper-derived fields such as league name, team count, and filled spots for all leagues with a `sleeperLeagueId`.
- [x] Add a validation script for `data/leagues.json` to catch missing required fields, invalid formats, broken constitution page references, and malformed URLs before changes are pushed.
- [x] Add a donation-data validation script for `data/donations.json` and optional live DonorsChoose link health so homepage donation data is easier to verify.
- [x] Add a league data diff report that summarizes what changed after a sync run in a cleaner human-readable format for review before commit.
- [x] Add a numbering helper that automatically assigns the next internal ID for a new league based on format prefix, such as `RD`, `DYN`, `BBU`, `RDB`, `KP`, or `CH`.
- [x] Add a template-driven league intake script that asks the same standard questions and writes or updates the correct JSON entry automatically.
- [x] Add a lightweight preview script that opens the local homepage with a cache-busting query string after league-data updates.
- [x] Add a one-command check script that verifies `index.html`, `styles.css`, `app.js`, and `data/leagues.json` for common structural mistakes before commit.
- [x] Add a GitHub Action to run JSON validation and basic link/path checks on every push.
- [x] Add a periodic sync workflow to regenerate Sleeper-derived league fields automatically while preserving your manual fields like `inviteLink` and `leagueSafeLink`.
- [x] Document a future split between manual and synced league data so field ownership is clearer if automation expands.
- [x] Add a cache-busting helper that bumps the `styles.css?v=` and `app.js?v=` values in `index.html` after frontend changes.
- [x] Add a constitution-page check script that verifies each constitution has a working back link, banner image reference, and basic section structure.
- [x] Add a release helper that runs the local check script, opens a preview, and summarizes whether the site is ready to push.
- [x] Add a keeper-ledger sync script and local dataset that pull current keeper-league managers from Sleeper into a commissioner worksheet while preserving manual keeper slots.
- [x] Add a bracket-ledger sync script and grouped bracket datasets that pull combined `RDB` standings from Sleeper and output Seeds `1-32`, wild cards, and Week 13 bracket matchups.

### Cleanup / Future Improvements

- [x] Add a small documented workflow for updating `data/leagues.json` from the intake template.
- [x] Keep planned empty formats visible in Active Leagues until the keeper format is ready to launch.
- [x] Add a Best Ball Union center page that exposes combined public standings, league leaders, and weekly high scores in the same separate-page pattern as the Bracket Center.
- [x] Refine the general Sleeper thumbnail into a cleaner square image based primarily on the VBP banner.
