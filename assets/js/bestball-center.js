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
    team: "DSnyder5",
    league: "BBU2",
    grades: { lineup: 96, depth: 94, bigWeeks: 94, scoringFit: 92 },
    summary: "Ranked first because the RBs are excellent, the WR group is deep enough to fill the flex spots, and Hurts gives the team a strong QB score most weeks.",
    core: "Jonathan Taylor, Saquon Barkley, Nico Collins, Ladd McConkey, George Pickens, Davante Adams, Jalen Hurts"
  },
  {
    rank: 2,
    team: "ThrowwUpTheX",
    league: "BBU1",
    grades: { lineup: 95, depth: 92, bigWeeks: 95, scoringFit: 89 },
    summary: "Very close to first. Chase, Saquon, Kyren, Waddle, and Evans give this roster a lot of weekly scoring power, and the two QBs give it good cover.",
    core: "Ja'Marr Chase, Saquon Barkley, Kyren Williams, Jaylen Waddle, Mike Evans, Jalen Hurts, Justin Herbert"
  },
  {
    rank: 3,
    team: "Adamgrifki",
    league: "BBU1",
    grades: { lineup: 91, depth: 91, bigWeeks: 90, scoringFit: 96 },
    summary: "Bowers is a real edge at TE, and the WR room is strong. The RB depth is also good enough for a league where rosters are locked after the draft.",
    core: "Jonathan Taylor, Amon-Ra St. Brown, Brock Bowers, Chris Olave, Marvin Harrison, Jameson Williams"
  },
  {
    rank: 4,
    team: "bryanb460",
    league: "BBU2",
    grades: { lineup: 91, depth: 88, bigWeeks: 92, scoringFit: 84 },
    summary: "This is one of the best WR rooms in the field. That matters because BBU starts three WRs and two flex spots every week.",
    core: "Justin Jefferson, Malik Nabers, A.J. Brown, DK Metcalf, James Cook"
  },
  {
    rank: 5,
    team: "gunnar21",
    league: "BBU1",
    grades: { lineup: 90, depth: 86, bigWeeks: 90, scoringFit: 91 },
    summary: "Bijan and Breece are a strong RB start, McBride helps at TE, and Lamar gives the roster a clear weekly advantage at QB.",
    core: "Bijan Robinson, Breece Hall, Trey McBride, Lamar Jackson, Ladd McConkey, Rome Odunze"
  },
  {
    rank: 6,
    team: "Cameron74",
    league: "BBU2",
    grades: { lineup: 88, depth: 84, bigWeeks: 88, scoringFit: 87 },
    summary: "The top players are strong and the three-QB setup should help. The main concern is whether the WR depth is enough over a full season.",
    core: "Bijan Robinson, Josh Jacobs, Drake London, Lamar Jackson, David Montgomery, Kyle Pitts, Justin Herbert"
  },
  {
    rank: 7,
    team: "mguzz",
    league: "BBU1",
    grades: { lineup: 86, depth: 89, bigWeeks: 86, scoringFit: 83 },
    summary: "This roster has useful depth at both RB and WR, which matters when there are no waivers. Burrow also gives it a strong weekly QB option.",
    core: "Puka Nacua, Nico Collins, Derrick Henry, Chase Brown, Joe Burrow, Zay Flowers, Jordan Addison"
  },
  {
    rank: 8,
    team: "swampraider",
    league: "BBU2",
    grades: { lineup: 86, depth: 83, bigWeeks: 89, scoringFit: 82 },
    summary: "Chase and Burrow can carry big weeks together. The RB group has upside, but it also carries more risk than some teams above it.",
    core: "Ja'Marr Chase, Kyren Williams, Chase Brown, Chris Olave, Joe Burrow, TreVeyon Henderson"
  },
  {
    rank: 9,
    team: "PasqTheGoat",
    league: "BBU2",
    grades: { lineup: 84, depth: 80, bigWeeks: 91, scoringFit: 88 },
    summary: "This team can have huge weeks because of CMC, Bowers, Daniels, Wilson, and Brian Thomas. The risk is that several key players have more uncertainty than the teams above.",
    core: "Christian McCaffrey, Brock Bowers, Garrett Wilson, Jayden Daniels, Brian Thomas"
  },
  {
    rank: 10,
    team: "jakeejk",
    league: "BBU2",
    grades: { lineup: 83, depth: 84, bigWeeks: 80, scoringFit: 92 },
    summary: "The WR and TE groups are very strong for this scoring format. QB is the biggest reason this team is not ranked higher.",
    core: "Ashton Jeanty, CeeDee Lamb, Trey McBride, Tee Higgins, DeVonta Smith, Emeka Egbuka"
  },
  {
    rank: 11,
    team: "jakeejk",
    league: "BBU1",
    grades: { lineup: 83, depth: 80, bigWeeks: 82, scoringFit: 88 },
    summary: "The WR group is excellent, especially in a three-WR format. The RB and QB groups are thinner than the teams above it.",
    core: "Justin Jefferson, Garrett Wilson, Tetairoa McMillan, Luther Burden, Emeka Egbuka"
  },
  {
    rank: 12,
    team: "OutlawReturns",
    league: "BBU2",
    grades: { lineup: 81, depth: 82, bigWeeks: 82, scoringFit: 87 },
    summary: "Amon-Ra gives this team a steady WR base, and the RBs can produce big weeks. The TE depth also helps because TEs get 0.75 per catch.",
    core: "De'Von Achane, Amon-Ra St. Brown, Breece Hall, Drake Maye, D'Andre Swift, Zay Flowers, Sam LaPorta"
  },
  {
    rank: 13,
    team: "RevDennis",
    league: "BBU2",
    grades: { lineup: 82, depth: 81, bigWeeks: 79, scoringFit: 83 },
    summary: "Allen and Puka are a strong starting point. The roster also has enough RB and TE cover to handle a season without pickups.",
    core: "Puka Nacua, Omarion Hampton, Josh Allen, Travis Etienne, DJ Moore, Rome Odunze"
  },
  {
    rank: 14,
    team: "jessegambo",
    league: "BBU1",
    grades: { lineup: 81, depth: 80, bigWeeks: 80, scoringFit: 82 },
    summary: "Gibbs and Jacobs give this team a strong RB base, and the WRs are good enough to keep the weekly score steady.",
    core: "Jahmyr Gibbs, Josh Jacobs, Drake London, Tee Higgins, Terry McLaurin, Caleb Williams"
  },
  {
    rank: 15,
    team: "VanillaWafer",
    league: "BBU1",
    grades: { lineup: 80, depth: 76, bigWeeks: 86, scoringFit: 81 },
    summary: "CMC, Nabers, DK, and Mahomes give this roster real upside. The lower rank is mostly because there is more injury and role risk here.",
    core: "Christian McCaffrey, Malik Nabers, DJ Moore, DK Metcalf, Patrick Mahomes"
  },
  {
    rank: 16,
    team: "Flagg Planters",
    league: "BBU2",
    grades: { lineup: 79, depth: 78, bigWeeks: 82, scoringFit: 79 },
    summary: "This team is very RB-heavy and has two good QB options. It can win big weeks, but the WR room is thinner than most teams above it.",
    core: "Jahmyr Gibbs, Bucky Irving, Derrick Henry, Tetairoa McMillan, Patrick Mahomes, Mark Andrews"
  },
  {
    rank: 17,
    team: "kj0116",
    league: "BBU1",
    grades: { lineup: 80, depth: 75, bigWeeks: 79, scoringFit: 80 },
    summary: "Lamb, A.J. Brown, Allen, and LaPorta are excellent. The concern is that the bench does not add as much weekly scoring help as the teams above it.",
    core: "CeeDee Lamb, A.J. Brown, Josh Allen, Kenneth Walker, Sam LaPorta"
  },
  {
    rank: 18,
    team: "SnoopDerek",
    league: "BBU2",
    grades: { lineup: 77, depth: 76, bigWeeks: 79, scoringFit: 77 },
    summary: "The WR and QB groups can score well. The RB room needs to hit because there are no waivers or trades to fix it later.",
    core: "Jaxon Smith-Njigba, Kenneth Walker, Rashee Rice, Jaylen Waddle, Caleb Williams, Bo Nix"
  },
  {
    rank: 19,
    team: "HopscotchDaisy",
    league: "BBU1",
    grades: { lineup: 76, depth: 77, bigWeeks: 75, scoringFit: 80 },
    summary: "The RB and TE rooms are deep. The issue is that the WR and QB groups look less likely to keep up in total points.",
    core: "Ashton Jeanty, De'Von Achane, Bucky Irving, Travis Etienne, Davante Adams, DeVonta Smith"
  },
  {
    rank: 20,
    team: "2GunzTanner",
    league: "BBU1",
    grades: { lineup: 75, depth: 75, bigWeeks: 76, scoringFit: 78 },
    summary: "There is plenty to like with Maye, Daniels, Kittle, JSN, and Hampton. The rank is lower because more of the roster still has to prove it.",
    core: "Jaxon Smith-Njigba, Omarion Hampton, Rashee Rice, TreVeyon Henderson, Drake Maye, Jayden Daniels, George Kittle"
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
    const score = getBbuPowerScore(entry.grades);
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
    breakdown.textContent = `Score: ${score.toFixed(1)} = lineup ${entry.grades.lineup} x 45%, depth ${entry.grades.depth} x 30%, big-week players ${entry.grades.bigWeeks} x 15%, scoring fit ${entry.grades.scoringFit} x 10%.`;

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
