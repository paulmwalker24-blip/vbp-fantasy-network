# League Data Ownership

This document captures the current field ownership model for `data/leagues.json` and the recommended future split if Sleeper automation becomes more important.

## Current Model

Today, all league data lives in a single flat record inside `data/leagues.json`.

The homepage now normalizes every row into a render model before display. That keeps the public card rendering insulated from the flat storage shape and makes field ownership explicit even before a future nested migration.

### Commissioner-Owned Fields

These are the fields the site should trust as curated public or operational values unless a script is explicitly run with an overwrite option:

- `name`
- `draftStyle` (optional, for non-bracket leagues that should show a fast/slow draft pill)
- `buyIn`
- `filled` as the commissioner-published occupancy count shown on the site
- `inviteLink`
- `leagueSafeLink`
- `leagueSafeLinksBySeason` (optional, when a league needs separate future-season LeagueSafe links)
- `constitutionPage`
- `division`
- `notes`
- `status`
- `lastUpdated`

### Sleeper Reference Fields

These fields may be refreshed from Sleeper or resolved from Sleeper links, but they should not silently overwrite commissioner-owned fields:

- `sleeperLeagueId`
- `sleeperSeason`
- `teams`
- `sleeperFilled` (optional reference copy of Sleeper owner-assigned roster count)

### Homepage Render Model

`assets/js/app.js` converts each stored record into the shape the cards actually use:

- normalized `format`
- normalized `draftStyle`
- capped commissioner-published `filled`
- optional reference `sleeperFilled`
- computed `spotsLeft`
- safe public `link`
- `liveSyncEligible`
- `liveSyncState`, one of `manual`, `live`, or `fallback`

Sleeper hydration can update live `teams`, `sleeperFilled`, and `sleeperSeason` in the browser for reference/sync status. It should not replace the commissioner-published `filled` count unless a maintenance script is run with an explicit overwrite option.

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
    "draftStyle": "slow",
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
    "sleeperFilled": 1,
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

Do not migrate the JSON storage shape yet unless:

- Sleeper sync becomes a routine maintenance task
- manual and synced values start conflicting often
- multiple people begin editing league data

Until then, keep using the current flat structure, the homepage normalization layer, and the local scripts in `scripts/` to enforce ownership in practice.

For the current dynasty payment workflow, keep the present-season LeagueSafe URL in `leagueSafeLink` and store future-season dynasty LeagueSafe URLs in `leagueSafeLinksBySeason`.

## Current Practical Rule

- `filled` is the commissioner-published occupancy number you want the site and local copy to trust.
- `sleeperFilled` is optional reference data from Sleeper showing how many rosters currently have an `owner_id`.
- `sync-sleeper-leagues.ps1` should refresh `sleeperFilled` by default and only overwrite `filled` when you explicitly opt in.
