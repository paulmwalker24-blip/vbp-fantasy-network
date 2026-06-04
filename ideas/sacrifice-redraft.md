# Sacrifice Redraft

## Core Hook

VBP Progressive PPR redraft, but every week each team's highest-scoring starter must be dropped.

Other managers can claim that player immediately through normal waivers, but the original manager cannot re-add their own sacrificed player until after the following NFL week is complete.

This should feel like normal redraft on Sleeper until the weekly sacrifice rule forces roster churn.

## Short Explainer

Sacrifice Redraft is a normal VBP Progressive PPR redraft league with one twist: every week, each team has to drop its highest-scoring starter.

After the week finishes, the commissioner posts the sacrifice list for all 12 teams. Those players must be dropped before the next waiver run. Everyone else can claim them right away, but the team that dropped the player cannot re-add him until after the next week is complete.

So if your wide receiver scores 31 points in Week 1, great, you got the win boost, but now he becomes your sacrifice for Week 2. You cannot add him back until Week 3 at the earliest. The same pattern applies all season: a Week X sacrifice is locked away from the original manager through Week X+1.

## Baseline League Settings

- League format: 12-team seasonal redraft.
- Format name: Sacrifice Redraft.
- First test league: Sacrifice Redraft 1.
- First test league entry: Free.
- Sleeper league ID: `1368081408932712448`.
- Public invite link: `https://sleeper.com/i/j7zjVWa4qYqP0`.
- Direct Sleeper league link: `https://sleeper.com/leagues/1368081408932712448`.
- Current live assigned count: 2/12 as verified through Sleeper roster assignments.
- Platform: Sleeper.
- Scoring: VBP Progressive PPR with 6-point passing touchdowns.
- Regular season: Weeks 1-14.
- Playoffs: 6 teams, Weeks 15-17, with top two seeds receiving first-round byes.
- Waivers: FAAB.
- FAAB budget: $200 per team.
- Trades: allowed until the standard redraft trade deadline unless the final league rules say otherwise.
- Draft: snake draft.
- Draft order: generated through 100yardrush.com after the league is full and paid.

## Roster Settings

Use the Sleeper-standard VBP redraft roster build:

- 1 QB
- 2 RB
- 2 WR
- 1 TE
- 2 FLEX (RB / WR / TE)
- 6 bench
- 1 IR

Positions not used:

- Kickers
- Team Defense / Special Teams
- Superflex

## Scoring

Use the VBP Progressive PPR scoring model:

| Position | Reception Points |
| --- | ---: |
| RB | 0.5 |
| WR | 0.25 |
| TE | 0.75 |

Passing touchdowns are worth 6 points.

All other scoring categories follow standard Sleeper scoring settings.

No yardage bonuses, big-play bonuses, or additional tight end premium should be used unless the final league rules explicitly change that.

## Sacrifice Rule

- Sacrifice player: each team's highest-scoring starter for the completed week.
- Bench players do not trigger the sacrifice rule.
- Managers should be diligent and drop their sacrifice player as soon as possible after that week's NFL games have been completed.
- The commissioner will post the official sacrifice list on Tuesdays.
- Other teams may claim or add the sacrificed player immediately.
- The original manager may not re-add their own sacrificed player until the following NFL week has been completed. In shorthand: a Week X sacrifice cannot be re-added by the original manager until Week X+2 at the earliest.
- Trades remain enabled under the standard redraft trade rules.
- If a manager refuses to drop the sacrifice player, the commissioner may manually remove the player.
- Ties for highest-scoring starter should use Sleeper decimal scoring first; if still tied, use commissioner-posted tiebreaker rules.

## Weekly Process

1. Weekly games complete.
2. Managers should review their own starting lineup and drop their likely sacrifice player as soon as possible.
3. On Tuesday, the commissioner reviews each team's starting lineup scores.
4. The highest-scoring starter on each team is named that team's official sacrifice player.
5. The commissioner posts the full sacrifice list in league chat.
6. Any manager who has not yet dropped the correct sacrifice player must do so before waivers.
7. Sacrificed players enter normal Sleeper waivers.
8. All other managers may claim those players immediately.
9. The original manager may not re-add their own sacrificed player until the following NFL week is complete.

Example:

- Week 1: Ja'Marr Chase is Team A's highest-scoring starter.
- Team A should drop Chase as soon as Week 1 games are complete, and the commissioner will confirm the sacrifice list on Tuesday.
- Every other team may claim Chase for Week 2.
- Team A may not re-add Chase during Week 2.
- If Chase is available after Week 2 is complete, Team A can add him again for Week 3 at the earliest.
- The same structure applies to every week: a Week X sacrifice is unavailable to the original manager for Week X+1.

## Playoff Handling

Sacrifice applies Weeks 1-13 only.

No sacrifice is triggered after Week 14, the final regular-season week.
No sacrifice occurs during the fantasy playoffs.

Reason:

- The sacrifice mechanic creates the format identity during the main regular-season run.
- Week 14 decides final playoff seeding without forcing a sacrifice that carries into the playoffs.
- Playoff rounds should be decided by the rosters managers have built through the chaos.

## Commissioner Workload

This format is not fully automatic.

Weekly commissioner tasks:

- Review each team's highest-scoring starter after the weekly scoring period locks.
- Only worry about stat-correction weirdness when two players are extremely close at the top of a team's sacrifice block.
- Post the 12-team sacrifice list on Tuesdays.
- Confirm each sacrifice player is dropped before waivers.
- Track each original manager's one-week re-add restriction.

Expected workload: moderate, roughly 10-15 minutes per week if tracked in a simple weekly post or spreadsheet.

## Tracking Template

```text
Week [X] Sacrifice List

Team 1: [Player] - original manager cannot re-add until Week [X+2]
Team 2: [Player] - original manager cannot re-add until Week [X+2]
Team 3: [Player] - original manager cannot re-add until Week [X+2]
Team 4: [Player] - original manager cannot re-add until Week [X+2]
Team 5: [Player] - original manager cannot re-add until Week [X+2]
Team 6: [Player] - original manager cannot re-add until Week [X+2]
Team 7: [Player] - original manager cannot re-add until Week [X+2]
Team 8: [Player] - original manager cannot re-add until Week [X+2]
Team 9: [Player] - original manager cannot re-add until Week [X+2]
Team 10: [Player] - original manager cannot re-add until Week [X+2]
Team 11: [Player] - original manager cannot re-add until Week [X+2]
Team 12: [Player] - original manager cannot re-add until Week [X+2]
```

## Open Questions Before Launch

- What point gap should count as "extremely close" for stat-correction caution: 0.10, 0.25, 0.50, or commissioner judgment?

## Recruiting Lines

```text
Free Sacrifice Redraft test league: Progressive PPR with 6-point passing touchdowns, but your highest-scoring starter each week has to be dropped.
```

```text
Big weeks help you win now, but they also cost you the player for at least one week.
```

```text
Win by surviving your own best players.
```
