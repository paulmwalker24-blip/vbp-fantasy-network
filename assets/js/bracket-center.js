const BRACKET_LEDGER_URL = "data/bracket-ledger.json";
const DEFAULT_GROUP_ID = "BRACKET-2026-1";
const DEFAULT_TEAMS_PER_LEAGUE = 12;
const SCOREBOARD_REFRESH_MS = 60000;
const DEMO_TEAM_SUFFIXES = [
  "Legion",
  "Outlaws",
  "Breakers",
  "Storm",
  "Voltage",
  "Signal",
  "Rush",
  "Nightfall",
  "Kings",
  "Union",
  "Rebels",
  "Rise"
];

const scoreboardState = {
  liveGroup: null,
  selectedLeagueRecordId: "",
  refreshTimer: null
};

function text(value) {
  return String(value ?? "").trim();
}

function toNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function getSearchGroupId() {
  const params = new URLSearchParams(window.location.search);
  return text(params.get("group")) || DEFAULT_GROUP_ID;
}

function getEntryKey(entry) {
  return [
    text(entry?.leagueRecordId),
    text(entry?.ownerId),
    text(entry?.rosterId)
  ].join("|");
}

function formatLeagueRecord(entry) {
  if (!entry) return "0-0";

  const wins = toNumber(entry.wins);
  const losses = toNumber(entry.losses);
  const ties = toNumber(entry.ties);

  if (ties > 0) {
    return `${wins}-${losses}-${ties}`;
  }

  return `${wins}-${losses}`;
}

function formatRecord(record) {
  const parts = text(record).split("-").map(part => part.trim()).filter(Boolean);
  if (parts.length >= 3 && parts[2] === "0") {
    return `${parts[0]}-${parts[1]}`;
  }
  return text(record);
}

function formatTimestamp(value) {
  const input = text(value);
  if (!input) return "Unknown";

  const parsed = new Date(input);
  if (Number.isNaN(parsed.getTime())) {
    return input;
  }

  return parsed.toLocaleString();
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

function getGroups(payload) {
  if (Array.isArray(payload?.groups)) {
    return payload.groups;
  }

  if (payload?.groups) {
    return [payload.groups];
  }

  return [];
}

function findGroup(payload, groupId) {
  return getGroups(payload).find(group => text(group?.groupId) === groupId) || null;
}

function getExpectedTeamCount(group) {
  const leagueCount = Array.isArray(group?.leagueRecordIds) ? group.leagueRecordIds.length : 0;
  return leagueCount * DEFAULT_TEAMS_PER_LEAGUE;
}

function getDemoPlayoffCounts(leagueCount) {
  if (leagueCount === 5) {
    return [7, 6, 7, 5, 7];
  }

  const counts = new Array(Math.max(leagueCount, 1)).fill(1);
  let remaining = 32 - counts.length;
  let index = 0;

  while (remaining > 0) {
    counts[index % counts.length] += 1;
    remaining -= 1;
    index += 1;
  }

  return counts;
}

function getLeagueDescriptors(group) {
  const snapshots = Array.isArray(group?.leagueSnapshots) ? group.leagueSnapshots : [];
  const namesById = new Map();

  snapshots.forEach(snapshot => {
    const leagueRecordId = text(snapshot?.leagueRecordId);
    if (!leagueRecordId) return;
    namesById.set(leagueRecordId, {
      leagueName: text(snapshot?.localLeagueName) || leagueRecordId,
      division: text(snapshot?.division)
    });
  });

  return (Array.isArray(group?.leagueRecordIds) ? group.leagueRecordIds : []).map((leagueRecordId, index) => {
    const resolvedLeagueRecordId = text(leagueRecordId);
    const snapshotInfo = namesById.get(resolvedLeagueRecordId) || {};

    return {
      leagueRecordId: resolvedLeagueRecordId,
      leagueName: snapshotInfo.leagueName || `Division ${index + 1}`,
      division: snapshotInfo.division || ""
    };
  });
}

function getDemoMetrics(rank, divisionIndex, slotIndex) {
  let wins = 1;
  let losses = 8;
  let ties = 0;

  if (rank <= 2) {
    wins = 8;
    losses = 1;
  } else if (rank <= 10) {
    wins = 7;
    losses = 2;
  } else if (rank <= 24) {
    wins = 6;
    losses = 3;
  } else if (rank <= 38) {
    wins = 5;
    losses = 4;
  } else if (rank <= 48) {
    wins = 4;
    losses = 5;
  } else if (rank <= 55) {
    wins = 3;
    losses = 6;
  } else if (rank <= 59) {
    wins = 2;
    losses = 7;
  }

  const pointsFor = Number((1188.42 - ((rank - 1) * 7.83) - (divisionIndex * 1.47) - (slotIndex * 0.31)).toFixed(2));

  return {
    wins,
    losses,
    ties,
    record: `${wins}-${losses}-${ties}`,
    pointsFor,
    pointsForDisplay: pointsFor.toFixed(2)
  };
}

function interleaveGroups(groups) {
  const queues = groups.map(group => [...group]);
  const merged = [];
  let hasItems = true;

  while (hasItems) {
    hasItems = false;

    queues.forEach(queue => {
      if (!queue.length) return;
      merged.push(queue.shift());
      hasItems = true;
    });
  }

  return merged;
}

function buildDemoGroup(group) {
  const descriptors = getLeagueDescriptors(group);
  const expectedTeamCount = getExpectedTeamCount(group) || 60;
  const teamsPerLeague = Math.max(Math.floor(expectedTeamCount / Math.max(descriptors.length, 1)), DEFAULT_TEAMS_PER_LEAGUE);
  const playoffCounts = getDemoPlayoffCounts(descriptors.length);

  const divisionTeams = descriptors.map((descriptor, divisionIndex) => {
    const teams = [];

    for (let slotIndex = 0; slotIndex < teamsPerLeague; slotIndex += 1) {
      const suffix = DEMO_TEAM_SUFFIXES[slotIndex % DEMO_TEAM_SUFFIXES.length];
      teams.push({
        leagueRecordId: descriptor.leagueRecordId,
        leagueName: descriptor.leagueName,
        division: descriptor.division,
        ownerId: `sample-${descriptor.leagueRecordId}-${slotIndex + 1}`,
        rosterId: slotIndex + 1,
        teamName: `${descriptor.leagueName} ${suffix}`,
        displayName: `${descriptor.leagueName}${slotIndex + 1}`,
        slotIndex,
        divisionIndex
      });
    }

    return teams;
  });

  const divisionWinners = divisionTeams.map(teams => teams[0]);
  const extraPlayoffTeams = interleaveGroups(
    divisionTeams.map((teams, divisionIndex) => teams.slice(1, playoffCounts[divisionIndex]))
  );
  const directQualifiers = extraPlayoffTeams.slice(0, 25);
  const wildCards = extraPlayoffTeams.slice(25, 27);
  const outTeams = interleaveGroups(
    divisionTeams.map((teams, divisionIndex) => teams.slice(playoffCounts[divisionIndex]))
  );

  const rankedTeams = [...divisionWinners, ...directQualifiers, ...wildCards, ...outTeams].map((team, index) => {
    const metrics = getDemoMetrics(index + 1, team.divisionIndex, team.slotIndex);

    return {
      rank: index + 1,
      teamName: team.teamName,
      displayName: team.displayName,
      leagueRecordId: team.leagueRecordId,
      leagueName: team.leagueName,
      division: team.division,
      record: metrics.record,
      wins: metrics.wins,
      losses: metrics.losses,
      ties: metrics.ties,
      pointsFor: metrics.pointsFor,
      pointsForDisplay: metrics.pointsForDisplay,
      ownerId: team.ownerId,
      rosterId: team.rosterId
    };
  });

  const rankedTeamByKey = new Map(
    rankedTeams.map(entry => [getEntryKey(entry), entry])
  );

  const seededDivisionWinners = divisionWinners.map((team, index) => ({
    seed: index + 1,
    seedType: "division-winner",
    team: rankedTeamByKey.get(getEntryKey(team))
  }));

  const seededDirectQualifiers = directQualifiers.map((team, index) => ({
    seed: index + 6,
    seedType: "direct-qualifier",
    team: rankedTeamByKey.get(getEntryKey(team))
  }));

  const seededWildCards = wildCards.map((team, index) => ({
    seed: index + 31,
    seedType: "wild-card",
    team: rankedTeamByKey.get(getEntryKey(team))
  }));

  return {
    ...group,
    isSample: true,
    notes: "Sample 60-team preview is currently shown because the live bracket group is still pre-draft, incomplete, or not yet showing meaningful live standings.",
    overallStandings: rankedTeams,
    divisionWinners: seededDivisionWinners,
    playoffField: [...seededDivisionWinners, ...seededDirectQualifiers, ...seededWildCards],
    leagueSnapshots: descriptors.map(descriptor => ({
      leagueRecordId: descriptor.leagueRecordId,
      localLeagueName: descriptor.leagueName,
      division: descriptor.division
    }))
  };
}

function hasMeaningfulStandingsData(group) {
  const standings = Array.isArray(group?.overallStandings) ? group.overallStandings : [];

  return standings.some(entry => {
    const recordParts = text(entry?.record)
      .split("-")
      .map(part => Number(part.trim()))
      .filter(value => Number.isFinite(value));

    const totalGames = recordParts.reduce((sum, value) => sum + value, 0);
    const pointsFor = toNumber(entry?.pointsFor);

    return totalGames > 0 || pointsFor > 0;
  });
}

function shouldUseDemoGroup(group) {
  const trackedTeams = Array.isArray(group?.overallStandings) ? group.overallStandings.length : 0;
  const expectedTeams = getExpectedTeamCount(group);
  const seasonDataReady = Boolean(group?.seasonDataReady);

  if (!seasonDataReady) {
    return true;
  }

  if (trackedTeams < expectedTeams) {
    return true;
  }

  return !hasMeaningfulStandingsData(group);
}

function computeDivisionCounts(group) {
  const countsByLeague = new Map();
  const leagueNamesById = new Map();

  const leagueRecordIds = Array.isArray(group?.leagueRecordIds) ? group.leagueRecordIds : [];
  const snapshots = Array.isArray(group?.leagueSnapshots) ? group.leagueSnapshots : [];
  const playoffField = Array.isArray(group?.playoffField) ? group.playoffField : [];

  snapshots.forEach(snapshot => {
    const leagueRecordId = text(snapshot?.leagueRecordId);
    if (!leagueRecordId) return;
    leagueNamesById.set(leagueRecordId, text(snapshot?.localLeagueName) || leagueRecordId);
  });

  leagueRecordIds.forEach(leagueRecordId => {
    countsByLeague.set(text(leagueRecordId), 0);
  });

  playoffField.forEach(entry => {
    const leagueRecordId = text(entry?.team?.leagueRecordId);
    if (!leagueRecordId) return;
    countsByLeague.set(leagueRecordId, (countsByLeague.get(leagueRecordId) || 0) + 1);
  });

  return leagueRecordIds.map(leagueRecordId => {
    const resolvedId = text(leagueRecordId);
    return {
      leagueRecordId: resolvedId,
      leagueName: leagueNamesById.get(resolvedId) || resolvedId,
      count: countsByLeague.get(resolvedId) || 0
    };
  });
}

function buildStatusMaps(group) {
  const divisionWinnerKeys = new Set();
  const playoffSeedByKey = new Map();

  const divisionWinners = Array.isArray(group?.divisionWinners) ? group.divisionWinners : [];
  const playoffField = Array.isArray(group?.playoffField) ? group.playoffField : [];

  divisionWinners.forEach(entry => {
    divisionWinnerKeys.add(getEntryKey(entry?.team));
  });

  playoffField.forEach(entry => {
    playoffSeedByKey.set(getEntryKey(entry?.team), Number(entry?.seed) || 0);
  });

  return { divisionWinnerKeys, playoffSeedByKey };
}

function buildTeamLookup(snapshot) {
  const map = new Map();
  const standings = Array.isArray(snapshot?.standings) ? snapshot.standings : [];

  standings.forEach(entry => {
    const rosterId = toNumber(entry?.rosterId);
    if (!rosterId) return;

    map.set(rosterId, {
      teamName: text(entry?.teamName) || text(entry?.displayName) || `Roster ${rosterId}`,
      record: formatLeagueRecord(entry)
    });
  });

  return map;
}

function getScoreboardWeekInfo(nflState) {
  const seasonType = text(nflState?.season_type || nflState?.seasonType).toLowerCase();
  const leg = toNumber(nflState?.leg || nflState?.week || nflState?.display_week);

  if (!leg) {
    return {
      label: "Week unavailable",
      week: 0,
      isActiveSeason: false
    };
  }

  const seasonLabel = seasonType === "post"
    ? "Playoffs"
    : seasonType === "regular"
    ? "Regular Season"
    : seasonType
      ? seasonType
      : "Season";

  return {
    label: `${seasonLabel} Week ${leg}`,
    week: leg,
    isActiveSeason: seasonType === "regular" || seasonType === "post"
  };
}

function groupMatchupEntries(matchups) {
  const groups = new Map();

  (Array.isArray(matchups) ? matchups : []).forEach(entry => {
    const rosterId = toNumber(entry?.roster_id);
    if (!rosterId) return;

    const matchupId = entry?.matchup_id;
    const key = matchupId === null || matchupId === undefined
      ? `solo-${rosterId}`
      : `matchup-${matchupId}`;

    if (!groups.has(key)) {
      groups.set(key, []);
    }

    groups.get(key).push(entry);
  });

  return Array.from(groups.entries())
    .sort((a, b) => String(a[0]).localeCompare(String(b[0]), undefined, { numeric: true }))
    .map(([, entries]) => entries.sort((left, right) => toNumber(left?.roster_id) - toNumber(right?.roster_id)));
}

function getMatchupStatusLabel(leftPoints, rightPoints, teamCount) {
  if (teamCount === 1) {
    return "Solo";
  }

  if (leftPoints === rightPoints) {
    return "Tied";
  }

  return "Live";
}

function createMatchupCard(snapshot, matchupEntries) {
  const teamLookup = buildTeamLookup(snapshot);
  const card = document.createElement("article");
  card.className = "format-center-matchup-card";

  const header = document.createElement("div");
  header.className = "format-center-matchup-header";

  const title = document.createElement("p");
  title.className = "format-center-matchup-title";
  title.textContent = matchupEntries.length > 1
    ? `Matchup ${text(matchupEntries[0]?.matchup_id)}`
    : "Single Team View";

  const firstPoints = toNumber(matchupEntries[0]?.points);
  const secondPoints = matchupEntries.length > 1 ? toNumber(matchupEntries[1]?.points) : 0;

  const status = document.createElement("span");
  status.className = "format-center-matchup-status";
  status.textContent = getMatchupStatusLabel(firstPoints, secondPoints, matchupEntries.length);

  header.append(title, status);

  const body = document.createElement("div");
  body.className = "format-center-matchup-body";

  const highestPoints = matchupEntries.reduce((max, entry) => Math.max(max, toNumber(entry?.points)), 0);

  matchupEntries.forEach(entry => {
    const rosterId = toNumber(entry?.roster_id);
    const points = toNumber(entry?.points).toFixed(2);
    const teamMeta = teamLookup.get(rosterId) || {
      teamName: `Roster ${rosterId}`,
      record: "0-0"
    };

    const teamRow = document.createElement("div");
    teamRow.className = `format-center-matchup-team${toNumber(entry?.points) === highestPoints && matchupEntries.length > 1 ? " is-leading" : matchupEntries.length > 1 ? " is-trailing" : ""}`;

    const teamCopy = document.createElement("div");
    const teamName = document.createElement("p");
    teamName.className = "format-center-matchup-name";
    teamName.textContent = teamMeta.teamName;
    const teamRecord = document.createElement("p");
    teamRecord.className = "format-center-matchup-record";
    teamRecord.textContent = teamMeta.record;
    teamCopy.append(teamName, teamRecord);

    const score = document.createElement("div");
    score.className = "format-center-matchup-score";
    score.textContent = points;

    teamRow.append(teamCopy, score);
    body.appendChild(teamRow);
  });

  card.append(header, body);
  return card;
}

function renderScoreboardTabs(snapshots) {
  const tabsContainer = document.getElementById("scoreboardTabs");
  tabsContainer.innerHTML = "";

  snapshots.forEach((snapshot, index) => {
    const leagueRecordId = text(snapshot?.leagueRecordId);
    const label = text(snapshot?.localLeagueName) || leagueRecordId;
    const button = document.createElement("button");
    button.type = "button";
    button.className = `format-center-tab${leagueRecordId === scoreboardState.selectedLeagueRecordId || (!scoreboardState.selectedLeagueRecordId && index === 0) ? " is-active" : ""}`;
    button.dataset.leagueRecordId = leagueRecordId;
    button.textContent = label;
    button.addEventListener("click", () => {
      scoreboardState.selectedLeagueRecordId = leagueRecordId;
      updateActiveScoreboardTab();
    });
    tabsContainer.appendChild(button);
  });

  if (!scoreboardState.selectedLeagueRecordId && snapshots.length) {
    scoreboardState.selectedLeagueRecordId = text(snapshots[0]?.leagueRecordId);
  }
}

function updateActiveScoreboardTab() {
  const tabs = Array.from(document.querySelectorAll(".format-center-tab"));
  const panels = Array.from(document.querySelectorAll(".format-center-scoreboard-panel"));

  tabs.forEach(tab => {
    tab.classList.toggle("is-active", tab.dataset.leagueRecordId === scoreboardState.selectedLeagueRecordId);
  });

  panels.forEach(panel => {
    panel.hidden = panel.dataset.leagueRecordId !== scoreboardState.selectedLeagueRecordId;
  });
}

function renderScoreboardsUnavailable(snapshots, message, weekLabel = "Scoreboard unavailable") {
  const panelsContainer = document.getElementById("scoreboardPanels");
  const summary = document.getElementById("scoreboardSummary");
  const week = document.getElementById("scoreboardWeekLabel");

  renderScoreboardTabs(snapshots);
  panelsContainer.innerHTML = "";
  summary.textContent = message;
  week.textContent = weekLabel;

  snapshots.forEach(snapshot => {
    const panel = document.createElement("section");
    panel.className = "format-center-scoreboard-panel";
    panel.dataset.leagueRecordId = text(snapshot?.leagueRecordId);
    panel.hidden = text(snapshot?.leagueRecordId) !== scoreboardState.selectedLeagueRecordId;

    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = `${text(snapshot?.localLeagueName) || text(snapshot?.leagueRecordId)} scoreboard is not available yet.`;

    panel.appendChild(empty);
    panelsContainer.appendChild(panel);
  });

  updateActiveScoreboardTab();
}

async function renderLiveScoreboards(group) {
  const snapshots = Array.isArray(group?.leagueSnapshots) ? group.leagueSnapshots : [];
  const summary = document.getElementById("scoreboardSummary");
  const weekLabel = document.getElementById("scoreboardWeekLabel");
  const panelsContainer = document.getElementById("scoreboardPanels");

  if (!snapshots.length) {
    renderScoreboardsUnavailable([], "No bracket leagues are configured for live scoreboards yet.");
    return;
  }

  const statuses = snapshots.map(snapshot => text(snapshot?.status).toLowerCase());
  const allPrelaunch = statuses.every(status => status === "pre_draft" || status === "drafting" || !status);

  if (allPrelaunch) {
    renderScoreboardsUnavailable(
      snapshots,
      "Live scoreboards will appear here once the bracket leagues enter the season and start posting weekly matchups.",
      "Season not active yet"
    );
    return;
  }

  const nflStateResponse = await fetch("https://api.sleeper.app/v1/state/nfl", { cache: "no-store" });
  if (!nflStateResponse.ok) {
    throw new Error(`Sleeper NFL state request failed with status ${nflStateResponse.status}`);
  }

  const nflState = await nflStateResponse.json();
  const weekInfo = getScoreboardWeekInfo(nflState);

  if (!weekInfo.isActiveSeason || !weekInfo.week) {
    renderScoreboardsUnavailable(
      snapshots,
      "Sleeper is not currently reporting an active regular-season or playoff week for live scoreboards.",
      weekInfo.label
    );
    return;
  }

  renderScoreboardTabs(snapshots);
  panelsContainer.innerHTML = "";
  summary.textContent = "Current-week matchup scores refresh from Sleeper while this page is open. Use the tabs to follow each division.";
  weekLabel.textContent = weekInfo.label;

  const matchupResults = await Promise.all(snapshots.map(async snapshot => {
    const sleeperLeagueId = text(snapshot?.sleeperLeagueId);
    if (!sleeperLeagueId) {
      return {
        leagueRecordId: text(snapshot?.leagueRecordId),
        snapshot,
        matchups: [],
        error: "Missing Sleeper league id."
      };
    }

    try {
      const response = await fetch(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/matchups/${encodeURIComponent(weekInfo.week)}`, { cache: "no-store" });
      if (!response.ok) {
        throw new Error(`Matchup request failed with status ${response.status}`);
      }

      return {
        leagueRecordId: text(snapshot?.leagueRecordId),
        snapshot,
        matchups: await response.json(),
        error: ""
      };
    } catch (error) {
      return {
        leagueRecordId: text(snapshot?.leagueRecordId),
        snapshot,
        matchups: [],
        error: error instanceof Error ? error.message : "Unable to load scoreboard."
      };
    }
  }));

  matchupResults.forEach(result => {
    const panel = document.createElement("section");
    panel.className = "format-center-scoreboard-panel";
    panel.dataset.leagueRecordId = result.leagueRecordId;
    panel.hidden = result.leagueRecordId !== scoreboardState.selectedLeagueRecordId;

    const meta = document.createElement("div");
    meta.className = "format-center-scoreboard-meta";

    const title = document.createElement("h3");
    title.textContent = `${text(result.snapshot?.localLeagueName) || result.leagueRecordId} Scoreboard`;

    const note = document.createElement("p");
    note.className = "format-center-scoreboard-note";
    note.textContent = result.error
      ? result.error
      : "Showing the current week's matchup totals for this division.";

    meta.append(title, note);
    panel.appendChild(meta);

    if (result.error) {
      const empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = "This division's scoreboard could not be loaded right now.";
      panel.appendChild(empty);
      panelsContainer.appendChild(panel);
      return;
    }

    const groupedMatchups = groupMatchupEntries(result.matchups);
    if (!groupedMatchups.length) {
      const empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = "No matchup data is available for this division yet.";
      panel.appendChild(empty);
      panelsContainer.appendChild(panel);
      return;
    }

    const grid = document.createElement("div");
    grid.className = "format-center-matchup-grid";
    groupedMatchups.forEach(matchupEntries => {
      grid.appendChild(createMatchupCard(result.snapshot, matchupEntries));
    });

    panel.appendChild(grid);
    panelsContainer.appendChild(panel);
  });

  updateActiveScoreboardTab();
}

function getStatusMeta(entry, statusMaps) {
  const key = getEntryKey(entry);

  if (statusMaps.divisionWinnerKeys.has(key)) {
    return { label: "Division Leader", className: "format-center-status is-leader" };
  }

  if (statusMaps.playoffSeedByKey.has(key)) {
    const seed = statusMaps.playoffSeedByKey.get(key);
    if (seed >= 31) {
      return { label: "Wild Card", className: "format-center-status is-wild-card" };
    }
    return { label: "In", className: "format-center-status is-in" };
  }

  return { label: "Out", className: "format-center-status is-out" };
}

function renderMeta(group) {
  const groupName = document.getElementById("centerGroupName");
  const lastUpdated = document.getElementById("centerLastUpdated");
  const trackedTeams = document.getElementById("centerTrackedTeams");
  const playoffFieldSize = document.getElementById("centerPlayoffFieldSize");
  const statusBanner = document.getElementById("centerStatusBanner");
  const title = document.getElementById("centerPageTitle");
  const subtitle = document.getElementById("centerPageSubtitle");

  const overallStandings = Array.isArray(group?.overallStandings) ? group.overallStandings : [];
  const playoffField = Array.isArray(group?.playoffField) ? group.playoffField : [];
  const targetPlayoffSize = Number(group?.rules?.directQualifiers || 30) + Number(group?.rules?.wildCards || 2);
  const label = text(group?.label) || text(group?.groupId) || DEFAULT_GROUP_ID;
  const seasonDataReady = Boolean(group?.seasonDataReady);
  const seedingReady = Boolean(group?.seedingReady);
  const statusText = text(group?.notes);

  title.textContent = "Bracket Center";
  subtitle.textContent = group?.isSample
    ? `Sample full-field preview for ${label} while live standings are still incomplete.`
    : `Public standings and playoff race snapshot for ${label}.`;
  groupName.textContent = label;
  lastUpdated.textContent = formatTimestamp(group?.lastSyncedAt);
  trackedTeams.textContent = `${overallStandings.length} tracked`;
  playoffFieldSize.textContent = `${playoffField.length} / ${targetPlayoffSize}`;

  if (statusText) {
    statusBanner.hidden = false;
    statusBanner.className = `format-center-banner${!group?.isSample && seasonDataReady && seedingReady ? " is-live" : " is-provisional"}`;
    statusBanner.textContent = statusText;
  } else {
    statusBanner.hidden = true;
  }
}

function renderDivisionCounts(group) {
  const container = document.getElementById("divisionCountsContainer");
  const counts = computeDivisionCounts(group);
  container.innerHTML = "";

  if (!counts.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No grouped bracket leagues are configured for this center yet.";
    container.appendChild(empty);
    return;
  }

  counts.forEach(entry => {
    const card = document.createElement("article");
    card.className = "format-center-division-card";

    const name = document.createElement("h3");
    name.textContent = entry.leagueName;

    const count = document.createElement("p");
    count.className = "format-center-division-count";
    count.textContent = `${entry.count} team${entry.count === 1 ? "" : "s"}`;

    card.append(name, count);
    container.appendChild(card);
  });
}

function renderStandings(group) {
  const body = document.getElementById("standingsTableBody");
  const standings = Array.isArray(group?.overallStandings) ? group.overallStandings : [];
  const statusMaps = buildStatusMaps(group);

  body.innerHTML = "";

  if (!standings.length) {
    body.appendChild(createEmptyState("No standings are available for this bracket group yet.", 6));
    return;
  }

  standings.forEach(entry => {
    const row = document.createElement("tr");
    const statusMeta = getStatusMeta(entry, statusMaps);

    const rank = document.createElement("td");
    rank.textContent = text(entry.rank);

    const team = document.createElement("td");
    const teamName = document.createElement("strong");
    teamName.textContent = text(entry.teamName) || text(entry.displayName) || "Unknown Team";
    team.appendChild(teamName);

    const division = document.createElement("td");
    division.textContent = text(entry.leagueName) || text(entry.leagueRecordId);

    const record = document.createElement("td");
    record.textContent = formatRecord(entry.record);

    const pf = document.createElement("td");
    pf.textContent = text(entry.pointsForDisplay);

    const status = document.createElement("td");
    const pill = document.createElement("span");
    pill.className = statusMeta.className;
    pill.textContent = statusMeta.label;
    status.appendChild(pill);

    row.append(rank, team, division, record, pf, status);
    body.appendChild(row);
  });
}

async function loadCenter() {
  const targetGroupId = getSearchGroupId();
  const divisionCountsContainer = document.getElementById("divisionCountsContainer");
  const standingsBody = document.getElementById("standingsTableBody");

  try {
    const response = await fetch(BRACKET_LEDGER_URL, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Bracket ledger request failed with status ${response.status}`);
    }

    const payload = await response.json();
    const liveGroup = findGroup(payload, targetGroupId);

    if (!liveGroup) {
      throw new Error(`Could not find bracket group ${targetGroupId}.`);
    }

    const group = shouldUseDemoGroup(liveGroup)
      ? buildDemoGroup(liveGroup)
      : liveGroup;

    renderMeta(group);
    renderDivisionCounts(group);
    renderStandings(group);
    scoreboardState.liveGroup = liveGroup;
    await renderLiveScoreboards(liveGroup);
  } catch (error) {
    console.error("Bracket center load failed:", error);

    divisionCountsContainer.innerHTML = "";
    const emptyDivisionState = document.createElement("div");
    emptyDivisionState.className = "empty-state";
    emptyDivisionState.textContent = "Unable to load bracket center data right now.";
    divisionCountsContainer.appendChild(emptyDivisionState);

    standingsBody.innerHTML = "";
    standingsBody.appendChild(createEmptyState("Unable to load standings right now.", 6));

    const banner = document.getElementById("centerStatusBanner");
    banner.hidden = false;
    banner.className = "format-center-banner is-provisional";
    banner.textContent = "The bracket center could not load the current data file.";

    renderScoreboardsUnavailable([], "Unable to load live scoreboards right now.");
  }
}

document.getElementById("reloadCenterButton")?.addEventListener("click", () => {
  window.location.reload();
});

document.getElementById("refreshScoresButton")?.addEventListener("click", async () => {
  if (!scoreboardState.liveGroup) {
    return;
  }

  await renderLiveScoreboards(scoreboardState.liveGroup);
});

if (scoreboardState.refreshTimer) {
  window.clearInterval(scoreboardState.refreshTimer);
}

scoreboardState.refreshTimer = window.setInterval(async () => {
  if (!scoreboardState.liveGroup) {
    return;
  }

  await renderLiveScoreboards(scoreboardState.liveGroup);
}, SCOREBOARD_REFRESH_MS);

loadCenter();
