# Redraft Bracket Waiver Wire Tracker

The Discord waiver tracker maintains one compact network-wide message per Sleeper week in channel `1540122228199268352`.

## Scope

Only the five 2026 Redraft Bracket divisions are configured:

- `RDB1` - Titan
- `RDB2` - Apex
- `RDB3` - Iron
- `RDB4` - Vanguard
- `RDB5` - Dominion

Other VBP leagues are not part of this feed.

## Included Activity

`scripts/post-discord-waiver-tracker.ps1` checks Sleeper transaction Weeks 1-18 and summarizes:

- successful waiver claims with status `complete` or `completed`
- completed free-agent pickups
- completed drop-only roster moves
- players added and dropped in the move
- the FAAB bid when Sleeper provides one, otherwise waiver priority or free-agent method
- the manager or team, division, transaction timestamp, and direct Sleeper league link

Pending and failed waiver claims are ignored. The weekly recap shows the five largest successful FAAB bids and one short activity line for each division. Routine moves remain counted without making the message grow indefinitely. `data/discord-waiver-tracker-state.json` stores transaction IDs, a weekly signature, and the single Discord message ID for each network recap.

The first live run is safe by default: existing moves are recorded without being posted unless `-IncludeHistorical` is supplied. `-MigrateIndividualMessages` also consolidates older per-transaction or per-division webhook posts by editing one retained weekly message and removing the superseded messages.

## Credentials

The real webhook must remain private:

- Local: add `channels.waiver-tracker` to ignored `data/private/discord-webhooks.json`.
- GitHub Actions: add repository secret `DISCORD_WEBHOOK_WAIVER_TRACKER`.

Before any post, the script reads the webhook metadata and refuses to continue unless its `channel_id` exactly matches `1540122228199268352`.

## Commands

Preview without posting or changing state:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-waiver-tracker.ps1 -DryRun
```

Initialize without posting older activity:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-waiver-tracker.ps1
```

Preview an intentional historical backfill:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-waiver-tracker.ps1 -IncludeHistorical -DryRun
```

## GitHub Actions

`.github/workflows/discord-waiver-tracker.yml` refreshes the current recap every day at 2:00 PM Central. It schedules both possible UTC hours and performs a Chicago-time check so daylight-saving changes do not move the local posting time. Scheduled posting stays disabled until repository variable `DISCORD_WAIVER_TRACKER_ENABLED` is set to `true`.

The manual workflow defaults to dry-run mode. Recommended rollout:

1. Add the webhook secret.
2. Run manually with `dry_run=true`.
3. Run once with `dry_run=false` and `include_historical=false` to establish the baseline without flooding the channel.
4. Set `DISCORD_WAIVER_TRACKER_ENABLED=true`.
5. Confirm the next successful claim or free-agent pickup creates exactly one post.
