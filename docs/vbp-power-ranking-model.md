# VBP Power Ranking Model

## Scoring-Derived Standard

Every generated current-season ranking must read the live Sleeper `scoring_settings` and apply those coefficients to Sleeper's Week 1-17 player stat projections. Verifying settings without using them in the projected fantasy-point calculation does not meet the VBP standard.

For each player and week, the model calculates:

`projected fantasy points = sum(projected stat × matching live scoring coefficient)`

The calculation is performed from stat components rather than Sleeper's generic standard, half-PPR, or PPR point totals. That allows the same projection feed to reflect each league's actual reception values, passing rules, yardage, touchdowns, turnovers, two-point plays, fumbles, and matching bonus categories.

Any nonzero offensive scoring category without a projection field is explicitly recorded in `zeroAssumptionKeys` and treated as a projected zero. It must never be silently replaced with a generic scoring value. Core passing, rushing, receiving, and positional-reception keys are required; generation fails closed if those inputs are missing.

The VBP Progressive PPR baseline is:

| Setting | Value |
| --- | ---: |
| Base reception (`rec`) | 0.00 |
| RB reception bonus (`bonus_rec_rb`) | 0.50 |
| WR reception bonus (`bonus_rec_wr`) | 0.25 |
| TE reception bonus (`bonus_rec_te`) | 0.75 |
| Rushing / receiving yard | 0.10 |
| Rushing / receiving TD | 6.00 |
| Passing yard | 0.04 |
| Passing TD | 4.00 |
| Interception | -1.00 |

Total reception value is calculated as `rec + positional bonus`. If a live league differs from this baseline, its Sleeper settings override the default in both the projection calculation and the generated report.

## Team Power Score

The score remains a comparative grade out of 100, not a projected record. For dynasty boards, the published score uses a fixed within-league scale around the calculated roster-strength average so real model differences remain readable without assigning points by rank. It uses:

- Scoring-derived weekly averages and top-week ceiling calculated under the complete live scoring system.
- Optimized legal starters for the live roster-position rules.
- Quarterback scarcity in true superflex or 2QB lineups.
- Bench depth, elite ceiling, Sleeper injury/status flags, and commissioner overrides.
- Dynasty age runway and draft capital for dynasty formats.

For Best Ball Union, scoring-derived weekly average supplies 72% of each player's projection grade and scoring-derived top-three-week ceiling supplies 28%, followed by explicit injury and commissioner adjustments. The team model then grades the legal optimized lineup, locked depth, quarterback room, elite ceiling, and availability. Wins and points already scored do not alter the roster-strength grade; points for remains only a published-score tiebreaker.

Dynasty future-value boards may still use market rank, age, and draft capital because their purpose extends beyond one season. Their separate current-season profiles must use the scoring-derived projection standard.

## Positional Boards

Published individual-league positional boards rank owners at every position represented in that league, such as QB, RB, WR, TE, K, DEF, DL, LB, DB, or IDP.

- Each row is an owner and position score, ranked from best position group to weakest.
- Public boards do not publish the underlying player list or internal scoring trail.
- The calculation still respects the live scoring settings, eligible starter counts, depth needs, and replacement environment.

## Format Profiles

- `dynasty` and `dynastybracket`: superflex quarterback stability, long-term roster runway, current depth, and draft capital.
- `bestball`: custom-scoring weekly average, best automatic lineup, top-three-week ceiling, locked drafted depth, and heightened injury/role risk because there are no in-season repairs.
- `gauntlet`: four-start micro-roster ceiling and availability risk after its locked draft completes.
- `keeper`: present roster power plus future keeper runway and cost value.
- `chopped`: weekly survival strength, health, and replacement pressure.
- `redraft` and `bracket`: current starter strength and seasonal depth, with bracket formats intended for combined boards when their rooms are ready.

Pass-catching RBs and volume TEs rise relative to ordinary catch-volume WRs under Progressive PPR. In superflex dynasty, secure quarterbacks remain structurally valuable because of starter scarcity and long-term market value.
