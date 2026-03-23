# TODO

## Immediate

- [ ] Verify the homepage format filters work correctly in Chrome after cache-busting.
- [ ] Continue populating `data/leagues.json` with real Sleeper league IDs, invite links, and LeagueSafe links for all active leagues.
- [ ] Add missing `leagueSafeLink` values for the remaining leagues.
- [ ] Decide whether the homepage should visibly expose LeagueSafe links or keep them as stored data only for now.

## League Data Migration

- [ ] Confirm each league entry points to the correct `constitutionPage`.
- [ ] Review `status` values across all leagues so `open`, `full`, and `coming-soon` are consistent.
- [ ] Decide whether `division` should be displayed anywhere for bracket leagues.

## Donation Section

- [ ] Decide how donation updates should be tracked through the form over time.

## Constitutions

- [ ] Review constitution pages for duplicate or noisy generated formatting artifacts.
- [ ] Confirm banner images and "Back to Hub" links render correctly on all constitution pages.

## Cleanup / Future Improvements

- [ ] Add a small documented workflow for updating `data/leagues.json` from the intake template.
- [ ] Consider adding a script later to help merge Sleeper API data into local league records.
- [ ] Normalize constitution formatting artifacts later, especially export-style heading/list structure in the redraft, best ball, bracket, and dynasty pages.
- [ ] Decide whether to keep planned empty formats visible in Active Leagues or hide them until launched.
- [ ] Revisit the general Sleeper thumbnail image and refine it into a final brand-ready square image based primarily on the VBP banner.

## Next Automation Ideas

- [ ] Add a donation-data validation script for `data/donations.json` and live DonorsChoose link health so homepage donation data is easier to verify.
- [ ] Add a cache-busting helper that bumps the `styles.css?v=` and `app.js?v=` values in `index.html` after frontend changes.
- [ ] Add a league data diff report that summarizes what changed after a sync run in a cleaner human-readable format for review before commit.
- [ ] Add a missing-data autofill assistant that suggests likely `constitutionPage` and default format-specific fields for new league records.
- [ ] Add a constitution-page check script that verifies each constitution has a working back link, banner image reference, and basic section structure.
- [ ] Add a release helper that runs the local check script, opens a preview, and summarizes whether the site is ready to push.

## Completed

### Immediate

- [x] Confirm league cards render in internal ID order within each format, especially `RD1`, `RD2`, `RD3`.
- [x] Create and store the dynasty LeagueSafe links for `DYN1`, `DYN2`, and `DYN3`, including future-season links for `2027` and `2028`.
- [x] Push the dynasty LeagueSafe, validator, and preview workflow updates to `origin/main`.

### League Data Migration

- [x] Replace placeholder or manual `filled` values with Sleeper-synced values wherever a valid `sleeperLeagueId` exists.
- [x] Populate `sleeperLeagueId` for dynasty, bracket, and best ball leagues where available.

### Donation Section

- [x] Decide whether to keep donations on Google Sheets or migrate donations to local JSON later.
- [x] Verify the donation progress bars and local donation JSON rendering on the homepage.

### Automation Recommendations

- [x] Add a small local script to parse a Sleeper league URL and auto-fill `sleeperLeagueId` into a league record.
- [x] Add a local sync script that refreshes Sleeper-derived fields such as league name, team count, and filled spots for all leagues with a `sleeperLeagueId`.
- [x] Add a validation script for `data/leagues.json` to catch missing required fields, invalid formats, broken constitution page references, and malformed URLs before changes are pushed.
- [x] Add a numbering helper that automatically assigns the next internal ID for a new league based on format prefix, such as `RD`, `DYN`, `BBU`, `RDB`, `KP`, or `CH`.
- [x] Add a template-driven league intake script that asks the same standard questions and writes or updates the correct JSON entry automatically.
- [x] Add a lightweight preview script that opens the local homepage with a cache-busting query string after league-data updates.
- [x] Add a one-command check script that verifies `index.html`, `styles.css`, `app.js`, and `data/leagues.json` for common structural mistakes before commit.
- [x] Add a GitHub Action to run JSON validation and basic link/path checks on every push.
- [x] Add a periodic sync workflow to regenerate Sleeper-derived league fields automatically while preserving your manual fields like `inviteLink` and `leagueSafeLink`.
- [x] Document a future split between manual and synced league data so field ownership is clearer if automation expands.
