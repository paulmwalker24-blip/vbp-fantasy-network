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
- missing `leagueSafeLink`
- missing `sleeperLeagueId`
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

Runs the validator plus additional static checks across `index.html`, `styles.css`, `app.js`, and linked constitution pages.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-site.ps1
```

Strict mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-site.ps1 -Strict
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
