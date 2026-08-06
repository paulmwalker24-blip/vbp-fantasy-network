module.exports = async function handler(req, res) {
  try {
    const base = 'https://api.sleeper.app/v1';
    const currentLeagueId = '1314734374628884480';
    const openRosterIds = new Set([6, 10, 11]);

    const get = async (path) => {
      const response = await fetch(`${base}${path}`);
      if (!response.ok) throw new Error(`${path}: ${response.status}`);
      return response.json();
    };

    const keeperFlag = (pick) => {
      const raw = pick?.is_keeper ?? pick?.metadata?.is_keeper ?? pick?.metadata?.keeper;
      return raw === true || raw === 1 || raw === '1' || raw === 'true' || raw === 'yes';
    };

    const currentLeague = await get(`/league/${currentLeagueId}`);
    const currentRosters = await get(`/league/${currentLeagueId}/rosters`);
    const players = await get('/players/nfl');
    const targetRosters = currentRosters.filter((r) => openRosterIds.has(Number(r.roster_id)));
    const targetIds = new Set(targetRosters.flatMap((r) => (r.players || []).map(String)));

    const seasons = [];
    let leagueId = currentLeague.previous_league_id;
    for (let guard = 0; leagueId && guard < 10; guard += 1) {
      const league = await get(`/league/${leagueId}`);
      const drafts = await get(`/league/${leagueId}/drafts`);
      const draft = drafts.find((d) => String(d.draft_id) === String(league.draft_id))
        || [...drafts].sort((a, b) => Number(b.created || 0) - Number(a.created || 0))[0]
        || null;
      const picks = draft ? await get(`/draft/${draft.draft_id}/picks`) : [];
      seasons.push({
        season: String(league.season),
        league_id: String(league.league_id),
        draft_id: draft ? String(draft.draft_id) : null,
        picks: picks.filter((p) => targetIds.has(String(p.player_id))).map((p) => ({
          player_id: String(p.player_id),
          round: Number(p.round),
          pick_no: Number(p.pick_no),
          roster_id: p.roster_id == null ? null : Number(p.roster_id),
          is_keeper: keeperFlag(p),
          raw_is_keeper: p.is_keeper ?? null,
          metadata: p.metadata ?? null
        }))
      });
      leagueId = league.previous_league_id;
    }
    seasons.sort((a, b) => Number(b.season) - Number(a.season));
    const latestSeason = seasons[0]?.season || null;

    const playerName = (id) => {
      if (String(id).length <= 3) return String(id);
      const p = players[String(id)];
      return p?.full_name || `${p?.first_name || ''} ${p?.last_name || ''}`.trim() || String(id);
    };

    const result = targetRosters.map((roster) => ({
      roster_id: Number(roster.roster_id),
      players: (roster.players || []).map((id) => {
        const history = seasons.map((s) => {
          const pick = s.picks.find((p) => p.player_id === String(id));
          return pick ? { season: s.season, ...pick } : null;
        }).filter(Boolean);
        const latest = history.find((h) => h.season === latestSeason) || null;
        let keeperUses = 0;
        if (latest) {
          for (const s of seasons) {
            const entry = history.find((h) => h.season === s.season);
            if (!entry) break;
            if (entry.is_keeper) keeperUses += 1;
            else break;
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
        } else if (keeperUses >= 2) {
          status = 'INELIGIBLE_MAX_TENURE';
          cost = null;
        }
        return {
          player_id: String(id),
          name: playerName(id),
          position: String(id).length <= 3 ? 'DEF' : players[String(id)]?.position || null,
          status,
          keeper_cost_2026_round: cost,
          latest_round: latest?.round ?? null,
          latest_was_keeper: latest?.is_keeper ?? null,
          consecutive_keeper_uses: keeperUses,
          sleeper_note: roster.metadata?.[`p_nick_${id}`] || null,
          history
        };
      })
    }));

    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({
      checked_at: new Date().toISOString(),
      league: { id: currentLeagueId, name: currentLeague.name, season: currentLeague.season },
      rule: { minimum_round: 3, penalty_rounds: 2, max_keeper_uses: 2 },
      season_chain: seasons.map((s) => ({ season: s.season, league_id: s.league_id, draft_id: s.draft_id })),
      openings: result
    });
  } catch (error) {
    res.status(500).json({ error: String(error?.stack || error) });
  }
};
