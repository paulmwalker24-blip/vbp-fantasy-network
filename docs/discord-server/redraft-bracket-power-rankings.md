# Redraft Bracket Discord Power Rankings

The Redraft Bracket power-ranking channel is maintained by `.github/workflows/redraft-bracket-power-rankings-discord.yml`.

## Schedule

The workflow runs every Tuesday at 1:30 AM in the `America/Chicago` timezone, shortly after the weekly standings refresh. GitHub handles the CST/CDT change through the workflow's timezone-aware schedule.

The scheduled job:

1. Builds a fresh RDB1-RDB5 ranking snapshot from Sleeper with the official power-ranking generator.
2. Validates Titan, Apex, Iron, Vanguard, and Dominion as five complete 12-team divisions.
3. Combines their 60 comparable roster grades into one Top 20.
4. Updates one persistent Discord card instead of posting a new message each week.
5. Commits the Discord message state so future runs edit the same message.

The Discord snapshot is generated in the runner's temporary directory. It does not overwrite the network-wide `data/power-rankings.json`; the existing daily rankings workflow remains responsible for that public website dataset. This prevents a failed request for an unrelated league from truncating the website data during a Discord update.

## Publication rules

Before every division draft is complete, Discord shows one waiting card with each division's current draft status. It never publishes a partial or sample Top 20.

Once all five drafts are complete, the card displays ranks 1-20 in four plain-text groups. Each row includes the manager/team name, division, and current record. Internal roster-strength scores are used to order the rankings but are not displayed in Discord.

If a later Sleeper refresh is incomplete or one division is missing, the publisher fails closed and leaves the last valid Top 20 in Discord.

## Configuration and secrets

- Public channel and group configuration: `data/discord-redraft-bracket-power-rankings-config.json`
- Persistent Discord message ID: `data/discord-redraft-bracket-power-rankings-state.json`
- GitHub Actions secret: `DISCORD_WEBHOOK_REDRAFT_BRACKET_POWER_RANKINGS`
- GitHub Actions enable variable: `DISCORD_REDRAFT_BRACKET_POWER_RANKINGS_ENABLED=true`

The webhook URL must remain in GitHub Secrets only. The publisher validates that the webhook belongs to the configured channel before creating or editing a message.

## Manual verification

Preview current generated data without posting:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\post-discord-redraft-bracket-power-rankings.ps1 -DryRun
```

Refresh from Sleeper first, then preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-power-rankings.ps1 -PublishDrafting
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\post-discord-redraft-bracket-power-rankings.ps1 -DryRun
```

Manual GitHub workflow runs default to dry-run mode. Set `dry_run` to `false` only when the Discord channel should be updated.
