import fs from 'node:fs';

const auditPath = 'dist/keeper-audit.json';
const result = JSON.parse(fs.readFileSync(auditPath, 'utf8'));
const response = await fetch('https://api.sleeper.app/v1/players/nfl');
if (!response.ok) throw new Error(`Could not load Sleeper player catalog: HTTP ${response.status}`);
const players = await response.json();

const defenses = {
  ARI: 'Arizona Cardinals', ATL: 'Atlanta Falcons', BAL: 'Baltimore Ravens', BUF: 'Buffalo Bills',
  CAR: 'Carolina Panthers', CHI: 'Chicago Bears', CIN: 'Cincinnati Bengals', CLE: 'Cleveland Browns',
  DAL: 'Dallas Cowboys', DEN: 'Denver Broncos', DET: 'Detroit Lions', GB: 'Green Bay Packers',
  HOU: 'Houston Texans', IND: 'Indianapolis Colts', JAX: 'Jacksonville Jaguars', KC: 'Kansas City Chiefs',
  LAC: 'Los Angeles Chargers', LAR: 'Los Angeles Rams', LV: 'Las Vegas Raiders', MIA: 'Miami Dolphins',
  MIN: 'Minnesota Vikings', NE: 'New England Patriots', NO: 'New Orleans Saints', NYG: 'New York Giants',
  NYJ: 'New York Jets', PHI: 'Philadelphia Eagles', PIT: 'Pittsburgh Steelers', SEA: 'Seattle Seahawks',
  SF: 'San Francisco 49ers', TB: 'Tampa Bay Buccaneers', TEN: 'Tennessee Titans', WAS: 'Washington Commanders'
};

for (const opening of result.openings || []) {
  for (const player of opening.players || []) {
    const id = String(player.player_id);
    const catalog = players[id] || null;
    if (catalog) {
      player.name = catalog.full_name || [catalog.first_name, catalog.last_name].filter(Boolean).join(' ') || player.name;
      player.position = catalog.position || player.position;
      player.nfl_team = catalog.team || null;
    } else if (defenses[id]) {
      player.name = defenses[id];
      player.position = 'DEF';
      player.nfl_team = id;
    }

    if (player.status === 'NO_VERIFIED_2025_DRAFT_COST') {
      player.status = 'ELIGIBLE_UNDRAFTED';
      player.keeper_cost_2026_round = 10;
      player.eligibility_basis = 'Not selected in the 2025 draft; first keeper season uses the undrafted-player 10th-round cost.';
    }
  }
}

result.rule.undrafted_first_keeper_round = 10;
result.rule.max_keeper_uses = 2;
result.rule.interpretation = 'A player may be drafted/acquired and then kept twice. After two keeper uses, the player returns to the draft pool. A player not selected in the immediately preceding draft is treated as an undrafted acquisition at a 10th-round first keeper cost.';
result.enriched_at = new Date().toISOString();

fs.writeFileSync(auditPath, JSON.stringify(result, null, 2));
console.log(JSON.stringify({ enriched: true, openings: result.openings?.length || 0 }));
