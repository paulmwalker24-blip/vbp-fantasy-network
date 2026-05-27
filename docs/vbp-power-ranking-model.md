# VBP Power Ranking Model

## Scoring Verification

Every generated ranking board reads the live Sleeper `scoring_settings` before applying player-value adjustments. The VBP Progressive PPR baseline is:

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

Total reception value is calculated as `rec + positional bonus`. If a live league differs from this baseline, its Sleeper settings override the default and the generated board reports that difference.

## Team Power Score

The score remains a grade out of 100, not a projected weekly point total. For dynasty boards, the published score uses a fixed within-league scale around the calculated roster-strength average so real model differences remain readable without assigning points by rank. It uses:

- Optimized legal starters for the live roster-position rules.
- Scoring-aware receiving leverage for RBs and TEs measured against the live WR reception value.
- Quarterback scarcity in true superflex or 2QB lineups.
- Bench depth, elite ceiling, Sleeper injury/status flags, and commissioner overrides.
- Dynasty age runway and draft capital for dynasty formats.

Sleeper provides roster, draft, settings, and player metadata but does not provide component stat projections through the endpoints used here. The system does not invent projected fantasy points.

## Positional Boards

Published individual-league positional boards rank owners at every position represented in that league, such as QB, RB, WR, TE, K, DEF, DL, LB, DB, or IDP.

- Each row is an owner and position score, ranked from best position group to weakest.
- Public boards do not publish the underlying player list or internal scoring trail.
- The calculation still respects the live scoring settings, eligible starter counts, depth needs, and replacement environment.

## Format Profiles

- `dynasty` and `dynastybracket`: superflex quarterback stability, long-term roster runway, current depth, and draft capital.
- `bestball`: best automatic weekly lineup, locked drafted depth, weekly scoring ceiling, and heightened injury/role risk because there are no in-season repairs.
- `gauntlet`: four-start micro-roster ceiling and availability risk after its locked draft completes.
- `keeper`: present roster power plus future keeper runway and cost value.
- `chopped`: weekly survival strength, health, and replacement pressure.
- `redraft` and `bracket`: current starter strength and seasonal depth, with bracket formats intended for combined boards when their rooms are ready.

Pass-catching RBs and volume TEs rise relative to ordinary catch-volume WRs under Progressive PPR. In superflex dynasty, secure quarterbacks remain structurally valuable because of starter scarcity and long-term market value.
