module.exports = async function handler(req, res) {
  const leagueId = '1314734374628884480';
  const base = 'https://api.sleeper.app/v1';

  try {
    const getJson = async (url) => {
      const response = await fetch(url, { headers: { 'user-agent': 'VBP-Fantasy-Network/1.0' } });
      if (!response.ok) throw new Error(`${response.status} ${response.statusText}: ${url}`);
      return response.json();
    };

    const [league, rosters, drafts, tradedPicks, players] = await Promise.all([
      getJson(`${base}/league/${leagueId}`),
      getJson(`${base}/league/${leagueId}/rosters`),
      getJson(`${base}/league/${leagueId}/drafts`),
      getJson(`${base}/league/${leagueId}/traded_picks`),
      getJson(`${base}/players/nfl`),
    ]);

    const latestDraft = [...drafts].sort((a, b) => Number(b.created || 0) - Number(a.created || 0))[0] || null;
    const draft = latestDraft ? await getJson(`${base}/draft/${latestDraft.draft_id}`) : null;

    let previousRosters = [];
    if (league.previous_league_id) {
      previousRosters = await getJson(`${base}/league/${league.previous_league_id}/rosters`);
    }

    const slotByRoster = {};
    if (draft?.slot_to_roster_id) {
      for (const [slot, rosterId] of Object.entries(draft.slot_to_roster_id)) {
        slotByRoster[String(rosterId)] = Number(slot);
      }
    }

    const vacancies = rosters
      .filter((roster) => !roster.owner_id)
      .map((roster) => {
        const prior = previousRosters.find((item) => Number(item.roster_id) === Number(roster.roster_id)) || null;
        const playerDetails = (roster.players || []).map((id) => {
          const player = players[id] || {};
          return {
            player_id: String(id),
            name: player.full_name || [player.first_name, player.last_name].filter(Boolean).join(' '),
            position: player.position || null,
            team: player.team || null,
            status: player.status || null,
            years_exp: player.years_exp ?? null,
          };
        });

        return {
          roster_id: Number(roster.roster_id),
          draft_slot: slotByRoster[String(roster.roster_id)] ?? null,
          current_settings: roster.settings || {},
          previous_settings: prior?.settings || null,
          metadata: roster.metadata || null,
          keepers: roster.keepers || [],
          players: playerDetails,
          reserve: roster.reserve || [],
          taxi: roster.taxi || [],
          incoming_traded_picks: tradedPicks.filter((pick) => Number(pick.owner_id) === Number(roster.roster_id)),
          outgoing_traded_picks: tradedPicks.filter((pick) => Number(pick.roster_id) === Number(roster.roster_id) && Number(pick.owner_id) !== Number(roster.roster_id)),
        };
      });

    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({
      checked_at: new Date().toISOString(),
      league: {
        league_id: league.league_id,
        name: league.name,
        season: league.season,
        status: league.status,
        total_rosters: league.total_rosters,
        previous_league_id: league.previous_league_id || null,
        roster_positions: league.roster_positions,
        settings: league.settings,
        scoring_settings: league.scoring_settings,
      },
      assigned_count: rosters.filter((roster) => Boolean(roster.owner_id)).length,
      vacancy_count: vacancies.length,
      vacancies,
      draft: draft ? {
        draft_id: draft.draft_id,
        status: draft.status,
        type: draft.type,
        settings: draft.settings,
        metadata: draft.metadata,
        slot_to_roster_id: draft.slot_to_roster_id,
      } : null,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
