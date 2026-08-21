# Redraft Bracket Trade Tracker

The Discord trade tracker posts each newly completed Sleeper trade once to channel `1540122074893385796`.

## Scope

Only the five 2026 Redraft Bracket divisions are configured:

- `RDB1` - Titan
- `RDB2` - Apex
- `RDB3` - Iron
- `RDB4` - Vanguard
- `RDB5` - Dominion

Standard redraft, dynasty, keeper, Chopped, Best Ball, Pick'em, and postponed Dynasty Bracket leagues are not part of this feed.

## Behavior

`scripts/post-discord-trade-tracker.ps1` checks Sleeper transaction Weeks 1-18 and accepts only transactions whose type is `trade` and whose status is `complete` or `completed`.

Each Discord embed includes:

- league and division name
- each team's received players
- received rookie or future draft picks when Sleeper includes them
- received FAAB when included in the transaction
- the stable Sleeper transaction ID and timestamp
- a direct link to the Sleeper league

The tracker supports two-team and multi-team trades. `data/discord-trade-tracker-state.json` records transaction IDs after posting so later checks do not create duplicates.

The first live run is intentionally safe: unless `-IncludeHistorical` is supplied, it records any existing completed trades without posting them. Only trades first seen after initialization are posted. At setup time on August 20, 2026, the five configured divisions returned no completed historical trades.

## Discord Webhook

Create a webhook inside channel `1540122074893385796`. Then configure it in one of two places:

- Local: add a `trade-tracker` entry to `data/private/discord-webhooks.json`.
- GitHub Actions: add repository secret `DISCORD_WEBHOOK_TRADE_TRACKER`.

Before posting, the script fetches the webhook metadata and refuses to continue unless its `channel_id` exactly matches `1540122074893385796`.

Do not put the real webhook URL in tracked configuration or documentation.

## Local Commands

Preview the initial baseline without writing state or posting:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-trade-tracker.ps1 -DryRun
```

Initialize the state without posting older trades:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-trade-tracker.ps1
```

After initialization, preview any new trade embeds:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-trade-tracker.ps1 -DryRun
```

Intentionally preview unposted historical trades:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-trade-tracker.ps1 -IncludeHistorical -DryRun
```

`-IncludeHistorical` can produce multiple Discord posts when used live. The config limits a single run to 10 posts; any additional transactions remain queued for later runs.

## GitHub Actions

`.github/workflows/discord-trade-tracker.yml` checks every 15 minutes. Scheduled posting stays disabled until repository variable `DISCORD_TRADE_TRACKER_ENABLED` is set to `true`.

The manual workflow defaults to dry-run mode. Recommended rollout:

1. Add the webhook secret.
2. Run the workflow manually with `dry_run=true`.
3. Run it once with `dry_run=false` and `include_historical=false` to initialize state without flooding the channel.
4. Set `DISCORD_TRADE_TRACKER_ENABLED=true`.
5. Confirm the next accepted Redraft Bracket trade produces exactly one post.
