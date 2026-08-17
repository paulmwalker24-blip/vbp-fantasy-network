# Redraft Bracket Discord Standings

The Redraft Bracket standings channel is maintained by `.github/workflows/redraft-bracket-standings-discord.yml`.

## Schedule

The workflow runs every Tuesday at 1:00 AM in the `America/Chicago` timezone. GitHub handles the CST/CDT change through the workflow's timezone-aware schedule.

The scheduled job:

1. Runs `scripts/sync-bracket-ledger.ps1` for `BRACKET-2026-1`.
2. Validates that Titan, Apex, Iron, Vanguard, and Dominion each contain 12 tracked teams.
3. Builds the Discord standings from `data/bracket-ledger.json`.
4. Updates the existing Discord cards instead of posting a new set every week.
5. Commits the refreshed website ledger and Discord message state.

## Published cards

Before regular-season results exist, Discord receives one preseason card explaining when the standings will begin. The website's synthetic sample standings are never sent to Discord.

After completed games exist, the publisher maintains four persistent cards:

- weekly overview, division representation, and projected cut line
- ranks 1-20
- ranks 21-40
- ranks 41-60

Projected statuses match the website ledger: Division Leader, In, Wild Card, or Out. They are not described as clinched until an official clinch model exists.

## Configuration and secrets

- Public channel and group configuration: `data/discord-redraft-bracket-standings-config.json`
- Persistent Discord message IDs: `data/discord-redraft-bracket-standings-state.json`
- GitHub Actions secret: `DISCORD_WEBHOOK_REDRAFT_BRACKET_STANDINGS`
- GitHub Actions enable variable: `DISCORD_REDRAFT_BRACKET_STANDINGS_ENABLED=true`

The webhook URL must remain in GitHub Secrets only. The publisher validates that the webhook belongs to the configured channel before creating or editing a message.

## Manual verification

Preview from current ledger data without posting:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\post-discord-redraft-bracket-standings.ps1 -DryRun
```

Refresh the ledger first, then preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1 -GroupIds BRACKET-2026-1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\post-discord-redraft-bracket-standings.ps1 -DryRun
```

Manual GitHub workflow runs default to dry-run mode. Set `dry_run` to `false` only when the Discord channel should be updated.
