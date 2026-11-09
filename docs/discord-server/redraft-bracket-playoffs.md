# 2026 Redraft Bracket playoff forum

Forum channel: `1569380664799920278` (`playoffs-2026`).

The existing **Redraft Bracket Discord Standings** workflow runs Tuesdays at 1 AM America/Chicago. After its standings publisher succeeds, it calls `scripts/refresh-discord-bracket-playoffs.ps1` using the same refreshed `data/bracket-ledger.json`. This dependency avoids a second timer and follows GitHub's actual run completion, including scheduling delays. Dry-run standings dispatches do not publish playoff posts. A failed standings publication prevents the playoff step.

The forum contains one plain-text overview and 16 matchup threads: 1/30 through 15/16 plus the 31/32 wildcard. Stable seed-pair titles keep threads reusable as projected teams change. Each thread starts with a SCORE message showing both teams, followed by two roster messages with records and Sleeper team links. Before Week 13 the scoreboard shows `--` and no team or player points are fetched. Once Week 13 begins, Round 1 always reads Week 13 matchup scores rather than a later week's scores. Tuesday refreshes are snapshots, not continuous live scoring.

The final field is saved once all 60 teams have 12 completed games. `data/bracket-playoff-field-2026.json` preserves that field for later runs; later results cannot reseed Round 1. If the final field is missing after 12 games, automation stops for commissioner review. Exact record/PF ties stop publication for the constitution's Max Points For review. This automation does not advance winners, create later-round posts, or replace commissioner oversight of final seeds.

## Credentials and state

- GitHub secret: `DISCORD_WEBHOOK_REDRAFT_BRACKET_PLAYOFFS`.
- Local fallback: `channels.redraft-bracket-playoffs` in gitignored `data/private/discord-webhooks.json`.
- Public overview IDs: `data/discord-bracket-playoffs-state.json`.
- Public matchup IDs: `data/discord-bracket-matchups-state.json`.

State files contain only IDs and publication bookkeeping, never webhook tokens. The original four tests were migrated into these shared state files so local and scheduled runs edit the same posts. Preserve state; do not run competing local publication while the workflow is running. The workflow saves state even on a partial publication failure. Requests are paced, rejected rate-limit requests are retried, and ambiguous create requests are not retried automatically. A one-time migration replaces old team-specific webhook sender labels with a neutral sender to prevent stale owner labels after seeds change; pending cleanup IDs are persisted until old roster messages are removed.

## Local preview and refresh

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-bracket-ledger.ps1 -GroupIds BRACKET-2026-1 -LedgerPath tmp/bracket-playoffs-preview.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\refresh-discord-bracket-playoffs.ps1 -LedgerPath tmp/bracket-playoffs-preview.json -DryRun
```

Omit `-DryRun` only when publication is requested. The wrapper validates all 16 matchup payloads before changing Discord. Scripts retain their original `post-discord-bracket-matchup-tests.ps1` name for compatibility; the wrapper passes `-AllMatchups` for production. No separate cron or Codex reminder is needed.
