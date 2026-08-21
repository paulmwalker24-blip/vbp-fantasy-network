# Discord Division Leaders

The division-leaders channel is maintained by `.github/workflows/discord-division-leaders.yml`.

The workflow reads live Sleeper rosters for BBU1 through BBU13. It maintains one persistent Discord card containing each division's current first-place team, record, and points for. Standings use record percentage first and points for to two decimal places second.

Before any completed games exist, the card says that no leader has been established instead of selecting an arbitrary 0-0 team.

## Schedule

The card refreshes every day at 2:10 PM in the `America/Chicago` timezone. Manual GitHub runs default to a safe dry run.

## Configuration

- Public configuration: `data/discord-division-leaders-config.json`
- Persistent message state: `data/discord-division-leaders-state.json`
- GitHub secret: `DISCORD_WEBHOOK_DIVISION_LEADERS`
- GitHub enable variable: `DISCORD_DIVISION_LEADERS_ENABLED=true`

The webhook URL remains in GitHub Secrets. Before posting, the publisher verifies that the webhook belongs to channel `1540364355772616794`.

## Manual preview

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\post-discord-division-leaders.ps1 -DryRun
```
