const BRACKET_HUB_URL = "https://sleeper.com/i/V9GRwXkB7aGeM";

const CENTER_VIEW_CONFIG = {
  redraft: {
    key: "redraft",
    buttonLabel: "Redraft Bracket",
    label: "Bracket Redraft",
    pageTitle: "Bracket Center",
    summaryTitle: "Live Redraft Bracket Center",
    summaryCopy: "This page acts as both the public home for the redraft bracket format and the standings layer once the grouped leagues are live.",
    subtitle: "Public standings and playoff race snapshot for the VBP Bracket Redraft group.",
    sampleSubtitlePrefix: "Sample full-field preview for",
    hubTitle: "Join the Bracket Hub First",
    hubCopy: "Use the central Sleeper hub to get the redraft bracket format details first. That makes it easier to route new owners into the fuller open rooms instead of sending them straight into low-fill divisions that lose momentum.",
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
    tradeTrackerIntro: "Accepted trades from every configured redraft bracket division are merged here so owners can follow the market across the full format.",
    tradeTrackerMissing: "No redraft bracket leagues are configured for trade tracking yet.",
    tradeTrackerEmpty: "No accepted redraft bracket trades have been reported by Sleeper yet.",
    loadFailure: "The redraft bracket center could not load the current data file.",
    unavailableDivisionMessage: "Unable to load redraft bracket center data right now.",
    unavailableStandingsMessage: "Unable to load redraft bracket standings right now.",
    unavailableScoreboardsMessage: "Unable to load live redraft bracket scoreboards right now.",
    unavailableTradeTrackerMessage: "Unable to load redraft bracket trades right now."
  },
  dynasty: {
    key: "dynasty",
    buttonLabel: "Dynasty Bracket",
    label: "Dynasty Bracket",
    pageTitle: "Bracket Center",
    summaryTitle: "Live Dynasty Bracket Center",
    summaryCopy: "This page acts as the public home for the dynasty bracket format, with a central intake path now and standings support as the divisions go live.",
    subtitle: "Public standings and playoff race snapshot for the VBP Dynasty Bracket group.",
    sampleSubtitlePrefix: "Sample dynasty-field preview for",
    hubTitle: "Use the Central Dynasty Bracket Hub",
    hubCopy: "Start in the shared Sleeper hub so interested dynasty owners can read the format, ask questions, and then get pointed into the healthiest open division instead of scattering across empty rooms too early.",
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
    tradeTrackerIntro: "Accepted trades from every configured dynasty bracket division are merged here so owners can follow the startup and in-season market across the full format.",
    tradeTrackerMissing: "No dynasty bracket leagues are configured for trade tracking yet.",
    tradeTrackerEmpty: "No accepted dynasty bracket trades have been reported by Sleeper yet.",
    loadFailure: "The dynasty bracket center could not load the current data file.",
    unavailableDivisionMessage: "Unable to load dynasty bracket center data right now.",
    unavailableStandingsMessage: "Unable to load dynasty bracket standings right now.",
    unavailableScoreboardsMessage: "Unable to load live dynasty bracket scoreboards right now.",
    unavailableTradeTrackerMessage: "Unable to load dynasty bracket trades right now."
  }
};
const DEFAULT_TEAMS_PER_LEAGUE = 12;
const SCOREBOARD_REFRESH_MS = 60000;
const TRADE_TRACKER_WEEKS = Array.from({ length: 18 }, (_, index) => index + 1);
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
  selectedSection: "standings",
  selectedLeagueRecordId: "",
  refreshTimer: null
};

let sleeperPlayersPromise = null;

const REDRAFT_DIVISION_IMAGE_BY_NAME = {
  titan: "assets/images/redraft-bracket-titan.png",
  apex: "assets/images/redraft-bracket-apex.png",
  iron: "assets/images/redraft-bracket-iron.png",
  vanguard: "assets/images/redraft-bracket-vanguard.png",
  dominion: "assets/images/redraft-bracket-dominion.png"
};

const DYNASTY_DIVISION_IMAGE_BY_NAME = {
  foundry: "assets/images/dynasty-bracket-foundry.png",
  forge: "assets/images/dynasty-bracket-forge.png",
  empire: "assets/images/dynasty-bracket-empire.png",
  legacy: "assets/images/dynasty-bracket-legacy.png"
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

function getCenterSection() {
  const params = new URLSearchParams(window.location.search);
  const requestedSection = text(params.get("tab")).toLowerCase();
  if (requestedSection === "bracket" || requestedSection === "trades") {
    return requestedSection;
  }
  return "standings";
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

function getRosterTeamLookup(snapshot) {
  const standings = Array.isArray(snapshot?.standings) ? snapshot.standings : [];
  const lookup = snapshot?._tradeTeamLookup instanceof Map
    ? new Map(snapshot._tradeTeamLookup)
    : new Map();

  standings.forEach(entry => {
    const rosterId = toNumber(entry?.rosterId);
    if (!rosterId) return;

    lookup.set(rosterId, text(entry?.teamName) || text(entry?.displayName) || `Roster ${rosterId}`);
  });

  return lookup;
}

function getDivisionImageSrc(leagueName) {
  const normalizedName = text(leagueName).toLowerCase();
  const imageMap = scoreboardState.centerView.key === "dynasty"
    ? DYNASTY_DIVISION_IMAGE_BY_NAME
    : REDRAFT_DIVISION_IMAGE_BY_NAME;

  return imageMap[normalizedName] || "";
}

async function hydrateTradeTeamLookup(snapshot) {
  const sleeperLeagueId = text(snapshot?.sleeperLeagueId);
  if (!sleeperLeagueId || snapshot?._tradeTeamLookup instanceof Map) {
    return;
  }

  try {
    const [usersResponse, rostersResponse] = await Promise.all([
      fetch(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/users`, { cache: "no-store" }),
      fetch(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/rosters`, { cache: "no-store" })
    ]);

    if (!usersResponse.ok || !rostersResponse.ok) {
      throw new Error("Sleeper users or rosters request failed.");
    }

    const users = await usersResponse.json();
    const rosters = await rostersResponse.json();
    const usersById = new Map((Array.isArray(users) ? users : []).map(user => [text(user?.user_id), user]));
    const lookup = new Map();

    (Array.isArray(rosters) ? rosters : []).forEach(roster => {
      const rosterId = toNumber(roster?.roster_id);
      const ownerId = text(roster?.owner_id);
      const user = usersById.get(ownerId);
      const teamName = text(user?.metadata?.team_name) || text(user?.display_name) || text(user?.username);

      if (rosterId && teamName) {
        lookup.set(rosterId, teamName);
      }
    });

    snapshot._tradeTeamLookup = lookup;
  } catch (error) {
    console.warn(`Trade tracker team lookup failed for ${sleeperLeagueId}:`, error);
    snapshot._tradeTeamLookup = new Map();
  }
}

function formatTradeDate(value) {
  const timestamp = toNumber(value);
  if (!timestamp) return "Unknown";

  const parsed = new Date(timestamp);
  if (Number.isNaN(parsed.getTime())) return "Unknown";

  return parsed.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric"
  });
}

function getPlayerDisplayName(playerId, players) {
  const id = text(playerId);
  if (!id) return "Unknown player";

  const player = players?.[id];
  if (!player) return `Player ${id}`;

  return text(player.full_name)
    || [text(player.first_name), text(player.last_name)].filter(Boolean).join(" ")
    || text(player.search_full_name)
    || `Player ${id}`;
}

function formatDraftPick(pick) {
  const season = text(pick?.season) || "Future";
  const round = text(pick?.round);
  const originalRosterId = toNumber(pick?.roster_id);
  const roundLabel = round ? `Round ${round}` : "Pick";
  const originalLabel = originalRosterId ? `, original roster ${originalRosterId}` : "";

  return `${season} ${roundLabel}${originalLabel}`;
}

async function getSleeperPlayers() {
  if (!sleeperPlayersPromise) {
    sleeperPlayersPromise = fetch("https://api.sleeper.app/v1/players/nfl", { cache: "force-cache" })
      .then(response => {
        if (!response.ok) {
          throw new Error(`Sleeper players request failed with status ${response.status}`);
        }
        return response.json();
      })
      .catch(error => {
        console.warn("Sleeper players load failed:", error);
        return {};
      });
  }

  return sleeperPlayersPromise;
}

function getTransactionAssetLines(transaction, snapshot, players) {
  if (Array.isArray(transaction?.sampleLines)) {
    return transaction.sampleLines;
  }

  const rosterIds = Array.isArray(transaction?.roster_ids) ? transaction.roster_ids.map(toNumber).filter(Boolean) : [];
  const teamLookup = getRosterTeamLookup(snapshot);
  const assetsByRoster = new Map(rosterIds.map(rosterId => [rosterId, []]));
  const adds = transaction?.adds && typeof transaction.adds === "object" ? transaction.adds : {};
  const draftPicks = Array.isArray(transaction?.draft_picks) ? transaction.draft_picks : [];

  Object.entries(adds).forEach(([playerId, rosterIdValue]) => {
    const rosterId = toNumber(rosterIdValue);
    if (!rosterId) return;
    if (!assetsByRoster.has(rosterId)) {
      assetsByRoster.set(rosterId, []);
    }
    assetsByRoster.get(rosterId).push(getPlayerDisplayName(playerId, players));
  });

  draftPicks.forEach(pick => {
    const receivingRosterId = toNumber(pick?.owner_id) || toNumber(pick?.roster_id);
    if (!receivingRosterId) return;
    if (!assetsByRoster.has(receivingRosterId)) {
      assetsByRoster.set(receivingRosterId, []);
    }
    assetsByRoster.get(receivingRosterId).push(formatDraftPick(pick));
  });

  const lines = Array.from(assetsByRoster.entries()).map(([rosterId, assets]) => ({
    teamName: teamLookup.get(rosterId) || `Roster ${rosterId}`,
    assets: assets.length ? assets : ["Details unavailable from Sleeper"]
  }));

  if (!lines.length) {
    return [{ teamName: "Trade", assets: ["Details unavailable from Sleeper"] }];
  }

  return lines;
}

function createTradeRow(trade, players) {
  const row = document.createElement("tr");
  if (trade.isSample) {
    row.className = "is-sample-trade";
  }

  const leagueLabel = text(trade.snapshot?.localLeagueName) || text(trade.snapshot?.leagueRecordId) || "League";
  const division = text(trade.snapshot?.division);
  const assetLines = getTransactionAssetLines(trade.transaction, trade.snapshot, players);

  const date = document.createElement("td");
  date.textContent = text(trade.transaction?.dateLabel) || formatTradeDate(trade.transaction?.created);

  const league = document.createElement("td");
  const leagueWrap = document.createElement("div");
  leagueWrap.className = "format-center-trade-league";
  const imageSrc = getDivisionImageSrc(leagueLabel);

  if (imageSrc) {
    const logo = document.createElement("img");
    logo.className = "format-center-trade-logo";
    logo.src = imageSrc;
    logo.alt = `${leagueLabel} division logo`;
    leagueWrap.appendChild(logo);
  } else {
    const leagueName = document.createElement("strong");
    leagueName.textContent = leagueLabel;
    leagueWrap.appendChild(leagueName);
  }

  if (trade.isSample) {
    const sampleBadge = document.createElement("span");
    sampleBadge.className = "format-center-sample-badge";
    sampleBadge.textContent = "Sample";
    leagueWrap.appendChild(sampleBadge);
  }
  if (division) {
    const divisionLabel = document.createElement("span");
    divisionLabel.className = "format-center-trade-subtext";
    divisionLabel.textContent = division;
    leagueWrap.appendChild(divisionLabel);
  }
  league.appendChild(leagueWrap);

  const teams = document.createElement("td");
  teams.textContent = assetLines.map(line => line.teamName).join(" / ");

  const details = document.createElement("td");
  const list = document.createElement("div");
  list.className = "format-center-trade-details";
  assetLines.forEach(line => {
    const item = document.createElement("p");
    const team = document.createElement("strong");
    team.textContent = `${line.teamName} receives: `;
    item.append(team, document.createTextNode(line.assets.join(", ")));
    list.appendChild(item);
  });
  details.appendChild(list);

  row.append(date, league, teams, details);
  return row;
}

function getSampleTrades(centerView, snapshots) {
  const fallbackSnapshots = centerView.key === "dynasty"
    ? [
        { localLeagueName: "Foundry", leagueRecordId: "DYB1", division: "Slow" },
        { localLeagueName: "Legacy", leagueRecordId: "DYB3", division: "Fast" }
      ]
    : [
        { localLeagueName: "Titan", leagueRecordId: "RDB1", division: "Slow" },
        { localLeagueName: "Iron", leagueRecordId: "RDB3", division: "Fast" }
      ];

  const usableSnapshots = snapshots.length ? snapshots : fallbackSnapshots;
  const firstSnapshot = usableSnapshots[0] || fallbackSnapshots[0];
  const secondSnapshot = usableSnapshots[1] || usableSnapshots[0] || fallbackSnapshots[1];

  if (centerView.key === "dynasty") {
    return [
      {
        isSample: true,
        snapshot: firstSnapshot,
        transaction: {
          dateLabel: "Sample",
          sampleLines: [
            { teamName: "Startup Builder", assets: ["Garrett Wilson", "2027 Round 2"] },
            { teamName: "Win-Now Core", assets: ["Saquon Barkley", "2026 Round 3"] }
          ]
        }
      },
      {
        isSample: true,
        snapshot: secondSnapshot,
        transaction: {
          dateLabel: "Sample",
          sampleLines: [
            { teamName: "Pick Collector", assets: ["2026 Round 1", "2027 Round 1"] },
            { teamName: "QB Shopper", assets: ["Dak Prescott"] }
          ]
        }
      }
    ];
  }

  return [
    {
      isSample: true,
      snapshot: firstSnapshot,
      transaction: {
        dateLabel: "Sample",
        sampleLines: [
          { teamName: "RB Needy Team", assets: ["Breece Hall"] },
          { teamName: "Depth Builder", assets: ["DK Metcalf", "Rachaad White"] }
        ]
      }
    },
    {
      isSample: true,
      snapshot: secondSnapshot,
      transaction: {
        dateLabel: "Sample",
        sampleLines: [
          { teamName: "Contender", assets: ["Amon-Ra St. Brown"] },
          { teamName: "Roster Rebuilder", assets: ["Jaylen Waddle", "Brian Robinson"] }
        ]
      }
    }
  ];
}

function renderSampleTrades(centerView, snapshots, body, status) {
  const sampleTrades = getSampleTrades(centerView, snapshots);

  body.innerHTML = "";
  sampleTrades.forEach(trade => {
    body.appendChild(createTradeRow(trade, {}));
  });

  status.textContent = "Sample trades shown";
}

function renderTradeTrackerUnavailable(message, statusLabel = "Trade tracker unavailable") {
  const summary = document.getElementById("tradeTrackerSummary");
  const status = document.getElementById("tradeTrackerStatus");
  const body = document.getElementById("tradeTrackerTableBody");

  if (summary) summary.textContent = message;
  if (status) status.textContent = statusLabel;
  if (body) {
    body.innerHTML = "";
    body.appendChild(createEmptyState(message, 4));
  }
}

async function renderTradeTracker(group) {
  const centerView = scoreboardState.centerView;
  const snapshots = Array.isArray(group?.leagueSnapshots) ? group.leagueSnapshots : [];
  const configuredSnapshots = snapshots.filter(snapshot => text(snapshot?.sleeperLeagueId));
  const summary = document.getElementById("tradeTrackerSummary");
  const status = document.getElementById("tradeTrackerStatus");
  const body = document.getElementById("tradeTrackerTableBody");

  if (!summary || !status || !body) return;

  if (!configuredSnapshots.length) {
    renderTradeTrackerUnavailable(centerView.tradeTrackerMissing, "No leagues configured");
    return;
  }

  summary.textContent = centerView.tradeTrackerIntro;
  status.textContent = "Loading trades...";
  body.innerHTML = "";
  body.appendChild(createEmptyState("Loading trades from Sleeper...", 4));

  const results = await Promise.all(configuredSnapshots.map(async snapshot => {
    const sleeperLeagueId = text(snapshot?.sleeperLeagueId);
    const weekResults = await Promise.all(TRADE_TRACKER_WEEKS.map(async week => {
      try {
        const response = await fetch(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/transactions/${week}`, { cache: "no-store" });
        if (!response.ok) {
          throw new Error(`Transactions request failed with status ${response.status}`);
        }
        const transactions = await response.json();
        return Array.isArray(transactions) ? transactions : [];
      } catch (error) {
        console.warn(`Trade tracker load failed for ${sleeperLeagueId} week ${week}:`, error);
        return [];
      }
    }));

    return weekResults
      .flat()
      .filter(transaction => text(transaction?.type).toLowerCase() === "trade")
      .filter(transaction => {
        const statusValue = text(transaction?.status).toLowerCase();
        return !statusValue || statusValue === "complete" || statusValue === "completed";
      })
      .map(transaction => ({ snapshot, transaction }));
  }));

  const trades = results
    .flat()
    .sort((left, right) => toNumber(right.transaction?.created) - toNumber(left.transaction?.created));

  body.innerHTML = "";

  if (!trades.length) {
    summary.textContent = `${centerView.tradeTrackerEmpty} Sample examples are shown below and clearly marked until live trades exist.`;
    renderSampleTrades(centerView, configuredSnapshots, body, status);
    return;
  }

  await Promise.all(configuredSnapshots.map(hydrateTradeTeamLookup));
  const players = await getSleeperPlayers();
  trades.slice(0, 50).forEach(trade => {
    body.appendChild(createTradeRow(trade, players));
  });

  status.textContent = `${trades.length} trade${trades.length === 1 ? "" : "s"} tracked`;
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
  const hubTitle = document.getElementById("centerHubTitle");
  const hubCopy = document.getElementById("centerHubCopy");
  const hubLink = document.getElementById("centerHubLink");
  const constitutionLink = document.getElementById("centerConstitutionLink");
  const topConstitutionLink = document.getElementById("centerTopConstitutionLink");
  const scoreboardSummary = document.getElementById("scoreboardSummary");
  const tradeTrackerSummary = document.getElementById("tradeTrackerSummary");
  const divisionCountsHeading = document.getElementById("divisionCountsHeading");
  const scoreboardsHeading = document.getElementById("scoreboardsHeading");
  const standingsHeading = document.getElementById("standingsHeading");
  const tradeTrackerHeading = document.getElementById("tradeTrackerHeading");

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
  if (hubTitle) {
    hubTitle.textContent = centerView.hubTitle;
  }
  if (hubCopy) {
    hubCopy.textContent = centerView.hubCopy;
  }
  if (hubLink) {
    hubLink.href = BRACKET_HUB_URL;
  }
  constitutionLink.href = centerView.constitutionPage;
  constitutionLink.textContent = "View Constitution";
  if (topConstitutionLink) {
    topConstitutionLink.href = centerView.constitutionPage;
    topConstitutionLink.textContent = "View Constitution";
  }
  scoreboardSummary.textContent = centerView.scoreboardsIntro;
  if (tradeTrackerSummary) {
    tradeTrackerSummary.textContent = centerView.tradeTrackerIntro;
  }
  groupName.textContent = label;
  lastUpdated.textContent = formatTimestamp(group?.lastSyncedAt);
  trackedTeams.textContent = `${overallStandings.length} tracked`;
  playoffFieldSize.textContent = `${playoffField.length} / ${targetPlayoffSize}`;

  if (divisionCountsHeading) {
    divisionCountsHeading.textContent = centerView.divisionHeading;
  }
  if (scoreboardsHeading) {
    scoreboardsHeading.textContent = "Live League Scoreboards";
  }
  if (standingsHeading) {
    standingsHeading.textContent = "Full Combined Standings";
  }
  if (tradeTrackerHeading) {
    tradeTrackerHeading.textContent = "Trade Tracker";
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

    const normalizedName = text(entry.leagueName).toLowerCase();
    const imageMap = centerView.key === "dynasty"
      ? DYNASTY_DIVISION_IMAGE_BY_NAME
      : REDRAFT_DIVISION_IMAGE_BY_NAME;
    const imageSrc = imageMap[normalizedName] || "";

    if (imageSrc) {
      const imageWrap = document.createElement("div");
      imageWrap.className = "format-center-division-image-wrap";

      const image = document.createElement("img");
      image.className = "format-center-division-image";
      image.src = imageSrc;
      image.alt = `${entry.leagueName} division artwork`;

      imageWrap.appendChild(image);
      card.appendChild(imageWrap);
    }

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

function getPlayoffField(group) {
  const playoffField = Array.isArray(group?.playoffField) ? group.playoffField : [];
  return [...playoffField]
    .filter(entry => entry?.team)
    .sort((left, right) => toNumber(left?.seed) - toNumber(right?.seed));
}

function createBracketSlot(label) {
  const slot = document.createElement("div");
  slot.className = "format-center-bracket-slot";

  const seed = document.createElement("span");
  seed.className = "format-center-bracket-seed";
  seed.textContent = label;

  slot.appendChild(seed);
  return slot;
}

function createBracketMatchupCard(leftLabel, rightLabel, label, note = "", size = "standard") {
  const card = document.createElement("article");
  card.className = `format-center-bracket-matchup${size !== "standard" ? ` is-${size}` : ""}`;

  const heading = document.createElement("div");
  heading.className = "format-center-bracket-matchup-header";

  const title = document.createElement("h3");
  title.textContent = label;
  heading.appendChild(title);

  if (note) {
    const noteEl = document.createElement("p");
    noteEl.className = "format-center-bracket-matchup-note";
    noteEl.textContent = note;
    heading.appendChild(noteEl);
  }

  const teams = document.createElement("div");
  teams.className = "format-center-bracket-matchup-body";
  teams.append(createBracketSlot(leftLabel), createBracketSlot(rightLabel));

  card.append(heading, teams);
  return card;
}

function createBracketPlaceholderCard(label, lineOne, lineTwo) {
  const card = document.createElement("article");
  card.className = "format-center-bracket-matchup is-placeholder";

  const heading = document.createElement("div");
  heading.className = "format-center-bracket-matchup-header";
  const title = document.createElement("h3");
  title.textContent = label;
  heading.appendChild(title);

  const body = document.createElement("div");
  body.className = "format-center-bracket-placeholder";
  body.innerHTML = `<span>${lineOne}</span><span>${lineTwo}</span>`;

  card.append(heading, body);
  return card;
}

function createBracketTextCard(label, lineOne, lineTwo, tone = "standard") {
  const card = document.createElement("article");
  card.className = `format-center-bracket-matchup format-center-bracket-text-card${tone === "placeholder" ? " is-placeholder" : ""}`;

  const heading = document.createElement("div");
  heading.className = "format-center-bracket-matchup-header";

  const title = document.createElement("h3");
  title.textContent = label;
  heading.appendChild(title);

  const body = document.createElement("div");
  body.className = "format-center-bracket-text-body";

  const lineOneEl = document.createElement("span");
  lineOneEl.textContent = lineOne;

  const lineTwoEl = document.createElement("span");
  lineTwoEl.textContent = lineTwo;

  body.append(lineOneEl, lineTwoEl);
  card.append(heading, body);
  return card;
}

function createBracketScoreCard(label, topLabel, topScore, bottomLabel, bottomScore, note = "") {
  const card = document.createElement("article");
  card.className = "format-center-bracket-matchup format-center-bracket-score-card";

  const heading = document.createElement("div");
  heading.className = "format-center-bracket-matchup-header";

  const title = document.createElement("h3");
  title.textContent = label;
  heading.appendChild(title);

  if (note) {
    const noteEl = document.createElement("p");
    noteEl.className = "format-center-bracket-matchup-note";
    noteEl.textContent = note;
    heading.appendChild(noteEl);
  }

  const body = document.createElement("div");
  body.className = "format-center-bracket-score-body";

  const entries = [
    { label: topLabel, score: topScore },
    { label: bottomLabel, score: bottomScore }
  ];

  entries.forEach(entry => {
    const row = document.createElement("div");
    row.className = `format-center-bracket-score-row${Number(entry.score) === Math.max(topScore, bottomScore) ? " is-winner" : ""}`;

    const team = document.createElement("span");
    team.className = "format-center-bracket-score-label";
    team.textContent = entry.label;

    const score = document.createElement("span");
    score.className = "format-center-bracket-score-value";
    score.textContent = Number(entry.score).toFixed(2);

    row.append(team, score);
    body.appendChild(row);
  });

  card.append(heading, body);
  return card;
}

function createBracketSection(titleText, summaryText = "") {
  const section = document.createElement("section");
  section.className = "format-center-bracket-stage";

  const header = document.createElement("div");
  header.className = "format-center-bracket-stage-header";

  const title = document.createElement("h3");
  title.textContent = titleText;
  header.appendChild(title);

  if (summaryText) {
    const summary = document.createElement("p");
    summary.className = "format-center-bracket-stage-copy";
    summary.textContent = summaryText;
    header.appendChild(summary);
  }

  section.appendChild(header);
  return section;
}

function createBracketDiagramPaths() {
  const paths = [
    "M236 54 H252 V182 H268",
    "M236 310 H252 V182 H268",
    "M236 566 H252 V694 H268",
    "M236 822 H252 V694 H268",
    "M468 182 H484 V438 H500",
    "M468 694 H484 V438 H500",
    "M670 438 H702",
    "M1404 54 H1388 V182 H1372",
    "M1404 310 H1388 V182 H1372",
    "M1404 566 H1388 V694 H1372",
    "M1404 822 H1388 V694 H1372",
    "M1172 182 H1156 V438 H1140",
    "M1172 694 H1156 V438 H1140",
    "M970 438 H938"
  ];

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "format-center-bracket-svg");
  svg.setAttribute("viewBox", "0 0 1640 876");
  svg.setAttribute("aria-hidden", "true");

  paths.forEach(d => {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", d);
    path.setAttribute("fill", "none");
    path.setAttribute("stroke", "#9fb3c8");
    path.setAttribute("stroke-width", "4");
    path.setAttribute("stroke-linecap", "round");
    path.setAttribute("stroke-linejoin", "round");
    svg.appendChild(path);
  });

  return svg;
}

function createBracketDiagramNode(column, row, roundKey, sideKey, card) {
  const node = document.createElement("div");
  node.className = "format-center-bracket-node";
  node.style.gridColumn = String(column);
  node.style.gridRow = String(row);
  node.dataset.round = roundKey;
  node.dataset.side = sideKey;
  card.classList.add("format-center-bracket-diagram-card");
  node.appendChild(card);
  return node;
}

function getMockDynastyPlayoffNodes() {
  return [
    createBracketDiagramNode(1, 1, "round-of-16", "left", createBracketScoreCard("Round of 16 A", "Seed 1", 156.42, "Seed 16", 118.77)),
    createBracketDiagramNode(1, 3, "round-of-16", "left", createBracketScoreCard("Round of 16 B", "Seed 8", 133.58, "Seed 9", 141.21)),
    createBracketDiagramNode(1, 5, "round-of-16", "left", createBracketScoreCard("Round of 16 C", "Seed 5", 149.06, "Seed 12", 136.44)),
    createBracketDiagramNode(1, 7, "round-of-16", "left", createBracketScoreCard("Round of 16 D", "Seed 4", 127.13, "Seed 13", 130.89)),
    createBracketDiagramNode(2, 2, "quarterfinals", "left", createBracketScoreCard("Quarterfinal 1", "Seed 1", 151.88, "Seed 9", 146.22)),
    createBracketDiagramNode(2, 6, "quarterfinals", "left", createBracketScoreCard("Quarterfinal 2", "Seed 5", 138.74, "Seed 13", 144.37)),
    createBracketDiagramNode(3, 4, "semifinals", "left", createBracketScoreCard("Semifinal 1", "Seed 1", 162.54, "Seed 13", 154.91)),
    createBracketDiagramNode(4, 4, "championship", "center", createBracketScoreCard("Title Game", "Seed 1", 168.02, "Seed 2", 159.47)),
    createBracketDiagramNode(5, 4, "semifinals", "right", createBracketScoreCard("Semifinal 2", "Seed 2", 148.35, "Seed 6", 141.92)),
    createBracketDiagramNode(6, 2, "quarterfinals", "right", createBracketScoreCard("Quarterfinal 3", "Seed 6", 140.68, "Seed 3", 134.11)),
    createBracketDiagramNode(6, 6, "quarterfinals", "right", createBracketScoreCard("Quarterfinal 4", "Seed 7", 126.94, "Seed 2", 145.76)),
    createBracketDiagramNode(7, 1, "round-of-16", "right", createBracketScoreCard("Round of 16 E", "Seed 6", 137.85, "Seed 11", 132.09)),
    createBracketDiagramNode(7, 3, "round-of-16", "right", createBracketScoreCard("Round of 16 F", "Seed 3", 144.63, "Seed 14", 121.47)),
    createBracketDiagramNode(7, 5, "round-of-16", "right", createBracketScoreCard("Round of 16 G", "Seed 7", 135.14, "Seed 10", 128.39)),
    createBracketDiagramNode(7, 7, "round-of-16", "right", createBracketScoreCard("Round of 16 H", "Seed 2", 152.27, "Seed 15", 117.84))
  ];
}

function getMockRedraftPlayoffNodes() {
  return [
    createBracketDiagramNode(1, 1, "round-of-16", "left", createBracketScoreCard("Round of 16 A", "Seed 1", 142.61, "Seed 29", 126.12)),
    createBracketDiagramNode(1, 3, "round-of-16", "left", createBracketScoreCard("Round of 16 B", "Seed 12", 136.84, "Wild Card winner", 133.44)),
    createBracketDiagramNode(1, 5, "round-of-16", "left", createBracketScoreCard("Round of 16 C", "Seed 5", 147.28, "Seed 21", 138.93)),
    createBracketDiagramNode(1, 7, "round-of-16", "left", createBracketScoreCard("Round of 16 D", "Seed 14", 131.55, "Seed 18", 135.02)),
    createBracketDiagramNode(2, 2, "quarterfinals", "left", createBracketScoreCard("Quarterfinal 1", "Seed 1", 150.9, "Seed 12", 141.16)),
    createBracketDiagramNode(2, 6, "quarterfinals", "left", createBracketScoreCard("Quarterfinal 2", "Seed 5", 143.31, "Seed 18", 148.08)),
    createBracketDiagramNode(3, 4, "semifinals", "left", createBracketScoreCard("Semifinal 1", "Seed 1", 155.67, "Seed 18", 149.54)),
    createBracketDiagramNode(4, 4, "championship", "center", createBracketScoreCard("Title Game", "Seed 1", 161.48, "Seed 3", 157.83)),
    createBracketDiagramNode(5, 4, "semifinals", "right", createBracketScoreCard("Semifinal 2", "Seed 3", 146.22, "Seed 10", 139.75)),
    createBracketDiagramNode(6, 2, "quarterfinals", "right", createBracketScoreCard("Quarterfinal 3", "Seed 3", 138.94, "Seed 19", 134.5)),
    createBracketDiagramNode(6, 6, "quarterfinals", "right", createBracketScoreCard("Quarterfinal 4", "Seed 10", 132.18, "Seed 16", 144.73)),
    createBracketDiagramNode(7, 1, "round-of-16", "right", createBracketScoreCard("Round of 16 E", "Seed 10", 127.41, "Seed 19", 134.88)),
    createBracketDiagramNode(7, 3, "round-of-16", "right", createBracketScoreCard("Round of 16 F", "Seed 3", 151.07, "Seed 14", 122.95)),
    createBracketDiagramNode(7, 5, "round-of-16", "right", createBracketScoreCard("Round of 16 G", "Seed 16", 140.62, "Seed 20", 136.2)),
    createBracketDiagramNode(7, 7, "round-of-16", "right", createBracketScoreCard("Round of 16 H", "Seed 11", 148.19, "Seed 18", 130.44))
  ];
}

function renderMainBracket(container, nodes) {
  const board = document.createElement("div");
  board.className = "format-center-bracket-board";

  const labels = document.createElement("div");
  labels.className = "format-center-bracket-label-row";

  [
    "Round of 16",
    "Quarterfinals",
    "Semifinals",
    "Championship",
    "Semifinals",
    "Quarterfinals",
    "Round of 16"
  ].forEach(labelText => {
    const label = document.createElement("span");
    label.className = "format-center-bracket-label";
    label.textContent = labelText;
    labels.appendChild(label);
  });

  const diagram = document.createElement("div");
  diagram.className = "format-center-bracket-diagram";
  diagram.appendChild(createBracketDiagramPaths());

  const grid = document.createElement("div");
  grid.className = "format-center-bracket-grid";
  nodes.forEach(node => grid.appendChild(node));

  diagram.appendChild(grid);
  board.append(labels, diagram);
  container.appendChild(board);
}

function renderDynastyBracketView(group, container) {
  const bracketSection = createBracketSection(
    "Tournament Bracket",
    "The dynasty format opens directly with a 16-team seeded bracket."
  );
  const nodes = getMockDynastyPlayoffNodes();

  renderMainBracket(bracketSection, nodes);
  container.appendChild(bracketSection);
}

function renderRedraftBracketView(group, container) {
  const prelimSection = createBracketSection(
    "Preliminary Rounds",
    "These games set the final Round of 16 field. Once that field is locked, the full tournament bracket begins below."
  );
  const prelimGrid = document.createElement("div");
  prelimGrid.className = "format-center-prelim-grid";

  const playInCards = [];
  playInCards.push(
    createBracketScoreCard(
      "Wild Card Play-In",
      "Seed 31",
      118.94,
      "Seed 32",
      124.66,
      "Seed 32 advances into the opening-round funnel."
    )
  );

  const openingRound = [];
  [
    ["1 vs 30", "Seed 1", 143.8, "Seed 30", 109.44],
    ["2 vs 29", "Seed 2", 132.17, "Seed 29", 137.52],
    ["3 vs 28", "Seed 3", 149.93, "Seed 28", 121.38],
    ["4 vs 27", "Seed 4", 141.04, "Seed 27", 126.15],
    ["5 vs 26", "Seed 5", 145.66, "Seed 26", 115.81],
    ["6 vs 25", "Seed 6", 128.45, "Seed 25", 134.09],
    ["7 vs 24", "Seed 7", 138.97, "Seed 24", 119.72],
    ["8 vs 23", "Seed 8", 130.88, "Seed 23", 117.14],
    ["9 vs 22", "Seed 9", 136.51, "Seed 22", 111.26],
    ["10 vs 21", "Seed 10", 142.64, "Seed 21", 140.37],
    ["11 vs 20", "Seed 11", 138.42, "Seed 20", 131.48],
    ["12 vs 19", "Seed 12", 144.55, "Seed 19", 121.91],
    ["13 vs 18", "Seed 13", 126.04, "Seed 18", 133.29],
    ["14 vs 17", "Seed 14", 139.83, "Seed 17", 120.62],
    ["15 vs 16", "Seed 15", 113.58, "Seed 16", 127.41]
  ].forEach(([label, topSeed, topScore, bottomSeed, bottomScore]) => {
    openingRound.push(createBracketScoreCard(label, topSeed, topScore, bottomSeed, bottomScore));
  });

  const playInPanel = document.createElement("section");
  playInPanel.className = "format-center-prelim-panel";
  const playInTitle = document.createElement("h4");
  playInTitle.className = "format-center-prelim-title";
  playInTitle.textContent = "Wild Card Play-In";
  playInPanel.append(playInTitle, ...playInCards);

  const openingPanel = document.createElement("section");
  openingPanel.className = "format-center-prelim-panel";
  const openingTitle = document.createElement("h4");
  openingTitle.className = "format-center-prelim-title";
  openingTitle.textContent = "Opening Round Box Scores";
  const openingList = document.createElement("div");
  openingList.className = "format-center-prelim-list";
  openingRound.forEach(card => openingList.appendChild(card));
  openingPanel.append(openingTitle, openingList);

  prelimGrid.append(playInPanel, openingPanel);
  prelimSection.appendChild(prelimGrid);
  container.appendChild(prelimSection);

  const bracketSection = createBracketSection(
    "Main Tournament Bracket",
    "The redraft bracket starts here visually after the play-in and opening round. The field reseeds once at this stage, so lower surviving seeds can move into any Round of 16 slot."
  );
  const nodes = getMockRedraftPlayoffNodes();

  renderMainBracket(bracketSection, nodes);
  container.appendChild(bracketSection);
}

function renderBracketView(group) {
  const centerView = scoreboardState.centerView;
  const section = document.getElementById("bracketVisualSection");
  const heading = document.getElementById("bracketVisualHeading");
  const summary = document.getElementById("bracketVisualSummary");
  const container = document.getElementById("bracketVisualContainer");
  const isSample = Boolean(group?.isSample);

  section.hidden = scoreboardState.selectedSection !== "bracket";
  container.innerHTML = "";

  heading.textContent = isSample ? "Projected Playoff Bracket" : "Current Playoff Bracket";
  summary.textContent = centerView.key === "dynasty"
    ? isSample
      ? "This visual preview shows how the dynasty bracket will look once the 16-team field is live."
      : "This visual preview shows how the dynasty bracket is structured from the Round of 16 forward."
    : isSample
      ? "This preview separates the preliminary redraft games from the actual Round of 16 bracket so the tournament path is easier to follow."
      : "This layout separates the preliminary redraft games from the main Round of 16 bracket so the tournament path is easier to follow.";

  if (centerView.key === "dynasty") {
    renderDynastyBracketView(group, container);
  } else {
    renderRedraftBracketView(group, container);
  }
}

function updateCenterSectionTabs() {
  const selectedSection = scoreboardState.selectedSection;
  const buttons = Array.from(document.querySelectorAll("[data-center-section]"));
  const divisionSection = document.getElementById("divisionCountsSection");
  const scoreboardsSection = document.getElementById("scoreboardsSection");
  const standingsSection = document.getElementById("standingsSection");
  const bracketSection = document.getElementById("bracketVisualSection");
  const tradeTrackerSection = document.getElementById("tradeTrackerSection");

  buttons.forEach(button => {
    button.classList.toggle("is-active", text(button.dataset.centerSection) === selectedSection);
  });

  const showStandings = selectedSection === "standings";
  const showTrades = selectedSection === "trades";
  divisionSection.hidden = !showStandings;
  scoreboardsSection.hidden = !showStandings;
  standingsSection.hidden = !showStandings;
  bracketSection.hidden = selectedSection !== "bracket";
  if (tradeTrackerSection) {
    tradeTrackerSection.hidden = !showTrades;
  }
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
  scoreboardState.selectedSection = getCenterSection();
  scoreboardState.liveGroup = null;
  scoreboardState.selectedLeagueRecordId = "";
  updateCenterViewSwitcher();
  updateCenterSectionTabs();

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
    renderBracketView(group);
    renderDivisionCounts(group);
    renderStandings(group);
    await renderLiveScoreboards(liveGroup);
    await renderTradeTracker(liveGroup);
    updateCenterSectionTabs();
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

    const bracketContainer = document.getElementById("bracketVisualContainer");
    bracketContainer.innerHTML = "";
    const emptyBracketState = document.createElement("div");
    emptyBracketState.className = "empty-state";
    emptyBracketState.textContent = "Unable to load bracket view right now.";
    bracketContainer.appendChild(emptyBracketState);

    renderScoreboardsUnavailable([], centerView.unavailableScoreboardsMessage);
    renderTradeTrackerUnavailable(centerView.unavailableTradeTrackerMessage);
    updateCenterSectionTabs();
  }
}

Array.from(document.querySelectorAll("[data-center-section]")).forEach(button => {
  button.addEventListener("click", () => {
    const nextSection = text(button.dataset.centerSection).toLowerCase();
    scoreboardState.selectedSection = nextSection === "bracket" || nextSection === "trades" ? nextSection : "standings";
    updateCenterSectionTabs();
  });
});

document.getElementById("reloadCenterButton")?.addEventListener("click", () => {
  window.location.reload();
});

document.getElementById("refreshScoresButton")?.addEventListener("click", async () => {
  if (!scoreboardState.liveGroup) {
    return;
  }

  await renderLiveScoreboards(scoreboardState.liveGroup);
});

document.getElementById("refreshTradesButton")?.addEventListener("click", async () => {
  if (!scoreboardState.liveGroup) {
    return;
  }

  await renderTradeTracker(scoreboardState.liveGroup);
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
