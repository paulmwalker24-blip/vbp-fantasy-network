# Discord Best Ball Union High Scorer

The Best Ball Union high-scorer channel is maintained by `.github/workflows/discord-bbu-high-scorer.yml`.

The workflow maintains one persistent Discord card with the highest single-week score across BBU1 through BBU13. Each completed week shows the winning team, BBU room, and score. Exact ties are displayed together instead of being broken arbitrarily.

Before Week 1 results exist, the card displays a preseason notice. Historical completed-week winners remain on the same post, so the channel does not accumulate one message per week.

## Schedule

The card refreshes every Tuesday at 2:20 PM in the `America/Chicago` timezone, after the weekly standings and division-leaders updates. Manual GitHub runs default to a safe dry run.

## Configuration

- Public configuration: `data/discord-bbu-high-scorer-config.json`
- Persistent message and winner history: `data/discord-bbu-high-scorer-state.json`
- GitHub secret: `DISCORD_WEBHOOK_BBU_HIGH_SCORER`
- GitHub enable variable: `DISCORD_BBU_HIGH_SCORER_ENABLED=true`

The webhook URL remains in GitHub Secrets. Before posting, the publisher verifies that the webhook belongs to channel `1540365233636249692`.

## Manual preview

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\post-discord-bbu-high-scorer.ps1 -DryRun
```
