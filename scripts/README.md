# Local Scripts

## `run-100yardrush.ps1`

Creates a 100 Yard Rush replay URL without writing any repo data.

By default it uses the VBP draft-order settings:

- 3 to 8 yards per rush
- 2 to 6 seconds per rush
- Fast speed
- no luck

If no names are passed, it pulls manager names from the league's Sleeper draft order first, then assigned rosters as a fallback.

Run BBU7 from Sleeper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-100yardrush.ps1 -LeagueRecordId BBU7
```

Run with an explicit manager list:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-100yardrush.ps1 -LeagueRecordId BBU7 -ManagerNames ManagerOne,ManagerTwo,ManagerThree,ManagerFour,ManagerFive,ManagerSix,ManagerSeven,ManagerEight,ManagerNine,ManagerTen
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-100yardrush.ps1 -LeagueRecordId BBU7 -PassThru | ConvertTo-Json -Depth 5
```

## `set-sleeper-league-id.ps1`

Parses a Sleeper league URL, Sleeper invite link, or raw numeric league ID and writes the resulting `sleeperLeagueId` into a league record inside `data/leagues.json`.

Examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-sleeper-league-id.ps1 -LeagueRecordId CH1 -SleeperInput "https://sleeper.com/leagues/1339342261023961088/predraft"
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-sleeper-league-id.ps1 -LeagueRecordId BBU5 -SleeperInput "1339095453291003904"
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-sleeper-league-id.ps1 -LeagueRecordId DYN3 -SleeperInput "https://sleeper.com/i/E8a1K6DqnARY0"
```

Optional output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-sleeper-league-id.ps1 -LeagueRecordId DYN2 -SleeperInput "https://sleeper.com/leagues/1340820529996640256/predraft" -PassThru
```

## `sync-sleeper-leagues.ps1`

Refreshes Sleeper-derived fields for every league that has a `sleeperLeagueId`, then prints a local report showing:

- which leagues synced successfully
- which fields changed
- which leagues are missing required manual data
- which records need review because local values differ from Sleeper

By default it updates:

- `sleeperSeason`
- `teams`
- `sleeperFilled`

It does not overwrite local published `filled`, names, or statuses unless you opt in.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-sleeper-leagues.ps1
```

Include the JSON report in output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-sleeper-leagues.ps1 -PassThru | ConvertTo-Json -Depth 6
```

Opt in to syncing local status:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-sleeper-leagues.ps1 -UpdateStatus
```

Opt in to syncing local display names from Sleeper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-sleeper-leagues.ps1 -UpdateNames
```

Opt in to overwriting local published `filled` from Sleeper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-sleeper-leagues.ps1 -UpdateFilledFromSleeper
```

## `league-occupancy-report.ps1`

Prints a quick commissioner-facing snapshot of local league occupancy from `data/leagues.json`.

Use this when you want one place to check the published `filled` count for every league without reading JSON manually.

If `sleeperFilled` is present, the report also shows the Sleeper owner-assigned roster count for comparison.

Examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\league-occupancy-report.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\league-occupancy-report.ps1 -OpenOnly
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\league-occupancy-report.ps1 -PassThru | ConvertTo-Json -Depth 5
```

## `validate-leagues-json.ps1`

Runs local structural validation against `data/leagues.json` without calling Sleeper.

It checks for:

- duplicate league IDs
- invalid formats or statuses
- invalid optional `draftStyle` values
- bad ID prefixes for the chosen format
- invalid or missing URLs
- impossible `filled` / `teams` values
- missing `constitutionPage`
- `constitutionPage` values that do not match the league format
- missing `leagueSafeLink` on non-`coming-soon` records
- missing `sleeperLeagueId` on non-`coming-soon` records
- bracket leagues missing draft type in `division`
- bracket leagues incorrectly using `draftStyle` instead of `division`

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-leagues-json.ps1
```

JSON report output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-leagues-json.ps1 -PassThru | ConvertTo-Json -Depth 6
```

Fail the command if validation finds errors:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-leagues-json.ps1 -Strict
```

## `upsert-league-record.ps1`

Creates a new league record or updates an existing one inside `data/leagues.json`.

For new records, the intake flow now pre-suggests likely defaults based on format and current repo data, including:

- the next internal ID for the chosen format
- the expected `constitutionPage`
- the common team count for that format
- the latest known `sleeperSeason`
- the most common same-format `buyIn`, `status`, and draft settings when available

Examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1 -Mode new -LeagueType dynasty
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1 -Mode update -LeagueRecordId KP1
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1 -Mode new -LeagueType bestball -PassThru | ConvertTo-Json -Depth 5
```

## `validate-donations-json.ps1`

Runs local structural validation against `data/donations.json`.

It checks for:

- a valid `projects` array
- missing `name`, `state`, `goal`, `donated`, `remaining`, or `link` values
- invalid or duplicate DonorsChoose links
- non-numeric or impossible donation amounts
- optional live DonorsChoose link health when requested

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-donations-json.ps1
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-donations-json.ps1 -PassThru | ConvertTo-Json -Depth 6
```

Include live link checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-donations-json.ps1 -CheckLinks
```

Fail the command if validation finds errors:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-donations-json.ps1 -Strict
```

## `bump-cache-bust.ps1`

Updates the `assets/css/styles.css?v=` and `assets/js/app.js?v=` query strings in `index.html` to a shared version token.

Use this after frontend changes when browser caching is getting in the way.

Default timestamp-based version:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bump-cache-bust.ps1
```

Set a specific version value:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bump-cache-bust.ps1 -Version 20260323a
```

Preview the change without writing the file:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bump-cache-bust.ps1 -WhatIf -PassThru | ConvertTo-Json -Depth 4
```

## `sync-keeper-ledger.ps1`

Builds or refreshes `data/keeper-ledger.json` by pulling current keeper-league manager data from Sleeper for every keeper league that already has a `sleeperLeagueId`.

It preserves manual keeper-slot fields and notes while refreshing:

- keeper league identity
- Sleeper league name
- current managers
- current roster players for each manager
- roster IDs
- display names
- usernames
- team names when available

Use this when you want a commissioner worksheet in the repo explorer that you can fill in with keeper declarations and keeper rounds.

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-keeper-ledger.ps1
```

Sync only specific keeper leagues:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-keeper-ledger.ps1 -LeagueRecordIds KP1,KP2
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-keeper-ledger.ps1 -PassThru | ConvertTo-Json -Depth 6
```

## `reconcile-bbu-payments.ps1`

Builds private commissioner-readable reports that cross-reference Best Ball Union Sleeper managers against local LeagueSafe payment rows and saved identity matches.

Private inputs live under `data/private/` and are ignored by git:

- `manager-identities.json`
- `leaguesafe-payments.csv`

The script writes only the readable BBU reports under `reports/private/bbu-payment-reconciliation/`, also ignored by git.

The script now stops without replacing existing reconciliation outputs if any live Sleeper league pull fails. Use `-AllowPartialSleeperData` only when an intentionally incomplete diagnostic report is needed.

Readable outputs:

- `bbu-master-readable.txt` - room-by-room BBU payment master with short status labels.
- `bbu-needs-attention-readable.txt` - concise list of payment matches, shortfalls, or paid rows that still need commissioner review.

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reconcile-bbu-payments.ps1
```

Reconcile only BBU4:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reconcile-bbu-payments.ps1 -LeagueRecordIds BBU4
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reconcile-bbu-payments.ps1 -PassThru | ConvertTo-Json -Depth 6
```

## `refresh-bbu-payment-center.ps1`

Runs the routine BBU workflow in one command: optionally imports a new LeagueSafe CSV, reconciles current Sleeper identities, and regenerates the readable BBU payment reports.

The consolidated BBU workflow no longer writes routine CSV exports, Excel workbooks, or the broad `PAYMENT-CENTER/` tree.

Quick refresh using the already imported BBU export:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\refresh-bbu-payment-center.ps1
```

Import a new export and refresh the readable BBU reports:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\refresh-bbu-payment-center.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBP's Best Ball Union 2026 payment details (8).csv"
```

## `import-leaguesafe-export.ps1`

Imports the latest LeagueSafe payment-details CSV for any single league into the organized private path `data/private/payments/exports/<LEAGUE-ID>-current.csv`. Use `-PaymentPeriod 2027` for separate future-season collections, which are stored as `<LEAGUE-ID>-2027.csv` instead of overwriting current data.

The raw CSV remains local-only and ignored by git. Shared-pot formats such as Best Ball Union and Redraft Bracket retain their specialized import/reconciliation workflows because one payment export covers several public league records.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-leaguesafe-export.ps1 -LeagueRecordId DYN8 -SourcePath "C:\Users\pkwal\Downloads\VBP Dynasty League #8 (Slow Draft) payment details (1).csv"
```

## `reconcile-league-payments.ps1`

Cross-references a league's imported LeagueSafe export or exports with current Sleeper roster ownership and the private `manager-identities.json` ledger. Separate payment-period files for the same league are totaled together. Optional local-only `data/private/payment-status-overrides.json` entries preserve commissioner notes such as a departed owner awaiting a LeagueSafe refund without altering the imported export. It writes Excel-friendly private outputs under `reports/private/payments/<LEAGUE-ID>/`:

- `tracker.csv` - each Sleeper assignment and its matched, candidate, or missing LeagueSafe row
- `unmatched-leaguesafe-rows.csv` - payment rows that are not yet confidently tied to an assigned Sleeper roster
- `summary.md` - a quick count of paid, review-needed, and unmatched records

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reconcile-league-payments.ps1 -LeagueRecordId DYN8
```

## `build-payment-index.ps1`

Creates a private network-wide index from `data/leagues.json`, noting whether each league has an imported individual export, an existing shared-pool export, or still needs a LeagueSafe file imported. It writes `reports/private/payments/README.md` and `league-payment-index.csv`.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-payment-index.ps1
```

## `build-commissioner-payment-center.ps1`

Creates the Explorer-friendly, private top-level `PAYMENT-CENTER/` folder. It combines generated reconciliation reports and the confirmed identity ledger into:

- `START-HERE.md` - landing page
- `ALL-LEAGUES-PAYMENT-INDEX.md` - readable links to every league page
- `MASTER-CONFIRMED-MANAGERS.md` - readable reusable confirmed Sleeper/LeagueSafe identities
- `MASTER-MANAGER-DIRECTORY.md` - running cross-league lookup with confirmed identities plus paid names still waiting for a Sleeper match
- `CSV-EXPORTS/BBU-UNMATCHED-SLEEPER-MANAGERS.csv` - unique unmatched BBU Sleeper identities, including unassigned waiting-room members
- `LEAGUES/<LEAGUE-ID> - <LEAGUE-NAME>.md` - one readable payment page per league, with a placeholder reminder until its export is imported
- `CSV-EXPORTS/` - separate spreadsheet-friendly versions

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-commissioner-payment-center.ps1
```

## `import-bbu-leaguesafe-export.ps1`

Copies the latest downloaded Best Ball Union LeagueSafe export into `data/private/leaguesafe-bbu-current.csv`, then rewrites `data/private/leaguesafe-payments.csv` with the paid rows used by reconciliation.

Use this whenever a newer LeagueSafe payment export is downloaded.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-bbu-leaguesafe-export.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBP's Best Ball Union 2026 payment details (2).csv"
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-bbu-leaguesafe-export.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBP's Best Ball Union 2026 payment details (2).csv" -PassThru | ConvertTo-Json -Depth 4
```

## `import-redraft-bracket-leaguesafe-export.ps1`

Copies the latest downloaded Redraft Bracket LeagueSafe export into `data/private/leaguesafe-bracket-current.csv`, then rewrites `data/private/leaguesafe-bracket-payments.csv` with the paid rows used by reconciliation.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-redraft-bracket-leaguesafe-export.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBPs Redraft Bracket League 2026 payment details.csv"
```

## `import-gauntlet-leaguesafe-export.ps1`

Copies the latest downloaded Best Ball Gauntlet LeagueSafe export into `data/private/leaguesafe-gauntlet-current.csv`, then rewrites `data/private/leaguesafe-gauntlet-payments.csv` with the paid rows for BG1.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-gauntlet-leaguesafe-export.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBP Bestball Gauntlet #1 payment details.csv"
```

## `reconcile-redraft-bracket-payments.ps1`

Builds private Redraft Bracket payment reconciliation CSV files from Sleeper RDB league managers, the Redraft Bracket LeagueSafe paid rows, and saved identity matches.

It writes readable bracket-specific files under `reports/private/redraft-bracket-payment-reconciliation/`:

- `redraft-bracket-master-readable.txt` - plain-text grouped view for quick commissioner review in the editor.
- `redraft-bracket-paid-not-assigned-readable.txt` - plain-text unmatched paid list.

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reconcile-redraft-bracket-payments.ps1
```

## `export-bbu-payment-workbook.ps1`

Builds a formatted Excel workbook from the private BBU reconciliation CSV files.

The workbook includes formatted tabs for:

- Action Tracker
- Bracket Tracker
- Bracket Paid Not Assigned
- Gauntlet Payments
- Person Summary
- Sleeper Entries
- LeagueSafe Export
- Unmatched Payments

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-bbu-payment-workbook.ps1
```

Build and open the workbook:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-bbu-payment-workbook.ps1 -Open
```

## `sync-bracket-ledger.ps1`

Builds or refreshes `data/bracket-ledger.json` by pulling current manager and standings data from Sleeper for grouped bracket leagues.

Group membership is defined in `data/bracket-groups.json`, so multiple `RDB` leagues can be treated as one combined tournament set.

The same script can also power alternate grouped bracket centers, including the dynasty-bracket setup, by pointing it at a different groups file and ledger output path.

It currently outputs:

- grouped bracket league snapshots
- division-winner seeding for Seeds `1-5`
- direct-qualifier seeding for Seeds `6-30`
- wild-card selection for Seeds `31-32`
- a flat combined `overallStandings` list for quick 1-60 style review
- Week 13 matchup output
- a post-Week-13 static bracket template

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1
```

Sync only one bracket group:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1 -GroupIds BRACKET-2026-1
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1 -PassThru | ConvertTo-Json -Depth 8
```

Dynasty bracket usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1 -GroupsPath .\data\dynasty-bracket-groups.json -LedgerPath .\data\dynasty-bracket-ledger.json
```

Sync only the dynasty bracket group:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1 -GroupsPath .\data\dynasty-bracket-groups.json -LedgerPath .\data\dynasty-bracket-ledger.json -GroupIds DYNASTY-BRACKET-2026-1
```

## `sync-power-rankings.ps1`

Builds or refreshes `data/power-rankings.json` by pulling detailed power-ranking inputs from Sleeper.

The sync automatically reads each league's Sleeper draft records and determines whether the relevant board is ready:

- startup drafts for new dynasty, dynasty-bracket, and keeper rooms
- rookie drafts for existing dynasty rooms when Sleeper marks the draft as rookie-only
- regular drafts for redraft, best ball, bracket redraft, and chopped rooms

Published boards are generated only after Sleeper reports the relevant draft data as complete. Pending leagues remain in the JSON with a `draftReadiness` explanation so the public rankings hub can show why a board is still locked.

Every refresh reads the current Sleeper roster endpoint for each league and writes a `rosterSync` block with the API source URL, refresh timestamp, Sleeper season/status, roster count, and player count. Use this to confirm the public board is based on the current stored Sleeper league ID.

The generated dataset combines:

- live league scoring settings and roster positions
- users and rosters
- draft status and draft-pick data
- Sleeper NFL player metadata
- injury/status flags exposed by Sleeper
- optimized starters and bench snapshots
- commissioner-owned overrides from `data/power-ranking-overrides.json`

The player and team calculations follow `docs/vbp-power-ranking-model.md`: the script verifies live reception/yardage/TD/interception settings first and publishes clean owner ranking boards. It records a format profile for dynasty, dynasty bracket, Best Ball Union, Gauntlet, Keeper, Chopped, Redraft, and Bracket boards so roster construction and risk are interpreted correctly. Dynasty owner scores use a fixed within-league display scale from their calculated strength difference, rather than points assigned by rank. Positional boards rank owners at each available position without publishing individual player lists. Sleeper metadata is not stat-component projection data, so generated scores are value signals rather than claimed projected fantasy points.

Each standard dynasty league publishes two owner boards from the same live roster pull. Its standard Dynasty Outlook includes long-term player value and future draft capital. Its `currentSeasonRankings` board measures current-season contention only, emphasizing the strongest legal lineup, usable depth, Superflex quarterback strength, health, and league scoring while excluding age runway and future picks.

Use `data/power-ranking-overrides.json` for facts Sleeper cannot reliably know, such as a commissioner publish hold, a schedule-context adjustment, or a manually reviewed player injury/value note.

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-power-rankings.ps1
```

Sync only DYN1:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-power-rankings.ps1 -LeagueRecordIds DYN1
```

Include pending or held leagues in the output for commissioner review:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-power-rankings.ps1 -IncludePending
```

Publish in-progress drafting leagues from the latest Sleeper rosters endpoint:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-power-rankings.ps1 -PublishDrafting
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-power-rankings.ps1 -LeagueRecordIds DYN1 -PassThru | ConvertTo-Json -Depth 10
```

## `export-bracket-report.ps1`

Builds a commissioner-friendly text standings report from `data/bracket-ledger.json`.

It currently outputs:

- a `DIVISION PLAYOFF COUNTS` section showing how many teams from each bracket league are in the tracked playoff field
- a `FULL COMBINED STANDINGS` section listing every currently tracked team in rank order
- status labels for each team: `Division Leader`, `In`, `Wild Card`, or `Out`
- a short notes block, including whether the current report is provisional

Default usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-bracket-report.ps1
```

Set a week label:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-bracket-report.ps1 -WeekLabel "Week 9"
```

Write the report to a file:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-bracket-report.ps1 -WeekLabel "Week 9" -OutputPath .\reports\bracket-week-9.txt
```

## `get-next-league-id.ps1`

Returns the next suggested internal ID for a given format based on the existing records in `data/leagues.json`.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\get-next-league-id.ps1 -Format chopped
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\get-next-league-id.ps1 -Format bracket -PassThru | ConvertTo-Json -Depth 4
```

## `open-preview.ps1`

Starts `localhost` if needed, then opens the requested page in Chrome with a cache-busting query string.

Homepage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\open-preview.ps1
```

Specific page:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\open-preview.ps1 -Target chopped-constitution.html
```

## `check-site.ps1`

Runs the validators plus additional static checks across `index.html`, `assets/css/styles.css`, `assets/js/app.js`, league data, donation data, and linked constitution pages.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-site.ps1
```

Strict mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-site.ps1 -Strict
```

## `league-data-diff-report.ps1`

Compares two league JSON snapshots and prints a human-readable summary of added, removed, and changed league records.

Use this after a sync run or manual edit when you want a cleaner review than raw JSON diff output.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\league-data-diff-report.ps1 -BeforePath .\snapshots\leagues-before.json
```

Compare two explicit files:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\league-data-diff-report.ps1 -BeforePath .\snapshots\leagues-before.json -AfterPath .\snapshots\leagues-after.json
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\league-data-diff-report.ps1 -BeforePath .\snapshots\leagues-before.json -PassThru | ConvertTo-Json -Depth 8
```

## `release-helper.ps1`

Runs the broad site check, optionally opens a localhost preview, and summarizes whether the site is ready to push.

Default behavior:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release-helper.ps1
```

Run without opening Chrome:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release-helper.ps1 -NoOpen
```

Skip preview and only summarize release readiness:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release-helper.ps1 -NoPreview
```

Treat warnings as blocking:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release-helper.ps1 -TreatWarningsAsBlocking -Strict
```

## `check-constitutions.ps1`

Runs static checks across every `*-constitution.html` page in the repo.

It verifies:

- the `Back to Hub` link exists and points to `index.html#constitutions`
- the constitution banner image exists and references a real local asset
- the page includes the expected hero, summary, and table-of-contents structure
- section cards have ids
- table-of-contents links point to real section ids
- `Back to top` links are present

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-constitutions.ps1
```

Structured output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-constitutions.ps1 -PassThru | ConvertTo-Json -Depth 6
```

Strict mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-constitutions.ps1 -Strict
```

## `upsert-league-record.ps1`

Guided intake script for creating a new league record or updating an existing one in `data/leagues.json`.

It can:

- prompt for the standard intake fields
- assign the next internal ID automatically for new leagues
- parse a Sleeper URL or invite link into `sleeperLeagueId`
- store an optional non-bracket `draftStyle` value for homepage card pills
- write the record
- run the validator afterward

Interactive usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1
```

Create a new league with parameters:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1 -Mode new -LeagueType chopped -PublicLeagueName "VBP Chopped League #2" -SleeperInput "https://sleeper.com/leagues/1234567890/predraft" -SleeperSeason 2026 -DraftStyle slow -BuyIn 15 -TeamCount 18 -FilledSpots 0 -Status open -InviteLink "https://sleeper.com/i/example" -LeagueSafeLink "https://www.leaguesafe.com/join/example" -ConstitutionPage chopped-constitution.html
```

Update an existing record:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1 -Mode update -LeagueRecordId CH1
```

Suggested workflow:

1. Start from `data/league-intake-template.md`.
2. Run `upsert-league-record.ps1` to write the change.
3. Run `validate-leagues-json.ps1`.
4. If the record has a `sleeperLeagueId`, run `sync-sleeper-leagues.ps1` if you want Sleeper-owned fields refreshed before commit.

## `create-general-thumbnail.ps1`

Builds a general square Sleeper-friendly thumbnail image from the existing site banner and format artwork.

Default output:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create-general-thumbnail.ps1
```

Custom output path:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create-general-thumbnail.ps1 -OutputPath assets\images\sleeper-thumbnail-v2.png
```
