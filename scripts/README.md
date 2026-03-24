# Local Scripts

## `set-sleeper-league-id.ps1`

Parses a Sleeper league URL or raw numeric league ID and writes the resulting `sleeperLeagueId` into a league record inside `data/leagues.json`.

Examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-sleeper-league-id.ps1 -LeagueRecordId CH1 -SleeperInput "https://sleeper.com/leagues/1339342261023961088/predraft"
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-sleeper-league-id.ps1 -LeagueRecordId BBU5 -SleeperInput "1339095453291003904"
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
- `filled`

It does not overwrite local names or statuses unless you opt in.

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

## `validate-leagues-json.ps1`

Runs local structural validation against `data/leagues.json` without calling Sleeper.

It checks for:

- duplicate league IDs
- invalid formats or statuses
- bad ID prefixes for the chosen format
- invalid or missing URLs
- impossible `filled` / `teams` values
- missing `constitutionPage`
- `constitutionPage` values that do not match the league format
- missing `leagueSafeLink` on non-`coming-soon` records
- missing `sleeperLeagueId` on non-`coming-soon` records
- bracket leagues missing draft type in `division`

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

Updates the `styles.css?v=` and `app.js?v=` query strings in `index.html` to a shared version token.

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

## `sync-bracket-ledger.ps1`

Builds or refreshes `data/bracket-ledger.json` by pulling current manager and standings data from Sleeper for grouped bracket leagues.

Group membership is defined in `data/bracket-groups.json`, so multiple `RDB` leagues can be treated as one combined tournament set.

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

Runs the validators plus additional static checks across `index.html`, `styles.css`, `app.js`, league data, donation data, and linked constitution pages.

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
- parse a Sleeper URL into `sleeperLeagueId`
- write the record
- run the validator afterward

Interactive usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1
```

Create a new league with parameters:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1 -Mode new -LeagueType chopped -PublicLeagueName "VBP Chopped League #2" -SleeperInput "https://sleeper.com/leagues/1234567890/predraft" -SleeperSeason 2026 -BuyIn 15 -TeamCount 18 -FilledSpots 0 -Status open -InviteLink "https://sleeper.com/i/example" -LeagueSafeLink "https://www.leaguesafe.com/join/example" -ConstitutionPage chopped-constitution.html
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
powershell -ExecutionPolicy Bypass -File .\scripts\create-general-thumbnail.ps1 -OutputPath sleeper-thumbnail-v2.png
```
