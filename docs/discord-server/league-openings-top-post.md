# League Openings Top Post

Use this as source copy for guide webhooks in the Discord League Opening channels.

The broad automated version lives in `scripts/post-discord-open-leagues-guide.ps1`. The current per-channel layout is documented in `docs/discord-server/testing-channel-map.md`.

This is stable format-guide copy. The webhook posts below it should handle live counts, current invite links, and room-specific status.

Post these as separate Discord messages in order so they stay readable on mobile.

## Message 1: Start Here

```text
VBP Fantasy Network league openings

This channel has two layers:

1. This pinned/top section explains what each league type is.
2. The automated status posts underneath show current openings, live room counts, and active join links.

Use the webhook boards below for the current status. This post is the format map so you can decide what kind of league fits you before jumping into a room.

Main hub:
https://vbp-fantasy-network.vercel.app/
```

## Message 2: Seasonal Redraft Formats

```text
SEASONAL REDRAFT OPTIONS

Standard Redraft
- Best for: managers who want one clean seasonal league.
- Typical size: 12 teams.
- Scoring: VBP Progressive PPR.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX.
- Bench: 6.
- Waivers: $200 FAAB.
- Playoffs: normal league playoff structure.
- Rules: https://vbp-fantasy-network.vercel.app/redraft-constitution.html

32-Team Redraft
- Best for: managers who want a deeper single-season field with scarce player supply.
- Size: 32 teams.
- Roster: 7 starters, 4 bench.
- Lineup: 1 RB, 2 WR, 3 FLEX, 1 SUPER FLEX.
- Note: there is no required dedicated QB starter; QB can be used in the SUPER FLEX.
- Waivers: $200 FAAB.
- Rules: https://vbp-fantasy-network.vercel.app/32-team-redraft-constitution.html

Co-Manager Redraft
- Best for: managers who want to run a team with a small front office.
- Size: 12 teams.
- Team control: each team must have 2-3 co-managers.
- Scoring: traditional 0.5 PPR, TE premium, 6-point passing TDs.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX, 1 SUPER FLEX.
- Bench/reserve: 5 bench, 1 IR.
- Draft: 3RR slow draft.
- Rules: https://vbp-fantasy-network.vercel.app/co-manager-constitution.html
```

## Message 3: Bracket Formats

```text
BRACKET FORMATS

Redraft Bracket
- Best for: managers who want a normal 12-team redraft room that also feeds a much bigger tournament.
- Total field: 60 teams across five 12-team divisions.
- Divisions: each division drafts and plays its own regular season.
- Overall playoff: 32 teams make one shared single-elimination bracket.
- Scoring: VBP Progressive PPR.
- Roster: 15 players.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX, 1 SUPER FLEX.
- Bench: 6.
- Waivers: $200 FAAB.
- Draft rooms: fast and slow divisions may be available.
- Rules: https://vbp-fantasy-network.vercel.app/bracket-constitution.html
- Center: https://vbp-fantasy-network.vercel.app/bracket-center.html

Dynasty Bracket
- Best for: managers who want dynasty roster building inside a larger network playoff.
- Total field: 48 teams across four 12-team divisions.
- Divisions: each division is its own dynasty league.
- Overall playoff: 16 teams make one shared Dynasty Bracket playoff.
- Scoring: VBP Progressive PPR with Superflex.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 3 FLEX, 1 SUPERFLEX.
- Bench/taxi/IR: 13 bench, 4 taxi, 4 IR.
- Draft: 3RR startup.
- Payment model: current season plus next two seasons due up front.
- Rules: https://vbp-fantasy-network.vercel.app/dynasty-bracket-constitution.html
- Center: https://vbp-fantasy-network.vercel.app/bracket-center.html?view=dynasty
```

## Message 4: Dynasty And Keeper Formats

```text
DYNASTY / KEEPER OPTIONS

Standard Dynasty
- Best for: managers who want full long-term roster control.
- Size: 12 teams.
- Scoring: VBP Progressive PPR with Superflex.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 3 FLEX, 1 SUPERFLEX.
- DYN8 and later: 31-round startup, then cut to 27 total players after preseason.
- Rookie draft: 4 rounds in future seasons.
- Draft: 3RR startup for new leagues.
- Payment model: new startups require current season plus next two seasons paid up front.
- Rules: https://vbp-fantasy-network.vercel.app/dynasty-constitution.html

Keeper
- Best for: managers who want a middle ground between redraft and dynasty.
- Size: 12 teams.
- Keepers: up to 3 players per offseason.
- Keeper cost: drafted players cost two rounds earlier each keeper season.
- Undrafted players: first keeper cost is Round 10.
- Keeper timeline: maximum of acquisition season plus the next two seasons with the same manager.
- Draft: 3RR.
- Payment model: two seasons due up front.
- Rules: https://vbp-fantasy-network.vercel.app/keeper-constitution.html
```

## Message 5: Best Ball And Specialty Formats

```text
BEST BALL / SPECIALTY OPTIONS

Best Ball Union
- Best for: managers who want to draft and then stop managing lineups.
- Size: 10 teams per room.
- Draft: normally fast 90-second snake draft.
- Roster: 18 players.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX.
- Bench: 9.
- Scoring: VBP Progressive PPR with weekly median matchup.
- Season management: no waivers, trades, pickups, or weekly lineup setting.
- Sleeper automatically uses your best lineup each week.
- Rules: https://vbp-fantasy-network.vercel.app/bestball-constitution.html
- Center: https://vbp-fantasy-network.vercel.app/bestball-center.html

Best Ball Gauntlet
- Best for: managers who want a tiny-roster best ball challenge.
- Size: 24 teams.
- Format: doubleheader micro best ball.
- Current open-room version may use a 6-player roster with 4 starters and 2 bench.
- Core concept: draft-only best ball with no waivers, trades, pickups, or lineup setting.
- Rules: https://vbp-fantasy-network.vercel.app/bestball-gauntlet-constitution.html

Chopped
- Best for: managers who want weekly survival pressure.
- Size: 18 teams.
- Format: elimination-style redraft.
- Scoring: VBP Progressive PPR.
- Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX.
- Waivers: $200 FAAB.
- Weekly survival is based on scoring and the posted elimination rules.
- Rules: https://vbp-fantasy-network.vercel.app/chopped-constitution.html

Pick'em
- Best for: managers who want a low-maintenance football contest with no fantasy roster.
- Format: NFL picks against the spread.
- No draft, no waivers, no lineups, no trades.
- Standings are based on Sleeper's pick'em scoring.
- Rules: https://vbp-fantasy-network.vercel.app/pickem-constitution.html
```

## Message 6: How To Use This Channel

```text
HOW TO JOIN

Use the live status posts below this guide.

Those posts show:
- current openings
- assigned spots
- active rooms
- current join links
- rules links
- whether a room is full, drafting, or still recruiting

If you are not sure where to start, reply or DM with:

1. Redraft, dynasty, best ball, bracket, keeper, chopped, or pick'em
2. Fast draft or slow draft preference, if it matters
3. Buy-in range
4. Whether you want simple seasonal play or a long-term league

I will point you to the best current fit.
```

## Maintenance Notes

- Keep this manual post stable; do not update it for every paid count.
- Edit it only when a format structure changes.
- Keep live counts and room-specific pushes in the webhook posts below it.
- If the Discord channel gets crowded, pin Message 1 and keep the full guide linked from `rules-and-links`.
