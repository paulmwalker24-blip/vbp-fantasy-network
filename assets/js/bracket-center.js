const CENTER_VIEW_CONFIG = {
  redraft: {
    key: "redraft",
    buttonLabel: "Redraft Bracket",
    label: "Bracket Redraft",
    pageTitle: "Bracket Center",
    summaryTitle: "Live Redraft Bracket Center",
    summaryCopy: "This page is the public standings layer for the redraft bracket format. It stays separate from the homepage so the hub can stay focused on recruiting, league discovery, and constitutions.",
    subtitle: "Public standings and playoff race snapshot for the VBP Bracket Redraft group.",
    sampleSubtitlePrefix: "Sample full-field preview for",
    constitutionPage: "bracket-constitution.html",
    constitutionLabel: "Bracket Redraft Constitution",
    ledgerUrl: "data/bracket-ledger.json",
    defaultGroupId: "BRACKET-2026-1",
    divisionHeading: "Division Playoff Counts",
    divisionEmptyMessage: "No grouped redraft bracket leagues are configured for this center yet.",
    standingsEmptyMessage: "No standings are available for this redraft bracket group yet.",
    scoreboardsIntro: "Use the division tabs to follow live or current-week matchup scores across the grouped redraft bracket leagues.",
    scoreboardsWaiting: "Live scoreboards will appear here once the redraft bracket leagues enter the season and start posting weekly matchups.",
    scoreboardsMissing: "No redraft bracket leagues are configured for live scoreboards yet.",
    loadFailure: "The redraft bracket center could not load the current data file.",
    unavailableDivisionMessage: "Unable to load redraft bracket center data right now.",
    unavailableStandingsMessage: "Unable to load redraft bracket standings right now.",
    unavailableScoreboardsMessage: "Unable to load live redraft bracket scoreboards right now."
  },
  dynasty: {
    key: "dynasty",
    buttonLabel: "Dynasty Bracket",
    label: "Dynasty Bracket",
    pageTitle: "Bracket Center",
    summaryTitle: "Live Dynasty Bracket Center",
    summaryCopy: "This page is the public standings layer for the dynasty bracket format. It is built to mirror the redraft bracket center once the four dynasty divisions are live and publishing weekly data.",
    subtitle: "Public standings and playoff race snapshot for the VBP Dynasty Bracket group.",
    sampleSubtitlePrefix: "Sample dynasty-field preview for",
    constitutionPage: "dynasty-bracket-constitution.html",
    constitutionLabel: "Dynasty Bracket Constitution",
    ledgerUrl: "data/dynasty-bracket-ledger.json",
    defaultGroupId: "DYNASTY-BRACKET-2026-1",
    divisionHeading: "Division Playoff Counts",
    divisionEmptyMessage: "No grouped dynasty bracket leagues are configured for this center yet.",
    standingsEmptyMessage: "No standings are available for this dynasty bracket group yet.",
    scoreboardsIntro: "Use the division tabs to follow live or current-week matchup scores across the grouped dynasty bracket leagues.",
    scoreboardsWaiting: "Live scoreboards will appear here once the dynasty bracket leagues enter the season and start posting weekly matchups.",
    scoreboardsMissing: "No dynasty bracket leagues are configured for live scoreboards yet.",
    loadFailure: "The dynasty bracket center could not load the current data file.",
    unavailableDivisionMessage: "Unable to load dynasty bracket center data right now.",
    unavailableStandingsMessage: "Unable to load dynasty bracket standings right now.",
    unavailableScoreboardsMessage: "Unable to load live dynasty bracket scoreboards right now."
  }
};
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
  centerView: CENTER_VIEW_CONFIG.redraft,
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

function getCenterView() {
  const params = new URLSearchParams(window.location.search);
  const requestedView = text(params.get("view")).toLowerCase();
  return CENTER_VIEW_CONFIG[requestedView] || CENTER_VIEW_CONFIG.redraft;
}

function getSearchGroupId(centerView) {
  const params = new URLSearchParams(window.location.search);
  return text(params.get("group")) || centerView.defaultGroupId;
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

function getGroupLeagueCount(group) {
  const leagueRecordIds = Array.isArray(group?.leagueRecordIds) ? group.leagueRecordIds.filter(Boolean) : [];
  if (leagueRecordIds.length) {
    return leagueRecordIds.length;
  }

  const snapshots = Array.isArray(group?.leagueSnapshots) ? group.leagueSnapshots.filter(Boolean) : [];
  if (snapshots.length) {
    return snapshots.length;
  }

  return toNumber(group?.sampleLeagueCount);
}

function getExpectedTeamCount(group) {
  const leagueCount = getGroupLeagueCount(group);
  const teamsPerLeague = Math.max(toNumber(group?.teamsPerLeague), DEFAULT_TEAMS_PER_LEAGUE);
  return leagueCount * teamsPerLeague;
}

function getTargetPlayoffFieldSize(group) {
  return Math.max(
    toNumber(group?.rules?.directQualifiers) + toNumber(group?.rules?.wildCards),
    toNumber(group?.rules?.divisionWinners)
  );
}

function getDemoPlayoffCounts(group) {
  const leagueCount = Math.max(getGroupLeagueCount(group), 1);
  const counts = new Array(leagueCount).fill(1);
  let remaining = Math.max(getTargetPlayoffFieldSize(group) - leagueCount, 0);
  let index = 0;

  while (remaining > 0) {
    counts[index % counts.length] += 1;
    remaining -= 1;
    index += 1;
  }

  return counts;
}

function getLeagueDescriptors(group) {
  const sampleDivisions = Array.isArray(group?.sampleDivisions) ? group.sampleDivisions : [];
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

  const leagueRecordIds = Array.isArray(group?.leagueRecordIds) ? group.leagueRecordIds : [];
  if (leagueRecordIds.length) {
    return leagueRecordIds.map((leagueRecordId, index) => {
      const resolvedLeagueRecordId = text(leagueRecordId);
      const snapshotInfo = namesById.get(resolvedLeagueRecordId) || {};

      return {
        leagueRecordId: resolvedLeagueRecordId,
        leagueName: snapshotInfo.leagueName || `Division ${index + 1}`,
        division: snapshotInfo.division || ""
      };
    });
  }

  if (snapshots.length) {
    return snapshots.map((snapshot, index) => ({
      leagueRecordId: text(snapshot?.leagueRecordId) || `SAMPLE${index + 1}`,
      leagueName: text(snapshot?.localLeagueName) || `Division ${index + 1}`,
      division: text(snapshot?.division)
    }));
  }

  return sampleDivisions.map((entry, index) => ({
    leagueRecordId: text(entry?.leagueRecordId) || `SAMPLE${index + 1}`,
    leagueName: text(entry?.leagueName) || `Division ${index + 1}`,
    division: text(entry?.division)
  }));
}

function getDemoMetrics(rank, divisionIndex, slotIndex, totalTeams) {
  const percentile = totalTeams > 1 ? (rank - 1) / (totalTeams - 1) : 0;
  let wins = 1;
  let losses = 8;
  let ties = 0;

  if (percentile <= 0.08) {
    wins = 8;
    losses = 1;
  } else if (percentile <= 0.2) {
    wins = 7;
    losses = 2;
  } else if (percentile <= 0.45) {
    wins = 6;
    losses = 3;
  } else if (percentile <= 0.72) {
    wins = 5;
    losses = 4;
  } else if (percentile <= 0.88) {
    wins = 4;
    losses = 5;
  } else if (percentile <= 0.96) {
    wins = 3;
    losses = 6;
  } else {
    wins = 2;
    losses = 7;
  }

  const pointsForBase = totalTeams > 50 ? 1188.42 : 1318.42;
  const pointsForStep = totalTeams > 50 ? 7.83 : 9.12;
  const pointsFor = Number((pointsForBase - ((rank - 1) * pointsForStep) - (divisionIndex * 1.47) - (slotIndex * 0.31)).toFixed(2));

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
  const expectedTeamCount = getExpectedTeamCount(group) || (descriptors.length * DEFAULT_TEAMS_PER_LEAGUE);
  const teamsPerLeague = Math.max(Math.floor(expectedTeamCount / Math.max(descriptors.length, 1)), DEFAULT_TEAMS_PER_LEAGUE);
  const playoffCounts = getDemoPlayoffCounts(group);
  const targetPlayoffFieldSize = getTargetPlayoffFieldSize(group);
  const divisionWinnerSeedCount = Math.min(Math.max(toNumber(group?.rules?.divisionWinners), descriptors.length), descriptors.length);
  const wildCardCount = Math.max(toNumber(group?.rules?.wildCards), 0);
  const directQualifierCount = Math.max(targetPlayoffFieldSize - divisionWinnerSeedCount - wildCardCount, 0);

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

  const divisionWinners = divisionTeams.map(teams => teams[0]).slice(0, divisionWinnerSeedCount);
  const extraPlayoffTeams = interleaveGroups(
    divisionTeams.map((teams, divisionIndex) => teams.slice(1, playoffCounts[divisionIndex]))
  );
  const directQualifiers = extraPlayoffTeams.slice(0, directQualifierCount);
  const wildCards = extraPlayoffTeams.slice(directQualifierCount, directQualifierCount + wildCardCount);
  const outTeams = interleaveGroups(
    divisionTeams.map((teams, divisionIndex) => teams.slice(playoffCounts[divisionIndex]))
  );

  const rankedTeams = [...divisionWinners, ...directQualifiers, ...wildCards, ...outTeams].map((team, index) => {
    const metrics = getDemoMetrics(index + 1, team.divisionIndex, team.slotIndex, expectedTeamCount);

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
    seed: divisionWinnerSeedCount + index + 1,
    seedType: "direct-qualifier",
    team: rankedTeamByKey.get(getEntryKey(team))
  }));

  const seededWildCards = wildCards.map((team, index) => ({
    seed: divisionWinnerSeedCount + directQualifierCount + index + 1,
    seedType: "wild-card",
    team: rankedTeamByKey.get(getEntryKey(team))
  }));

  return {
    ...group,
    isSample: true,
    notes: `${scoreboardState.centerView.label} sample preview is currently shown because the live grouped standings are still pre-draft, incomplete, or not yet showing meaningful data.`,
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
  const descriptorIds = getLeagueDescriptors(group).map(entry => text(entry.leagueRecordId)).filter(Boolean);
  const resolvedLeagueIds = leagueRecordIds.length ? leagueRecordIds : descriptorIds;

  snapshots.forEach(snapshot => {
    const leagueRecordId = text(snapshot?.leagueRecordId);
    if (!leagueRecordId) return;
    leagueNamesById.set(leagueRecordId, text(snapshot?.localLeagueName) || leagueRecordId);
  });

  resolvedLeagueIds.forEach(leagueRecordId => {
    countsByLeague.set(text(leagueRecordId), 0);
  });

  playoffField.forEach(entry => {
    const leagueRecordId = text(entry?.team?.leagueRecordId);
    if (!leagueRecordId) return;
    countsByLeague.set(leagueRecordId, (countsByLeague.get(leagueRecordId) || 0) + 1);
  });

  return resolvedLeagueIds.map(leagueRecordId => {
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
  const centerView = scoreboardState.centerView;
  const snapshots = Array.isArray(group?.leagueSnapshots) ? group.leagueSnapshots : [];
  const summary = document.getElementById("scoreboardSummary");
  const weekLabel = document.getElementById("scoreboardWeekLabel");
  const panelsContainer = document.getElementById("scoreboardPanels");

  if (!snapshots.length) {
    renderScoreboardsUnavailable([], centerView.scoreboardsMissing);
    return;
  }

  const statuses = snapshots.map(snapshot => text(snapshot?.status).toLowerCase());
  const allPrelaunch = statuses.every(status => status === "pre_draft" || status === "drafting" || !status);

  if (allPrelaunch) {
    renderScoreboardsUnavailable(
      snapshots,
      centerView.scoreboardsWaiting,
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
  summary.textContent = `Current-week matchup scores refresh from Sleeper while this page is open. Use the tabs to follow each ${centerView.key === "dynasty" ? "dynasty division" : "division"}.`;
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
  const divisionWinnerCount = Math.max(toNumber(scoreboardState.liveGroup?.rules?.divisionWinners), 0);
  const directQualifierTarget = Math.max(toNumber(scoreboardState.liveGroup?.rules?.directQualifiers), divisionWinnerCount);

  if (statusMaps.divisionWinnerKeys.has(key)) {
    return { label: "Division Leader", className: "format-center-status is-leader" };
  }

  if (statusMaps.playoffSeedByKey.has(key)) {
    const seed = statusMaps.playoffSeedByKey.get(key);
    if (seed > directQualifierTarget) {
      return { label: "Wild Card", className: "format-center-status is-wild-card" };
    }
    return { label: "In", className: "format-center-status is-in" };
  }

  return { label: "Out", className: "format-center-status is-out" };
}

function renderMeta(group) {
  const centerView = scoreboardState.centerView;
  const groupName = document.getElementById("centerGroupName");
  const lastUpdated = document.getElementById("centerLastUpdated");
  const trackedTeams = document.getElementById("centerTrackedTeams");
  const playoffFieldSize = document.getElementById("centerPlayoffFieldSize");
  const statusBanner = document.getElementById("centerStatusBanner");
  const title = document.getElementById("centerPageTitle");
  const subtitle = document.getElementById("centerPageSubtitle");
  const summaryTitle = document.getElementById("centerSummaryTitle");
  const summaryCopy = document.getElementById("centerSummaryCopy");
  const constitutionLink = document.getElementById("centerConstitutionLink");
  const topConstitutionLink = document.getElementById("centerTopConstitutionLink");
  const sectionHeaders = Array.from(document.querySelectorAll(".constitution-section-header h2"));
  const scoreboardSummary = document.getElementById("scoreboardSummary");

  const overallStandings = Array.isArray(group?.overallStandings) ? group.overallStandings : [];
  const playoffField = Array.isArray(group?.playoffField) ? group.playoffField : [];
  const targetPlayoffSize = getTargetPlayoffFieldSize(group);
  const label = text(group?.label) || text(group?.groupId) || centerView.defaultGroupId;
  const seasonDataReady = Boolean(group?.seasonDataReady);
  const seedingReady = Boolean(group?.seedingReady);
  const statusText = text(group?.notes);

  title.textContent = centerView.pageTitle;
  subtitle.textContent = group?.isSample
    ? `${centerView.sampleSubtitlePrefix} ${label} while live standings are still incomplete.`
    : `Public standings and playoff race snapshot for ${label}.`;
  summaryTitle.textContent = centerView.summaryTitle;
  summaryCopy.textContent = centerView.summaryCopy;
  constitutionLink.href = centerView.constitutionPage;
  constitutionLink.textContent = "View Constitution";
  if (topConstitutionLink) {
    topConstitutionLink.href = centerView.constitutionPage;
    topConstitutionLink.textContent = "View Constitution";
  }
  scoreboardSummary.textContent = centerView.scoreboardsIntro;
  groupName.textContent = label;
  lastUpdated.textContent = formatTimestamp(group?.lastSyncedAt);
  trackedTeams.textContent = `${overallStandings.length} tracked`;
  playoffFieldSize.textContent = `${playoffField.length} / ${targetPlayoffSize}`;

  if (sectionHeaders.length >= 3) {
    sectionHeaders[0].textContent = centerView.divisionHeading;
    sectionHeaders[1].textContent = "Live League Scoreboards";
    sectionHeaders[2].textContent = "Full Combined Standings";
  }

  if (statusText) {
    statusBanner.hidden = false;
    statusBanner.className = `format-center-banner${!group?.isSample && seasonDataReady && seedingReady ? " is-live" : " is-provisional"}`;
    statusBanner.textContent = statusText;
  } else {
    statusBanner.hidden = true;
  }
}

function renderDivisionCounts(group) {
  const centerView = scoreboardState.centerView;
  const container = document.getElementById("divisionCountsContainer");
  const counts = computeDivisionCounts(group);
  container.innerHTML = "";

  if (!counts.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = centerView.divisionEmptyMessage;
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
  const centerView = scoreboardState.centerView;
  const body = document.getElementById("standingsTableBody");
  const standings = Array.isArray(group?.overallStandings) ? group.overallStandings : [];
  const statusMaps = buildStatusMaps(group);

  body.innerHTML = "";

  if (!standings.length) {
    body.appendChild(createEmptyState(centerView.standingsEmptyMessage, 6));
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

function updateCenterViewSwitcher() {
  const centerView = scoreboardState.centerView;
  const buttons = Array.from(document.querySelectorAll("[data-center-view]"));

  buttons.forEach(button => {
    const targetView = text(button.dataset.centerView).toLowerCase();
    button.classList.toggle("is-active", targetView === centerView.key);
  });
}

async function loadCenter() {
  const centerView = getCenterView();
  const targetGroupId = getSearchGroupId(centerView);
  const divisionCountsContainer = document.getElementById("divisionCountsContainer");
  const standingsBody = document.getElementById("standingsTableBody");

  scoreboardState.centerView = centerView;
  scoreboardState.liveGroup = null;
  scoreboardState.selectedLeagueRecordId = "";
  updateCenterViewSwitcher();

  try {
    const response = await fetch(centerView.ledgerUrl, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`${centerView.label} ledger request failed with status ${response.status}`);
    }

    const payload = await response.json();
    const liveGroup = findGroup(payload, targetGroupId);

    if (!liveGroup) {
      throw new Error(`Could not find ${centerView.label} group ${targetGroupId}.`);
    }

    const group = shouldUseDemoGroup(liveGroup)
      ? buildDemoGroup(liveGroup)
      : liveGroup;

    scoreboardState.liveGroup = liveGroup;
    renderMeta(group);
    renderDivisionCounts(group);
    renderStandings(group);
    await renderLiveScoreboards(liveGroup);
  } catch (error) {
    console.error("Bracket center load failed:", error);

    divisionCountsContainer.innerHTML = "";
    const emptyDivisionState = document.createElement("div");
    emptyDivisionState.className = "empty-state";
    emptyDivisionState.textContent = centerView.unavailableDivisionMessage;
    divisionCountsContainer.appendChild(emptyDivisionState);

    standingsBody.innerHTML = "";
    standingsBody.appendChild(createEmptyState(centerView.unavailableStandingsMessage, 6));

    const banner = document.getElementById("centerStatusBanner");
    banner.hidden = false;
    banner.className = "format-center-banner is-provisional";
    banner.textContent = centerView.loadFailure;

    renderScoreboardsUnavailable([], centerView.unavailableScoreboardsMessage);
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
