const LEAGUES_JSON_URL = "data/leagues.json";
const CENTER_FORMAT = "bestball";
const MAX_BBU_WEEKS = 17;
const SAMPLE_PREVIEW_WEEK = 5;
const OVERALL_LEADERBOARD_LIMIT = 20;
const SAMPLE_TEAM_SUFFIXES = [
  "Outlaws",
  "Signal",
  "Breakers",
  "Kings",
  "Rush",
  "Voltage",
  "Union",
  "Rebels",
  "Storm",
  "Rise"
];
const SAMPLE_TEAM_PREFIXES = [
  "Atlas",
  "Copper",
  "Night",
  "Summit",
  "Harbor",
  "Cinder",
  "Nova",
  "Delta",
  "Royal",
  "Echo"
];
const BBU_POWER_SCORE_WEIGHTS = {
  lineup: 0.45,
  depth: 0.30,
  bigWeeks: 0.15,
  scoringFit: 0.10
};
const BBU_POWER_RANKINGS = [
  {
    rank: 1,
    team: "Cameron74",
    league: "BBU2",
    score: 90,
    summary: "QB room: Lamar Jackson, Justin Herbert. Starter grade 76.8. Bench grade 72. 5 spike-week pieces at 78+ value.",
    core: "Bijan Robinson, Lamar Jackson, Drake London, Josh Jacobs, Justin Herbert, Trevor Lawrence, David Montgomery"
  },
  {
    rank: 2,
    team: "gunnar21",
    league: "BBU3",
    score: 89,
    summary: "QB room: Drake Maye, Fernando Mendoza. Starter grade 77.8. Bench grade 70. 4 spike-week pieces at 78+ value.",
    core: "Drake Maye, Jahmyr Gibbs, Justin Jefferson, Nico Collins, RJ Harvey, DJ Moore, Tyler Warren"
  },
  {
    rank: 3,
    team: "OmahaaaSet$10",
    league: "BBU3",
    score: 89,
    summary: "QB room: Joe Burrow, Jaxson Dart. Starter grade 75.9. Bench grade 72.1. 3 spike-week pieces at 78+ value.",
    core: "Ja'Marr Chase, Joe Burrow, Jaxson Dart, Kyren Williams, Ladd McConkey, C.J. Stroud, Jeremiyah Love"
  },
  {
    rank: 4,
    team: "OutlawReturns",
    league: "BBU2",
    score: 88,
    summary: "QB room: Drake Maye, Sam Darnold. Starter grade 77.2. Bench grade 70.9. 3 spike-week pieces at 78+ value.",
    core: "Drake Maye, Amon-Ra St. Brown, De'Von Achane, Breece Hall, D'Andre Swift, Zay Flowers, Sam Darnold"
  },
  {
    rank: 5,
    team: "mguzz",
    league: "BBU1",
    score: 87,
    summary: "QB room: Joe Burrow, Baker Mayfield. Starter grade 77.2. Bench grade 71. 4 spike-week pieces at 78+ value.",
    core: "Puka Nacua, Joe Burrow, Nico Collins, Chase Brown, Derrick Henry, Zay Flowers, Baker Mayfield"
  },
  {
    rank: 6,
    team: "ThrowwUpTheX",
    league: "BBU1",
    score: 85,
    summary: "QB room: Jalen Hurts, Justin Herbert. Starter grade 76.6. Bench grade 71.6. 4 spike-week pieces at 78+ value.",
    core: "Ja'Marr Chase, Saquon Barkley, Justin Herbert, Jalen Hurts, Kyren Williams, George Pickens, Tony Pollard"
  },
  {
    rank: 7,
    team: "jessegambo",
    league: "BBU1",
    score: 84,
    summary: "QB room: Caleb Williams, Jared Goff. Starter grade 76.9. Bench grade 70.9. 4 spike-week pieces at 78+ value.",
    core: "Jahmyr Gibbs, Caleb Williams, Drake London, Josh Jacobs, Terry McLaurin, Jared Goff, Sam Darnold"
  },
  {
    rank: 8,
    team: "swampraider",
    league: "BBU2",
    score: 84,
    summary: "QB room: Joe Burrow, Jaxson Dart. Starter grade 76.5. Bench grade 71.1. 4 spike-week pieces at 78+ value.",
    core: "Ja'Marr Chase, Joe Burrow, Jaxson Dart, Chase Brown, Kyren Williams, Chris Olave, TreVeyon Henderson"
  },
  {
    rank: 9,
    team: "DSnyder5",
    league: "BBU3",
    score: 84,
    summary: "QB room: Dak Prescott, Baker Mayfield. Starter grade 76.2. Bench grade 72.6. 2 spike-week pieces at 78+ value.",
    core: "Jaxon Smith-Njigba, De'Von Achane, Breece Hall, Dak Prescott, David Montgomery, Baker Mayfield, Rome Odunze"
  },
  {
    rank: 10,
    team: "XWILL07",
    league: "BBU3",
    score: 82,
    summary: "QB room: Caleb Williams, Brock Purdy. Starter grade 77. Bench grade 71.4. 4 spike-week pieces at 78+ value.",
    core: "Kenneth Walker, Caleb Williams, Omarion Hampton, Drake London, Brock Purdy, A.J. Brown, Tee Higgins"
  },
  {
    rank: 11,
    team: "OmahaaaSet$10",
    league: "BBU4",
    score: 82,
    summary: "QB room: Joe Burrow, Jaxson Dart. Starter grade 76.2. Bench grade 70.4. 5 spike-week pieces at 78+ value.",
    core: "James Cook, Joe Burrow, Chase Brown, Nico Collins, Jaxson Dart, Terry McLaurin, Courtland Sutton"
  },
  {
    rank: 12,
    team: "Dropswitch",
    league: "BBU4",
    score: 81,
    summary: "QB room: Justin Herbert, Bo Nix. Starter grade 76.9. Bench grade 70. 4 spike-week pieces at 78+ value.",
    core: "Jahmyr Gibbs, CeeDee Lamb, Justin Herbert, Josh Jacobs, RJ Harvey, Tee Higgins, Harold Fannin"
  },
  {
    rank: 13,
    team: "Tacious00",
    league: "BBU4",
    score: 81,
    summary: "QB room: Jalen Hurts, Malik Willis. Starter grade 76.6. Bench grade 70.7. 3 spike-week pieces at 78+ value.",
    core: "Bijan Robinson, Drake London, Jalen Hurts, Tetairoa McMillan, TreVeyon Henderson, Matthew Stafford, Davante Adams"
  },
  {
    rank: 14,
    team: "DSnyder5",
    league: "BBU4",
    score: 80,
    summary: "QB room: Trevor Lawrence, Baker Mayfield. Starter grade 75.9. Bench grade 71.4. 1 spike-week piece at 78+ value.",
    core: "Jonathan Taylor, Derrick Henry, Trevor Lawrence, A.J. Brown, Baker Mayfield, Ladd McConkey, Jeremiyah Love"
  },
  {
    rank: 15,
    team: "jakeejk",
    league: "BBU4",
    score: 80,
    summary: "QB room: Brock Purdy, C.J. Stroud. Starter grade 76. Bench grade 70.7. 2 spike-week pieces at 78+ value.",
    core: "Ashton Jeanty, De'Von Achane, Chris Olave, Brock Purdy, Kyren Williams, Rome Odunze, C.J. Stroud"
  },
  {
    rank: 16,
    team: "PeterJ555",
    league: "BBU4",
    score: 80,
    summary: "QB room: Josh Allen, Kyler Murray. Starter grade 76.6. Bench grade 71.1. 3 spike-week pieces at 78+ value.",
    core: "Ja'Marr Chase, Josh Allen, Justin Jefferson, Bhayshul Tuten, Kyler Murray, DJ Moore, Rashee Rice"
  },
  {
    rank: 17,
    team: "gunnar21",
    league: "BBU1",
    score: 79,
    summary: "QB room: Lamar Jackson, Malik Willis. Starter grade 77. Bench grade 68.9. 2 spike-week pieces at 78+ value.",
    core: "Bijan Robinson, Lamar Jackson, Trey McBride, Breece Hall, RJ Harvey, Ladd McConkey, Rome Odunze"
  },
  {
    rank: 18,
    team: "jakeejk",
    league: "BBU1",
    score: 79,
    summary: "QB room: Brock Purdy, Jordan Love. Starter grade 76.1. Bench grade 71.7. 2 spike-week pieces at 78+ value.",
    core: "James Cook, Justin Jefferson, Brock Purdy, Tetairoa McMillan, Jordan Love, Emeka Egbuka, Chuba Hubbard"
  },
  {
    rank: 19,
    team: "DSnyder5",
    league: "BBU2",
    score: 79,
    summary: "QB room: Jalen Hurts, Baker Mayfield. Starter grade 77. Bench grade 71.9. 4 spike-week pieces at 78+ value.",
    core: "Jonathan Taylor, Saquon Barkley, Nico Collins, Jalen Hurts, RJ Harvey, Baker Mayfield, Ladd McConkey"
  },
  {
    rank: 20,
    team: "Fradulent",
    league: "BBU3",
    score: 77,
    summary: "QB room: Trevor Lawrence, Jordan Love. Starter grade 75.9. Bench grade 71.3. 2 spike-week pieces at 78+ value.",
    core: "Christian McCaffrey, Josh Jacobs, Trevor Lawrence, Jordan Love, Zay Flowers, Sam Darnold, Travis Etienne"
  }
];
const bestBallCenterState = {
  selectedSection: window.location.hash === "#powerRankings" ? "power" : "scoring"
};

function text(value) {
  return String(value ?? "").trim();
}

function toNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatTimestamp(value) {
  if (!value) {
    return new Date().toLocaleString();
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return text(value);
  }

  return parsed.toLocaleString();
}

function formatPoints(value) {
  return toNumber(value).toFixed(2);
}

function formatRecord(entry) {
  const wins = toNumber(entry?.wins);
  const losses = toNumber(entry?.losses);
  const ties = toNumber(entry?.ties);

  if (ties > 0) {
    return `${wins}-${losses}-${ties}`;
  }

  return `${wins}-${losses}`;
}

function getRecordValue(entry) {
  return toNumber(entry?.wins) + (toNumber(entry?.ties) * 0.5);
}

function getEntryKey(entry) {
  return `${text(entry?.leagueRecordId)}|${text(entry?.rosterId)}`;
}

function createEmptyState(message, colSpan = 1) {
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = colSpan;
  cell.className = "format-center-table-empty";
  cell.textContent = message;
  row.appendChild(cell);
  return row;
}

function getLeagueOrderValue(entry) {
  const match = text(entry?.id).match(/(\d+)$/);
  return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER;
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Request failed with status ${response.status} for ${url}`);
  }

  return response.json();
}

async function loadBestBallLeagues() {
  const payload = await fetchJson(LEAGUES_JSON_URL);
  const leagues = Array.isArray(payload) ? payload : payload.leagues;

  if (!Array.isArray(leagues)) {
    throw new Error("Local leagues JSON is missing a leagues array.");
  }

  return [...leagues]
    .filter(league => text(league?.format).toLowerCase() === CENTER_FORMAT)
    .sort((left, right) => getLeagueOrderValue(left) - getLeagueOrderValue(right));
}

function buildStandingsEntry(localLeague, roster, user) {
  const teamName = text(user?.metadata?.team_name) || text(user?.display_name) || `Roster ${toNumber(roster?.roster_id)}`;
  const pointsFor = toNumber(roster?.settings?.fpts) + (toNumber(roster?.settings?.fpts_decimal) / 100);

  return {
    leagueRecordId: text(localLeague?.id),
    leagueName: text(localLeague?.name),
    rosterId: toNumber(roster?.roster_id),
    ownerId: text(roster?.owner_id),
    teamName,
    displayName: text(user?.display_name),
    wins: toNumber(roster?.settings?.wins),
    losses: toNumber(roster?.settings?.losses),
    ties: toNumber(roster?.settings?.ties),
    pointsFor,
    pointsForDisplay: formatPoints(pointsFor)
  };
}

function compareLeagueStandings(left, right, weeklyHighWins) {
  const recordDelta = getRecordValue(right) - getRecordValue(left);
  if (recordDelta !== 0) {
    return recordDelta;
  }

  const pointDelta = toNumber(right?.pointsFor) - toNumber(left?.pointsFor);
  if (pointDelta !== 0) {
    return pointDelta;
  }

  const weeklyHighDelta = (weeklyHighWins.get(getEntryKey(right)) || 0) - (weeklyHighWins.get(getEntryKey(left)) || 0);
  if (weeklyHighDelta !== 0) {
    return weeklyHighDelta;
  }

  return text(left?.teamName).localeCompare(text(right?.teamName));
}

function compareOverallPoints(left, right, weeklyHighWins) {
  const pointDelta = toNumber(right?.pointsFor) - toNumber(left?.pointsFor);
  if (pointDelta !== 0) {
    return pointDelta;
  }

  const recordDelta = getRecordValue(right) - getRecordValue(left);
  if (recordDelta !== 0) {
    return recordDelta;
  }

  const weeklyHighDelta = (weeklyHighWins.get(getEntryKey(right)) || 0) - (weeklyHighWins.get(getEntryKey(left)) || 0);
  if (weeklyHighDelta !== 0) {
    return weeklyHighDelta;
  }

  return text(left?.teamName).localeCompare(text(right?.teamName));
}

async function loadLeagueSnapshot(localLeague) {
  const sleeperLeagueId = text(localLeague?.sleeperLeagueId);
  if (!sleeperLeagueId) {
    throw new Error(`Missing Sleeper league id for ${text(localLeague?.id)}.`);
  }

  const [liveLeague, rosters, users] = await Promise.all([
    fetchJson(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}`),
    fetchJson(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/rosters`),
    fetchJson(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/users`)
  ]);

  const usersById = new Map(
    (Array.isArray(users) ? users : []).map(user => [text(user?.user_id), user])
  );

  const standings = (Array.isArray(rosters) ? rosters : []).map(roster => {
    const ownerId = text(roster?.owner_id);
    return buildStandingsEntry(localLeague, roster, usersById.get(ownerId));
  });

  return {
    leagueRecordId: text(localLeague?.id),
    leagueName: text(localLeague?.name),
    sleeperLeagueId,
    inviteLink: text(localLeague?.inviteLink),
    buyIn: toNumber(localLeague?.buyIn),
    teams: toNumber(localLeague?.teams),
    filled: (Array.isArray(rosters) ? rosters : []).filter(roster => text(roster?.owner_id)).length,
    season: text(liveLeague?.season) || text(localLeague?.sleeperSeason),
    status: text(liveLeague?.status || localLeague?.status).toLowerCase(),
    standings,
    standingsByRosterId: new Map(standings.map(entry => [entry.rosterId, entry]))
  };
}

function hasMeaningfulStandings(snapshots) {
  return snapshots.some(snapshot =>
    snapshot.standings.some(entry =>
      toNumber(entry?.pointsFor) > 0 ||
      toNumber(entry?.wins) > 0 ||
      toNumber(entry?.losses) > 0 ||
      toNumber(entry?.ties) > 0
    )
  );
}

function incrementMap(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

async function getSeasonWeekCount(hasData) {
  if (!hasData) {
    return 0;
  }

  try {
    const state = await fetchJson("https://api.sleeper.app/v1/state/nfl");
    const seasonType = text(state?.season_type).toLowerCase();
    const currentLeg = toNumber(state?.leg);

    if (seasonType === "regular") {
      return Math.min(Math.max(currentLeg, 0), MAX_BBU_WEEKS);
    }

    if (seasonType === "post" || seasonType === "off" || seasonType === "pre") {
      return MAX_BBU_WEEKS;
    }
  } catch (error) {
    console.warn("Unable to load Sleeper NFL state for BBU center:", error);
  }

  return 0;
}

async function buildWeeklyContext(snapshots, weekCount) {
  const overallWeeklyHighWins = new Map();
  const weeklyHighRows = [];

  if (!weekCount) {
    return { overallWeeklyHighWins, weeklyHighRows };
  }

  for (let week = 1; week <= weekCount; week += 1) {
    const weeklyResponses = await Promise.all(
      snapshots.map(async snapshot => {
        try {
          const matchups = await fetchJson(`https://api.sleeper.app/v1/league/${encodeURIComponent(snapshot.sleeperLeagueId)}/matchups/${week}`);
          return { snapshot, matchups: Array.isArray(matchups) ? matchups : [] };
        } catch (error) {
          console.warn(`Unable to load BBU matchups for ${snapshot.leagueRecordId} week ${week}:`, error);
          return { snapshot, matchups: [] };
        }
      })
    );

    const overallCandidates = [];

    weeklyResponses.forEach(({ snapshot, matchups }) => {
      const entries = matchups.map(matchup => {
        const rosterId = toNumber(matchup?.roster_id);
        const standing = snapshot.standingsByRosterId.get(rosterId);

        return {
          leagueRecordId: snapshot.leagueRecordId,
          leagueName: snapshot.leagueName,
          rosterId,
          teamName: text(standing?.teamName) || `Roster ${rosterId}`,
          points: toNumber(matchup?.points)
        };
      });

      overallCandidates.push(...entries);
    });

    const overallMax = Math.max(0, ...overallCandidates.map(entry => entry.points));
    if (overallMax <= 0) {
      continue;
    }

    const winners = overallCandidates.filter(entry => entry.points === overallMax);
    winners.forEach(entry => incrementMap(overallWeeklyHighWins, getEntryKey(entry)));

    weeklyHighRows.push({
      week,
      score: overallMax,
      winners
    });
  }

  return { overallWeeklyHighWins, weeklyHighRows };
}

function getLeagueLeader(snapshot, weeklyHighWins) {
  const standings = [...snapshot.standings].sort((left, right) => compareLeagueStandings(left, right, weeklyHighWins));
  return standings[0] || null;
}

function buildCombinedLeaderboard(snapshots, weeklyHighWins) {
  return snapshots
    .flatMap(snapshot => snapshot.standings)
    .sort((left, right) => compareOverallPoints(left, right, weeklyHighWins));
}

function getSampleRecordForRank(rank) {
  const templates = [
    { wins: 8, losses: 2, ties: 0 },
    { wins: 8, losses: 2, ties: 0 },
    { wins: 7, losses: 3, ties: 0 },
    { wins: 7, losses: 3, ties: 0 },
    { wins: 6, losses: 4, ties: 0 },
    { wins: 5, losses: 5, ties: 0 },
    { wins: 5, losses: 5, ties: 0 },
    { wins: 4, losses: 6, ties: 0 },
    { wins: 3, losses: 7, ties: 0 },
    { wins: 2, losses: 8, ties: 0 }
  ];

  return templates[Math.min(rank, templates.length - 1)];
}

function buildSampleCenter(liveSnapshots) {
  const sampleSnapshots = liveSnapshots.map((snapshot, leagueIndex) => {
    const teamCount = Math.max(toNumber(snapshot?.teams), 10);
    const sampleEntries = [];

    for (let slotIndex = 0; slotIndex < teamCount; slotIndex += 1) {
      const prefix = SAMPLE_TEAM_PREFIXES[(slotIndex + leagueIndex) % SAMPLE_TEAM_PREFIXES.length];
      const suffix = SAMPLE_TEAM_SUFFIXES[(slotIndex + (leagueIndex * 2)) % SAMPLE_TEAM_SUFFIXES.length];
      const teamName = `${prefix} ${suffix}`;
      const weeklyScores = [];

      for (let week = 1; week <= SAMPLE_PREVIEW_WEEK; week += 1) {
        const score = Number((
          95 +
          ((teamCount - slotIndex) * 4.35) +
          (leagueIndex * 1.65) +
          (week * 2.4) +
          (((slotIndex + 2) * (week + 1) + leagueIndex) % 9)
        ).toFixed(2));

        weeklyScores.push(score);
      }

      const pointsFor = weeklyScores.reduce((sum, score) => sum + score, 0);

      sampleEntries.push({
        leagueRecordId: snapshot.leagueRecordId,
        leagueName: snapshot.leagueName,
        rosterId: slotIndex + 1,
        ownerId: `sample-${snapshot.leagueRecordId}-${slotIndex + 1}`,
        teamName,
        displayName: `${snapshot.leagueName} ${slotIndex + 1}`,
        pointsFor,
        pointsForDisplay: formatPoints(pointsFor),
        sampleWeeklyScores: weeklyScores
      });
    }

    const standings = sampleEntries
      .sort((left, right) => toNumber(right.pointsFor) - toNumber(left.pointsFor))
      .map((entry, index) => {
        const record = getSampleRecordForRank(index);
        return {
          ...entry,
          wins: record.wins,
          losses: record.losses,
          ties: record.ties
        };
      });

    return {
      ...snapshot,
      isSample: true,
      standings,
      standingsByRosterId: new Map(standings.map(entry => [entry.rosterId, entry]))
    };
  });

  const overallWeeklyHighWins = new Map();
  const weeklyHighRows = [];

  for (let week = 1; week <= SAMPLE_PREVIEW_WEEK; week += 1) {
    const overallCandidates = [];

    sampleSnapshots.forEach(snapshot => {
      const weekEntries = snapshot.standings.map(entry => ({
        leagueRecordId: entry.leagueRecordId,
        leagueName: entry.leagueName,
        rosterId: entry.rosterId,
        teamName: entry.teamName,
        points: toNumber(entry.sampleWeeklyScores?.[week - 1])
      }));

      overallCandidates.push(...weekEntries);
    });

    const overallMax = Math.max(0, ...overallCandidates.map(entry => entry.points));
    const winners = overallCandidates.filter(entry => entry.points === overallMax);

    winners.forEach(entry => incrementMap(overallWeeklyHighWins, getEntryKey(entry)));

    weeklyHighRows.push({
      week,
      score: overallMax,
      winners
    });
  }

  return {
    snapshots: sampleSnapshots,
    overallWeeklyHighWins,
    weeklyHighRows,
    overallLeaderboard: buildCombinedLeaderboard(sampleSnapshots, overallWeeklyHighWins),
    isSample: true
  };
}

function renderMeta(snapshots, overallLeaderboard, mode) {
  const seasonLabel = document.getElementById("centerSeasonLabel");
  const lastUpdated = document.getElementById("centerLastUpdated");
  const leagueCount = document.getElementById("centerLeagueCount");
  const teamCount = document.getElementById("centerTeamCount");
  const overallLeader = document.getElementById("centerOverallLeader");
  const statusBanner = document.getElementById("centerStatusBanner");
  const subtitle = document.getElementById("centerPageSubtitle");

  const seasons = Array.from(new Set(snapshots.map(snapshot => text(snapshot?.season)).filter(Boolean)));
  const totalTeams = snapshots.reduce((sum, snapshot) => sum + snapshot.standings.length, 0);
  const leader = overallLeaderboard[0] || null;

  seasonLabel.textContent = mode.isSample
    ? `${seasons.length ? seasons.join(", ") : "Unknown"} Example Week ${SAMPLE_PREVIEW_WEEK}`
    : seasons.length ? seasons.join(", ") : "Unknown";
  lastUpdated.textContent = new Date().toLocaleString();
  leagueCount.textContent = String(snapshots.length);
  teamCount.textContent = String(totalTeams);
  overallLeader.textContent = mode.showData && leader
    ? `${leader.teamName} (${leader.leagueName})`
    : "Season not active yet";

  statusBanner.hidden = false;

  if (mode.isSample) {
    subtitle.textContent = `Example Week ${SAMPLE_PREVIEW_WEEK} preview for Best Ball Union while live standings are still pre-draft or not yet meaningful.`;
    statusBanner.className = "format-center-banner is-provisional";
    statusBanner.textContent = `Example Week ${SAMPLE_PREVIEW_WEEK} preview is currently shown so visitors can see league leaders, the overall high-point race, and weekly high-score tracking before live Best Ball Union results are available.`;
    return;
  }

  subtitle.textContent = "Public leaderboard and weekly high-score snapshot for Best Ball Union.";
  statusBanner.className = "format-center-banner is-live";
  statusBanner.textContent = "Live standings and weekly high scores are being pulled directly from Sleeper for the current Best Ball Union field.";
}

function renderLeagueLeaders(snapshots, overallWeeklyHighWins, mode) {
  const container = document.getElementById("leagueLeadersContainer");
  container.innerHTML = "";

  if (!snapshots.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No Best Ball Union leagues are configured for this center yet.";
    container.appendChild(empty);
    return;
  }

  snapshots.forEach(snapshot => {
    const card = document.createElement("article");
    card.className = "format-center-division-card";

    const name = document.createElement("h3");
    name.textContent = snapshot.leagueName;
    card.appendChild(name);

    if (!mode.showData) {
      const status = document.createElement("p");
      status.className = "format-center-division-count";
      status.textContent = "Standings unavailable pre-draft";
      card.appendChild(status);
      container.appendChild(card);
      return;
    }

    const leader = getLeagueLeader(snapshot, overallWeeklyHighWins);
    if (!leader) {
      const empty = document.createElement("p");
      empty.className = "format-center-division-count";
      empty.textContent = "Leader unavailable";
      card.appendChild(empty);
      container.appendChild(card);
      return;
    }

    const leaderName = document.createElement("p");
    leaderName.className = "format-center-division-count";
    leaderName.textContent = leader.teamName;

    const leaderMeta = document.createElement("p");
    leaderMeta.className = "format-center-scoreboard-note";
    leaderMeta.textContent = `${formatRecord(leader)} | ${leader.pointsForDisplay} PF`;

    const overallWeeklyHighCount = document.createElement("p");
    overallWeeklyHighCount.className = "format-center-scoreboard-note";
    overallWeeklyHighCount.textContent = `Overall weekly highs: ${overallWeeklyHighWins.get(getEntryKey(leader)) || 0}`;

    card.append(leaderName, leaderMeta, overallWeeklyHighCount);
    container.appendChild(card);
  });
}

function renderOverallLeaderboard(overallLeaderboard, weeklyHighWins, mode) {
  const body = document.getElementById("overallLeaderboardBody");
  body.innerHTML = "";

  if (!mode.showData || !overallLeaderboard.length) {
    body.appendChild(createEmptyState("Overall points will appear here once Best Ball Union starts scoring.", 5));
    return;
  }

  overallLeaderboard.slice(0, OVERALL_LEADERBOARD_LIMIT).forEach((entry, index) => {
    const row = document.createElement("tr");

    const rank = document.createElement("td");
    rank.textContent = String(index + 1);

    const team = document.createElement("td");
    const teamName = document.createElement("strong");
    teamName.textContent = entry.teamName;
    team.appendChild(teamName);

    const league = document.createElement("td");
    league.textContent = entry.leagueName;

    const record = document.createElement("td");
    record.textContent = formatRecord(entry);

    const points = document.createElement("td");
    points.textContent = entry.pointsForDisplay;

    row.append(rank, team, league, record, points);
    body.appendChild(row);
  });
}

function renderWeeklyHighScores(weeklyHighRows, mode) {
  const body = document.getElementById("weeklyHighScoresBody");
  body.innerHTML = "";

  if (!mode.showData) {
    body.appendChild(createEmptyState("Weekly high scores will appear here once Best Ball Union games begin.", 4));
    return;
  }

  if (!weeklyHighRows.length) {
    body.appendChild(createEmptyState("No weekly high-score results are available yet.", 4));
    return;
  }

  weeklyHighRows.forEach(rowData => {
    const row = document.createElement("tr");

    const week = document.createElement("td");
    week.textContent = `Week ${rowData.week}`;

    const teams = document.createElement("td");
    teams.textContent = rowData.winners.map(entry => entry.teamName).join(" / ");

    const leagues = document.createElement("td");
    leagues.textContent = rowData.winners.map(entry => entry.leagueName).join(" / ");

    const score = document.createElement("td");
    score.textContent = formatPoints(rowData.score);

    row.append(week, teams, leagues, score);
    body.appendChild(row);
  });
}

function renderPowerRankings() {
  const list = document.getElementById("bbuPowerRankingsList");
  if (!list) {
    return;
  }

  list.innerHTML = "";

  BBU_POWER_RANKINGS.forEach(entry => {
    const score = entry.score === undefined ? getBbuPowerScore(entry.grades) : toNumber(entry.score);
    const row = document.createElement("article");
    row.className = `power-ranking-row${entry.rank <= 3 ? " is-top" : ""}`;

    const rank = document.createElement("div");
    rank.className = "power-ranking-position";
    rank.textContent = String(entry.rank);

    const body = document.createElement("div");
    body.className = "power-ranking-body";

    const header = document.createElement("div");
    header.className = "power-ranking-header";

    const name = document.createElement("h3");
    name.textContent = entry.team;

    const scoreBadge = document.createElement("span");
    scoreBadge.className = "power-ranking-score";
    scoreBadge.textContent = `${entry.league} | ${score.toFixed(1)}`;

    const summary = document.createElement("p");
    summary.textContent = entry.summary;

    const core = document.createElement("p");
    core.className = "power-ranking-core";
    core.textContent = `Build keys: ${entry.core}`;

    const breakdown = document.createElement("p");
    breakdown.className = "power-ranking-breakdown";
    breakdown.textContent = entry.grades
      ? `Score: ${score.toFixed(1)} = lineup ${entry.grades.lineup} x 45%, depth ${entry.grades.depth} x 30%, big-week players ${entry.grades.bigWeeks} x 15%, scoring fit ${entry.grades.scoringFit} x 10%.`
      : `Generated score: ${score.toFixed(1)} from the latest Sleeper roster, draft, player-value, depth, quarterback, and health inputs.`;

    header.append(name, scoreBadge);
    body.append(header, summary, core, breakdown);
    row.append(rank, body);
    list.appendChild(row);
  });
}

function getBbuPowerScore(grades) {
  return (
    (toNumber(grades?.lineup) * BBU_POWER_SCORE_WEIGHTS.lineup) +
    (toNumber(grades?.depth) * BBU_POWER_SCORE_WEIGHTS.depth) +
    (toNumber(grades?.bigWeeks) * BBU_POWER_SCORE_WEIGHTS.bigWeeks) +
    (toNumber(grades?.scoringFit) * BBU_POWER_SCORE_WEIGHTS.scoringFit)
  );
}

function updateBestBallSectionTabs(options = {}) {
  const selectedSection = bestBallCenterState.selectedSection === "power" ? "power" : "scoring";
  const buttons = Array.from(document.querySelectorAll("[data-bbu-section]"));
  const panels = Array.from(document.querySelectorAll("[data-bbu-panel]"));

  buttons.forEach(button => {
    button.classList.toggle("is-active", text(button.dataset.bbuSection) === selectedSection);
  });

  panels.forEach(panel => {
    panel.hidden = text(panel.dataset.bbuPanel) !== selectedSection;
  });

  if (options.scroll) {
    const targetId = selectedSection === "power" ? "powerRankings" : "scoringCenter";
    document.getElementById(targetId)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function renderLoadFailure(error) {
  console.error("Best Ball Union center load failed:", error);

  document.getElementById("centerSeasonLabel").textContent = "Unavailable";
  document.getElementById("centerLastUpdated").textContent = "Unavailable";
  document.getElementById("centerLeagueCount").textContent = "0";
  document.getElementById("centerTeamCount").textContent = "0";
  document.getElementById("centerOverallLeader").textContent = "Unavailable";

  const banner = document.getElementById("centerStatusBanner");
  banner.hidden = false;
  banner.className = "format-center-banner is-provisional";
  banner.textContent = "The Best Ball Union center could not load the current data.";

  const leaders = document.getElementById("leagueLeadersContainer");
  leaders.innerHTML = "";
  const empty = document.createElement("div");
  empty.className = "empty-state";
  empty.textContent = "Unable to load Best Ball Union league data right now.";
  leaders.appendChild(empty);

  const leaderboardBody = document.getElementById("overallLeaderboardBody");
  leaderboardBody.innerHTML = "";
  leaderboardBody.appendChild(createEmptyState("Unable to load the overall leaderboard right now.", 5));

  const weeklyBody = document.getElementById("weeklyHighScoresBody");
  weeklyBody.innerHTML = "";
  weeklyBody.appendChild(createEmptyState("Unable to load weekly high scores right now.", 4));
}

async function loadCenter() {
  try {
    const localLeagues = await loadBestBallLeagues();
    const liveSnapshots = await Promise.all(localLeagues.map(loadLeagueSnapshot));
    const hasLiveData = hasMeaningfulStandings(liveSnapshots);

    let centerData;

    if (hasLiveData) {
      const weekCount = await getSeasonWeekCount(true);
      const { overallWeeklyHighWins, weeklyHighRows } = await buildWeeklyContext(liveSnapshots, weekCount);
      centerData = {
        snapshots: liveSnapshots,
        overallWeeklyHighWins,
        weeklyHighRows,
        overallLeaderboard: buildCombinedLeaderboard(liveSnapshots, overallWeeklyHighWins),
        isSample: false
      };
    } else {
      centerData = buildSampleCenter(liveSnapshots);
    }

    const mode = {
      showData: hasLiveData || centerData.isSample,
      isSample: centerData.isSample
    };

    renderMeta(centerData.snapshots, centerData.overallLeaderboard, mode);
    renderLeagueLeaders(centerData.snapshots, centerData.overallWeeklyHighWins, mode);
    renderOverallLeaderboard(centerData.overallLeaderboard, centerData.overallWeeklyHighWins, mode);
    renderWeeklyHighScores(centerData.weeklyHighRows, mode);
  } catch (error) {
    renderLoadFailure(error);
  }
}

document.getElementById("reloadCenterButton")?.addEventListener("click", () => {
  window.location.reload();
});

Array.from(document.querySelectorAll("[data-bbu-section]")).forEach(button => {
  button.addEventListener("click", () => {
    bestBallCenterState.selectedSection = text(button.dataset.bbuSection) === "power" ? "power" : "scoring";
    if (bestBallCenterState.selectedSection === "power") {
      window.history.replaceState(null, "", "#powerRankings");
    } else {
      window.history.replaceState(null, "", window.location.pathname + window.location.search);
    }
    updateBestBallSectionTabs({ scroll: true });
  });
});

renderPowerRankings();
updateBestBallSectionTabs();
loadCenter();

