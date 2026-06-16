# Discord Testing Channel Map

Use this map for the current VBP Discord layout.

The `*-testing` channels under `League Openings` are the staging channels for format-specific league boards. Each one should start with a short format explanation, then the webhook board underneath it. Full leagues may be listed for context, but full leagues should not include join details or recruiting instructions.

## Current Channel Structure

```text
Pinned Channels
- start-here
- rules-and-links
- announcements

Community
- general-discussion
- nfl-discussion
- fantasy-football-discussion
- fantasy-football-draft-questions
- league-questions

League Hubs
- redraft-bracket
- dynasty-bracket
- best-ball-union

League Openings
- 32-team-redraft-testing
- best-ball-gauntlet-testing
- best-ball-union-testing
- chopped-testing
- co-manager-testing
- dynasty-bracket-testing
- dynasty-testing
- keeper-testing
- pickem-testing
- redraft-bracket-testing
- redraft-testing
- sacrifice-testing

Constitutions
- constitution channel or forum
```

## Posting Pattern

Each `*-testing` channel should use the same structure:

```text
1. Format explanation post
2. Full / established league summary
3. Current openings webhook
4. Follow-up recruiting post only when needed
```

The explanation should answer:

- what this league type is
- who it is best for
- roster or scoring basics
- whether full leagues are shown only as proof of activity
- where live join links appear

The webhook board should handle:

- current openings
- assigned spots
- paid-count notes where available
- draft status
- live join links for open leagues
- rules links

Once `data/private/discord-webhooks.json` contains the real testing-channel webhook URLs, the full stack can be posted with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\post-discord-testing-channel-stack.ps1
```

The same stack can also run through GitHub Actions with `.github/workflows/discord-testing-channel-stack.yml`. That workflow expects these repository secret names:

```text
DISCORD_WEBHOOK_32_TEAM_REDRAFT_TESTING
DISCORD_WEBHOOK_BEST_BALL_GAUNTLET_TESTING
DISCORD_WEBHOOK_BEST_BALL_UNION_TESTING
DISCORD_WEBHOOK_CHOPPED_TESTING
DISCORD_WEBHOOK_CO_MANAGER_TESTING
DISCORD_WEBHOOK_DYNASTY_BRACKET_TESTING
DISCORD_WEBHOOK_DYNASTY_TESTING
DISCORD_WEBHOOK_KEEPER_TESTING
DISCORD_WEBHOOK_PICKEM_TESTING
DISCORD_WEBHOOK_REDRAFT_BRACKET_TESTING
DISCORD_WEBHOOK_REDRAFT_TESTING
DISCORD_WEBHOOK_SACRIFICE_TESTING
```

GitHub secret values cannot be read back after they are saved. If a channel is skipped in the workflow logs, confirm the matching secret name exists and is not blank.

## Channel To Script Map

Use the same channel webhook URL for the guide and the status board in that channel, then post the guide first.

```text
32-team-redraft-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey redraft32
- Status script: scripts/post-discord-format-status.ps1 -FormatKey redraft32

best-ball-gauntlet-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey bbg
- Status script: scripts/post-discord-format-status.ps1 -FormatKey bbg

best-ball-union-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey bestball
- Status script: scripts/post-discord-bbu-status.ps1

chopped-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey chopped
- Status script: scripts/post-discord-format-status.ps1 -FormatKey chopped

co-manager-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey comanager
- Status script: scripts/post-discord-format-status.ps1 -FormatKey comanager

dynasty-bracket-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey dynastybracket
- Status script: scripts/post-discord-dynasty-bracket-status.ps1

dynasty-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey dynasty
- Status script: scripts/post-discord-format-status.ps1 -FormatKey dynasty

keeper-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey keeper
- Status script: scripts/post-discord-format-status.ps1 -FormatKey keeper

pickem-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey pickem
- Status script: scripts/post-discord-format-status.ps1 -FormatKey pickem

redraft-bracket-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey bracket
- Status script: scripts/post-discord-redraft-bracket-status.ps1

redraft-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey redraft
- Status script: scripts/post-discord-redraft-status.ps1

sacrifice-testing
- Explanation: scripts/post-discord-format-guide.ps1 -FormatKey sacrifice
- Status script: scripts/post-discord-format-status.ps1 -FormatKey sacrifice
```

## Full League Rule

Full leagues should be visible, but only as context.

Good:

```text
Full / established rooms:
- VBP Redraft 1
- VBP Redraft 2
- VBP Redraft 3
```

Avoid:

```text
VBP Redraft 1 is full. Join here: [link]
```

Reason:

- Full league links create confusion.
- Prospects should focus on open rooms.
- Full rooms still help show that the network is active.

## Recommended Launch Order

1. Keep all `*-testing` channels private or limited while building.
2. Post each explanation first.
3. Run each status webhook into its matching testing channel.
4. Review channel readability on desktop and mobile.
5. When a channel looks good, rename it from `*-testing` to the final public channel name.
6. Keep the saved webhook message state after rename so future script runs update the same message.

## Final Channel Names

When testing is complete, likely final names are:

```text
32-team-redraft
best-ball-gauntlet
best-ball-union-openings
chopped
co-manager-redraft
dynasty-bracket-openings
dynasty
keeper
pickem
redraft-bracket-openings
redraft
sacrifice-redraft
```

Use names that remain clear after the `League Openings` category label is collapsed.
