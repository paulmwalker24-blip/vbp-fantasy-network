# BBU Discord scoreboard automation

The combined weekly-winners summary, BBU Bot weekly Top 5, and overall Top 20 cover all 15 rooms and 150 teams. `scripts/refresh-bbu-scoreboards.ps1` audits every completed week, validates all three outputs, and compares all 150 cumulative totals with live Sleeper roster totals before publication. Use PowerShell 7 (`pwsh`). No switch previews; `-Publish` updates existing saved messages and verifies readback. Current manager identities are used; prize payments remain not recorded.

`bbu-scoreboards-discord.yml` targets Tuesday at 2:20 PM America/Chicago, with a Wednesday 7:23 AM recovery run. Enable using `DISCORD_BBU_BOT_SCOREBOARDS_ENABLED=true` and the dedicated `DISCORD_BBU_BOT_TOKEN` repository secret. Manual dispatch defaults to preview. State and audits are committed even after partial publication to preserve new message IDs. GET/PATCH rate limits use Discord's retry delay; POST is never retried automatically. Do not run local and scheduled publishers simultaneously.

The separate `discord-bbu-high-scorer.yml` job remains disabled using `DISCORD_BBU_HIGH_SCORER_ENABLED=false`. Its publisher, `post-discord-bbu-high-scorer.ps1`, now reads the same verified 15-room audit and is called by the repaired workflow. The existing `DISCORD_WEBHOOK_BBU_HIGH_SCORER` secret edits the original combined weekly-winners message in place; `data/discord-bbu-high-scorer-state.json` retains that message's ownership and history. This summary must refresh alongside the individual weekly cards and overall season standings. The BBU Bot cannot edit this webhook-authored message.

Bracket standings retain Tuesday 1:00 AM America/Chicago and add a Tuesday 7:13 AM recovery run. The existing workflow refreshes the ledger, standings, playoff overview, and matchup threads together. Keep its standings and playoff webhook secrets plus the existing Discord bot secret. Rankings are separate and outside this repair's scope.

GitHub scheduled starts may be delayed or dropped. Recovery runs provide another opportunity to refresh; they do not guarantee exact-time delivery. A failed job should be inspected and rerun. BBU reruns reuse saved per-week messages; uncertain new-message responses must be inspected before retrying to prevent duplicates.

Local preview: `pwsh -NoProfile -File scripts/refresh-bbu-scoreboards.ps1`

Publish: `pwsh -NoProfile -File scripts/refresh-bbu-scoreboards.ps1 -Publish`
