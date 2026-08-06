import fs from 'node:fs';

const base = 'https://api.sleeper.app/v1';
const leagueId = '1314734374628884480';
const season = '2026';
const targetRosters = [6, 10, 11];
const formId = '262176902106049';

const get = async (path) => {
  const response = await fetch(`${base}${path}`);
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
  return response.json();
};

const league = await get(`/league/${leagueId}`);
const drafts = await get(`/league/${leagueId}/drafts`);
const traded = await get(`/league/${leagueId}/traded_picks`);
const rosters = await get(`/league/${leagueId}/rosters`);

const draft = drafts.find((item) => String(item.draft_id) === String(league.draft_id))
  || [...drafts].sort((a, b) => Number(b.created || 0) - Number(a.created || 0))[0]
  || null;

const rounds = Number(draft?.settings?.rounds || 13);
const rosterCount = Number(league.total_rosters || rosters.length || 12);
const currentOwner = new Map();

for (let originalRoster = 1; originalRoster <= rosterCount; originalRoster += 1) {
  for (let round = 1; round <= rounds; round += 1) {
    currentOwner.set(`${originalRoster}:${round}`, originalRoster);
  }
}

const relevantTrades = traded.filter((pick) => String(pick.season) === season && Number(pick.round) <= rounds);
for (const pick of relevantTrades) {
  currentOwner.set(`${Number(pick.roster_id)}:${Number(pick.round)}`, Number(pick.owner_id));
}

const inventories = targetRosters.map((target) => {
  const owned = [];
  const missingOwn = [];

  for (let round = 1; round <= rounds; round += 1) {
    for (let originalRoster = 1; originalRoster <= rosterCount; originalRoster += 1) {
      if (currentOwner.get(`${originalRoster}:${round}`) === target) {
        owned.push({
          round,
          original_roster_id: originalRoster,
          is_own_pick: originalRoster === target
        });
      }
    }

    if (currentOwner.get(`${target}:${round}`) !== target) {
      missingOwn.push({
        round,
        current_owner_roster_id: currentOwner.get(`${target}:${round}`)
      });
    }
  }

  const byRound = {};
  for (const pick of owned) {
    byRound[pick.round] ||= [];
    byRound[pick.round].push(pick);
  }

  return {
    roster_id: target,
    total_picks: owned.length,
    owned,
    by_round: byRound,
    missing_own_picks: missingOwn
  };
});

const result = {
  checked_at: new Date().toISOString(),
  league: {
    id: leagueId,
    name: league.name,
    season: league.season,
    draft_id: draft?.draft_id ? String(draft.draft_id) : null,
    rounds,
    roster_count: rosterCount
  },
  relevant_traded_pick_records: relevantTrades,
  inventories
};

fs.mkdirSync('dist', { recursive: true });
fs.writeFileSync('dist/2026-pick-inventory.json', JSON.stringify(result, null, 2));
fs.writeFileSync('dist/index.html', '<!doctype html><title>2026 pick inventory complete</title><p>Complete</p>');

const params = new URLSearchParams();
params.set('formID', formId);
params.set('q2_textarea0', JSON.stringify(result));
const submit = await fetch(`https://submit.jotform.com/submit/${formId}`, {
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded;charset=UTF-8' },
  body: params,
  redirect: 'follow'
});

console.log(JSON.stringify({ submitStatus: submit.status, submitUrl: submit.url, result }, null, 2));
