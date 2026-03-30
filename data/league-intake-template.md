# League Intake Template

Use this for each league you want added or updated in `data/leagues.json`.

## Recommended Workflow

1. Start with `League type` first so the correct ID prefix and constitution page are obvious from the beginning.
2. If this is a new league, leave `Internal ID` blank and let `upsert-league-record.ps1` assign it, or run `get-next-league-id.ps1` first if you want to preview the suggested ID.
3. If you have a Sleeper league URL or invite link instead of a raw numeric ID, keep the URL. The local intake flow can resolve and store the `sleeperLeagueId` for you.
4. Write or update the record with the local intake script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\upsert-league-record.ps1
```

5. Validate the JSON after the change:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-leagues-json.ps1
```

6. If the league has a `sleeperLeagueId`, optionally refresh Sleeper-owned fields afterward:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-sleeper-leagues.ps1
```

Manual fields such as `inviteLink`, `leagueSafeLink`, `constitutionPage`, `buyIn`, and curated public names should still be reviewed before pushing changes.

- League type first: `redraft`, `dynasty`, `bestball`, `bracket`, `keeper`, or `chopped`
- Internal ID: leave blank if this is a new league; infer it by format sequence
  - `redraft` -> `RD1`, `RD2`, `RD3`
  - `dynasty` -> `DYN1`, `DYN2`, `DYN3`
  - `bestball` -> `BBU1`, `BBU2`, `BBU3`
  - `bracket` -> `RDB1`, `RDB2`, `RDB3`
  - `keeper` -> `KP1`, `KP2`, `KP3`
  - `chopped` -> `CH1`, `CH2`, `CH3`
- Sleeper league ID:
- Sleeper season:
- Public league name:
- Format:
- Draft style (optional, non-bracket only): `fast`, `slow`, or blank
- Division / draft type (bracket only):
- Buy-in:
- Team count:
- Filled spots:
- Status: `open`, `full`, or `coming-soon`
- Invite link:
- LeagueSafe link:
- Future-season LeagueSafe links (optional, `season=url` pairs such as `2027=https://...`):
- Constitution page:
- Notes:

