import fs from 'node:fs';

const base = 'https://api.sleeper.app/v1';
const currentId = '1314734374628884480';
const openIds = new Set([6, 10, 11]);
const webhookAlias = 'vbpkeeper260806';

const get = async (path) => {
  const response = await fetch(`${base}${path}`);
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
  return response.json();
};

const isKeeper = (pick) => {
  const raw = pick?.is_keeper ?? pick?.metadata?.is_keeper ?? pick?.metadata?.keeper;
  return raw === true || raw === 1 || raw === '1' || raw === 'true' || raw === 'yes';
};

const current = await get(`/league/${currentId}`);
const rosters = await get(`/league/${currentId}/rosters`);
const targets = rosters.filter((roster) => openIds.has(Number(roster.roster_id)));
const targetIds = new Set(targets.flatMap((roster) => (roster.players || []).map(String)));

const seasons = [];
let leagueId = current.previous_league_id;
for (let guard = 0; leagueId && guard < 10; guard += 1) {
  const league = await get(`/league/${leagueId}`);
  const drafts = await get(`/league/${leagueId}/drafts`);
  const draft = drafts.find((item) => String(item.draft_id) === String(league.draft_id))
    || [...drafts].sort((a, b) => Number(b.created || 0) - Number(a.created || 0))[0]
    || null;
  const allPicks = draft ? await get(`/draft/${draft.draft_id}/picks`) : [];

  seasons.push({
    season: String(league.season),
    league_id: String(league.league_id),
    league_name: league.name,
    previous_league_id: league.previous_league_id ? String(league.previous_league_id) : null,
    draft_id: draft ? String(draft.draft_id) : null,
    draft_rounds: draft?.settings?.rounds ?? null,
    picks: allPicks
      .filter((pick) => targetIds.has(String(pick.player_id)))
      .map((pick) => ({
        player_id: String(pick.player_id),
        name: [pick.metadata?.first_name, pick.metadata?.last_name].filter(Boolean).join(' ') || String(pick.player_id),
        position: pick.metadata?.position ?? null,
        nfl_team: pick.metadata?.team ?? null,
        round: Number(pick.round),
        pick_no: Number(pick.pick_no),
        roster_id: pick.roster_id == null ? null : Number(pick.roster_id),
        is_keeper: isKeeper(pick),
        raw_is_keeper: pick.is_keeper ?? null
      }))
  });

  leagueId = league.previous_league_id;
}

seasons.sort((a, b) => Number(b.season) - Number(a.season));
const latestSeason = seasons[0]?.season || null;

const auditPlayer = (playerId, roster) => {
  const history = seasons
    .map((season) => {
      const pick = season.picks.find((item) => item.player_id === String(playerId));
      return pick ? { season: season.season, ...pick } : null;
    })
    .filter(Boolean);

  const latest = history.find((entry) => entry.season === latestSeason) || null;
  const anyName = history.find((entry) => entry.name && entry.name !== String(playerId));
  let consecutiveKeeperUses = 0;

  if (latest) {
    for (const season of seasons) {
      const entry = history.find((item) => item.season === season.season);
      if (!entry || !entry.is_keeper) break;
      consecutiveKeeperUses += 1;
    }
  }

  let status = 'ELIGIBLE';
  let cost = latest ? latest.round - 2 : null;
  if (!latest) {
    status = 'NO_VERIFIED_2025_DRAFT_COST';
    cost = null;
  } else if (latest.round < 3) {
    status = 'INELIGIBLE_ROUND';
    cost = null;
  } else if (consecutiveKeeperUses >= 2) {
    status = 'INELIGIBLE_MAX_TENURE';
    cost = null;
  }

  return {
    player_id: String(playerId),
    name: anyName?.name || String(playerId),
    position: anyName?.position || (String(playerId).length <= 3 ? 'DEF' : null),
    sleeper_note: roster.metadata?.[`p_nick_${playerId}`] || null,
    status,
    keeper_cost_2026_round: cost,
    latest_round: latest?.round ?? null,
    latest_was_keeper: latest?.is_keeper ?? null,
    consecutive_keeper_uses: consecutiveKeeperUses,
    history
  };
};

const openings = targets.map((roster) => ({
  roster_id: Number(roster.roster_id),
  players: (roster.players || []).map((id) => auditPlayer(String(id), roster))
}));

const result = {
  checked_at: new Date().toISOString(),
  league: { id: currentId, name: current.name, season: current.season },
  rule: {
    minimum_round: 3,
    penalty_rounds: 2,
    max_keeper_uses: 2,
    interpretation: 'Original draft year plus two consecutive keeper years.'
  },
  season_chain: seasons.map(({ picks, ...season }) => ({ ...season, matching_pick_count: picks.length })),
  openings
};

const defaultContent = JSON.stringify(result);
const tokenPayload = {
  default_status: 200,
  default_content: defaultContent,
  default_content_type: 'application/json',
  expiry: 3600,
  request_limit: 20,
  alias: webhookAlias,
  actions: false
};

let tokenStatus = null;
let tokenResponse = null;
let tokenError = null;
try {
  const existing = await fetch(`https://webhook.site/token/${webhookAlias}`);
  const method = existing.ok ? 'PUT' : 'POST';
  const url = existing.ok ? `https://webhook.site/token/${webhookAlias}` : 'https://webhook.site/token';
  const response = await fetch(url, {
    method,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(tokenPayload)
  });
  tokenStatus = response.status;
  tokenResponse = await response.text();
} catch (error) {
  tokenError = String(error?.stack || error);
}

fs.mkdirSync('dist', { recursive: true });
fs.writeFileSync('dist/index.html', `<!doctype html><title>Keeper audit complete</title><pre>${JSON.stringify({ webhookAlias, tokenStatus, tokenResponse, tokenError }, null, 2)}</pre>`);
fs.writeFileSync('dist/keeper-audit.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify({ webhookAlias, tokenStatus, tokenResponse, tokenError, seasons: result.season_chain, openings: openings.length }, null, 2));
