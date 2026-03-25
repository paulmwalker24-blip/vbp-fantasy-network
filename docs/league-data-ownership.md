# League Data Ownership

This document captures the current field ownership model for `data/leagues.json` and the recommended future split if Sleeper automation becomes more important.

## Current Model

Today, all league data lives in a single flat record inside `data/leagues.json`.

Example fields currently treated as manual:

- `name`
- `buyIn`
- `inviteLink`
- `leagueSafeLink`
- `leagueSafeLinksBySeason` (optional, when a league needs separate future-season LeagueSafe links)
- `constitutionPage`
- `division`
- `notes`

Example fields currently treated as Sleeper-derived:

- `sleeperLeagueId`
- `sleeperSeason`
- `teams`
- `filled`
- `status` can be reviewed against Sleeper, but is still locally controlled by default

## Why A Future Split Could Help

As more scripts are added, the biggest risk is accidental overlap between:

- fields the commissioner curates manually
- fields that can be refreshed from Sleeper

A split would make ownership explicit and reduce accidental overwrites.

## Suggested Future Shape

```json
{
  "id": "CH1",
  "format": "chopped",
  "manual": {
    "name": "VBP Chopped League #1",
    "buyIn": 15,
    "inviteLink": "https://sleeper.com/i/Y2VKoEON1XkqR",
    "leagueSafeLink": "https://www.leaguesafe.com/join/4404482",
    "constitutionPage": "chopped-constitution.html",
    "division": "",
    "notes": ""
  },
  "synced": {
    "sleeperLeagueId": "1339342261023961088",
    "sleeperSeason": "2026",
    "teams": 18,
    "filled": 1,
    "status": "open"
  }
}
```

## Migration Guidance

If this split is implemented later:

1. Keep `id` and `format` at the top level for sorting and filtering.
2. Move commissioner-owned fields into `manual`.
3. Move Sleeper-refreshed fields into `synced`.
4. Update `assets/js/app.js` to normalize from the nested shape back into the current render model.
5. Update local scripts so they only touch `synced`.
6. Preserve backward compatibility during the transition if existing tools still expect the flat shape.

## Current Recommendation

Do not migrate yet unless:

- Sleeper sync becomes a routine maintenance task
- manual and synced values start conflicting often
- multiple people begin editing league data

Until then, keep using the current flat structure plus the local scripts in `scripts/` to enforce ownership in practice.

For the current dynasty payment workflow, keep the present-season LeagueSafe URL in `leagueSafeLink` and store future-season dynasty LeagueSafe URLs in `leagueSafeLinksBySeason`.
