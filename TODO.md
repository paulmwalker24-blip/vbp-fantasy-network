# TODO

## Immediate

- [ ] Verify the homepage format filters work correctly in Chrome after cache-busting.
- [ ] Confirm league cards render in internal ID order within each format, especially `RD1`, `RD2`, `RD3`.
- [ ] Continue populating `data/leagues.json` with real Sleeper league IDs, invite links, and LeagueSafe links for all active leagues.
- [ ] Add missing `leagueSafeLink` values for the remaining leagues.
- [ ] IMPORTANT: create and add the dynasty LeagueSafe links later; these still need to be set up before `DYN1-DYN3` can be completed.
- [ ] Decide whether the homepage should visibly expose LeagueSafe links or keep them as stored data only for now.

## League Data Migration

- [ ] Replace placeholder or manual `filled` values with Sleeper-synced values wherever a valid `sleeperLeagueId` exists.
- [ ] Populate `sleeperLeagueId` for dynasty, bracket, and best ball leagues where available.
- [ ] Confirm each league entry points to the correct `constitutionPage`.
- [ ] Review `status` values across all leagues so `open`, `full`, and `coming-soon` are consistent.
- [ ] Decide whether `division` should be displayed anywhere for bracket leagues.

## Donation Section

- [ ] Decide whether to keep donations on Google Sheets or migrate donations to local JSON later.
- [ ] Verify the donation progress bars and donation CSV parsing against the live published sheet.

## Constitutions

- [ ] Continue cleaning encoding issues in constitution pages where visible text still looks corrupted.
- [ ] Review constitution pages for duplicate or noisy generated formatting artifacts.
- [ ] Confirm banner images and “Back to Hub” links render correctly on all constitution pages.

## Cleanup / Future Improvements

- [ ] Add a small documented workflow for updating `data/leagues.json` from the intake template.
- [ ] Consider adding a script later to help merge Sleeper API data into local league records.
- [ ] Decide whether to keep planned empty formats visible in Active Leagues or hide them until launched.

## Automation Recommendations

- [ ] Add a small local script to parse a Sleeper league URL and auto-fill `sleeperLeagueId` into a league record.
- [ ] Add a local sync script that refreshes Sleeper-derived fields such as league name, team count, and filled spots for all leagues with a `sleeperLeagueId`.
- [ ] Add a validation script for `data/leagues.json` to catch missing required fields, invalid formats, broken constitution page references, and malformed URLs before changes are pushed.
- [ ] Add a numbering helper that automatically assigns the next internal ID for a new league based on format prefix, such as `RD`, `DYN`, `BBU`, `RDB`, `KP`, or `CH`.
- [ ] Add a template-driven league intake script that asks the same standard questions and writes or updates the correct JSON entry automatically.
- [ ] Add a lightweight preview script that opens the local homepage with a cache-busting query string after league-data updates.
- [ ] Add a one-command check script that verifies `index.html`, `styles.css`, `app.js`, and `data/leagues.json` for common structural mistakes before commit.
- [ ] Consider adding a GitHub Action later to run JSON validation and basic link/path checks on every push.
- [ ] Consider adding a periodic sync workflow later, only if desired, to regenerate Sleeper-derived league fields automatically while preserving your manual fields like `inviteLink` and `leagueSafeLink`.
- [ ] Consider splitting league data into `manual` and `synced` sections later if the Sleeper automation becomes more important and you want clearer ownership of each field.
