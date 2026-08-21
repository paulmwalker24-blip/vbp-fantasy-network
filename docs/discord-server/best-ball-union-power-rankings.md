# Best Ball Union Discord Power Rankings

The Best Ball Union power-ranking channel uses one persistent Discord message containing the combined Top 25 across `BBU1` through `BBU13`.

## Behavior

- A fresh temporary ranking snapshot is generated from Sleeper before every publish.
- All 13 completed rooms contribute 10 teams, producing a 130-team comparison pool.
- Only ranks 1-25 are displayed, in five compact five-team fields.
- Scores are custom-scoring, projection-derived locked-roster grades out of 100, not projected standings.
- Every matching Sleeper stat projection is multiplied by the live BBU scoring coefficient before lineup, depth, ceiling, and injury grading.
- The same Discord message is edited on later refreshes.
- Incomplete or malformed ranking data fails closed and preserves the last valid Top 25.

## Files

- Publisher: `scripts/post-discord-best-ball-union-power-rankings.ps1`
- Config: `data/discord-best-ball-union-power-rankings-config.json`
- Message state: `data/discord-best-ball-union-power-rankings-state.json`
- Workflow: `.github/workflows/best-ball-union-power-rankings-discord.yml`

## Discord and GitHub

- Channel: `1540207093133344768`
- Repository secret: `DISCORD_WEBHOOK_BEST_BALL_UNION_POWER_RANKINGS`
- Enable variable: `DISCORD_BEST_BALL_UNION_POWER_RANKINGS_ENABLED=true`
- Schedule: Tuesday at 1:45 AM Central

The webhook URL must never be stored in a tracked file. Before publishing, the script verifies that the webhook belongs to the configured channel.

## Local Preview

Generate a fresh BBU-only snapshot, then preview the Top 25:

```powershell
& .\scripts\sync-power-rankings.ps1 `
  -LeagueRecordIds @('BBU1','BBU2','BBU3','BBU4','BBU5','BBU6','BBU7','BBU8','BBU9','BBU10','BBU11','BBU12','BBU13') `
  -OutputPath .\tmp\bbu-power-rankings-preview.json `
  -PublishDrafting

& .\scripts\post-discord-best-ball-union-power-rankings.ps1 `
  -RankingsPath .\tmp\bbu-power-rankings-preview.json `
  -DryRun
```
