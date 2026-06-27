# Website And Leagues TODO

Use this list for site accuracy, league data, constitutions, recruiting copy, payment records, and public league-center work.

## Immediate

- [ ] Review and commit the June 26, 2026 Sleeper sync in `data/leagues.json`; bracket redraft now uses assigned teams as the paid count source.
- [ ] Resolve the Redraft Bracket payment reconciliation matches for `NFLGoodellEvilKing` in Iron and `deshaunwatson8` in Vanguard; the June 26 LeagueSafe export has 40 paid rows, 5 paid-not-assigned rows, and 2 assigned teams needing payment matches after confirming `Jdorsh` maps to `Justforfunn`.
- [ ] Run `scripts/check-site.ps1` after copy/data updates and fix any validation warnings that are actual blockers.
- [ ] Decide how to display or handle full-but-public invite links for newly full rooms such as `RD4`, `RDB2`, `BBU7`, and `BBU9`.
- [ ] Add the missing `BG2` LeagueSafe link once the payment page is ready.
- [ ] Resolve the Best Ball Union lineup mismatch: constitutions mention `3 WR`, while current Sleeper rooms report `2 WR`.
- [ ] Verify and record the pending Mandalore LeagueSafe refund in `DYN8`; this is historical payment record cleanup, not a recruiting blocker.

## Next

- [ ] Add public rendered ranking destinations for future completed Redraft, Keeper, Chopped, Redraft Bracket, and Dynasty Bracket boards before promoting those rankings as live.
- [ ] Decide whether `BBU10` or a newer BBU room should be the active recruiting room before each new post.
- [ ] Refresh `marketing/recruiting-copy-ready.txt` after every meaningful paid/assigned-count change.
- [ ] Keep bracket recruiting centered on Titan, Iron, and Dominion while Apex remains full.
- [ ] Decide whether to add an optional Tuesday GitHub Action that republishes bracket standings snapshots automatically.

## Explorer Cleanup

- [ ] Keep public pages at the repo root for stable deployed URLs, but use `README.md` as the day-to-day map instead of hunting through root files.
- [ ] Move future planning notes into `docs/`, `marketing/`, `notes/`, or `ideas/` instead of adding more root-level scratch files.
- [ ] Consider archiving older recruiting variants into `marketing/recruiting-archive.md` whenever `marketing/recruiting-copy-ready.txt` gets refreshed.
