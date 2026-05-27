# Power Rankings

Commissioner-facing workspace for power-ranking copy, notes, and publishing references.

The generated system follows the scoring model documented in `docs/vbp-power-ranking-model.md`. Live Sleeper scoring settings take priority over the baseline, and format profiles account for dynasty, Best Ball Union, Gauntlet, Keeper, Chopped, Redraft, and bracket roster structures. Published individual-league pages include owner-by-position boards without individual player breakdowns; the Best Ball Union Center reads the completed-room combined Top 20 from the same generated snapshot.

Use this folder for:
- power-ranking announcement posts
- ranking methodology copy
- notes about when rankings are ready to publish
- copy that supports the public ranking pages without being recruiting copy

Runtime files stay in their existing public locations:
- `power-rankings.html`
- `dynasty-power-rankings.html`
- `assets/js/power-rankings.js`
- `assets/js/bestball-center.js`
- `data/power-rankings.json`
- `data/power-ranking-overrides.json`
- `scripts/sync-power-rankings.ps1`

Keep `marketing/` focused on posts that recruit new owners into open leagues.
