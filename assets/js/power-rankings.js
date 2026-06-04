const POWER_RANKINGS_DATA_URL = "data/power-rankings.json";
const DEFAULT_LEAGUE_RECORD_ID = "DYN1";
let activeRankingView = "dynasty";

function getActiveLeagueRecordId() {
  const params = new URLSearchParams(window.location.search);
  return text(params.get("league") || DEFAULT_LEAGUE_RECORD_ID).toUpperCase();
}

function text(value) {
  return value === null || value === undefined ? "" : String(value).trim();
}

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function createElement(tagName, className, content) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  if (content !== undefined && content !== null) element.textContent = content;
  return element;
}

function formatDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

function formatRecord(record) {
  const wins = number(record?.wins);
  const losses = number(record?.losses);
  const ties = number(record?.ties);
  const pointsFor = number(record?.pointsFor);
  if (!wins && !losses && !ties && !pointsFor) return "Season not started";
  return `${wins}-${losses}${ties ? `-${ties}` : ""}, ${pointsFor.toFixed(2)} PF`;
}

function renderRankingRow(entry) {
  const row = createElement("article", `power-ranking-row${number(entry.rank) <= 3 ? " is-top" : ""}`);
  row.appendChild(createElement("div", "power-ranking-position", number(entry.rank).toString()));

  const body = createElement("div", "power-ranking-body");
  const header = createElement("div", "power-ranking-header");
  header.appendChild(createElement("h3", "", text(entry.teamName) || `Roster ${entry.rosterId}`));
  header.appendChild(createElement("span", "power-ranking-score", number(entry.score).toFixed(1)));
  body.appendChild(header);
  body.appendChild(createElement("p", "", formatRecord(entry.record)));
  if (Array.isArray(entry.reasons) && entry.reasons.length) {
    const reasons = createElement("ul", "power-ranking-reasons");
    entry.reasons.forEach(reason => {
      const tone = text(reason.tone) === "concern" ? "concern" : "positive";
      reasons.appendChild(createElement("li", `is-${tone}`, text(reason.text)));
    });
    body.appendChild(reasons);
  }

  row.appendChild(body);
  return row;
}

function renderMethodology(methodology) {
  const container = document.querySelector("[data-ranking-methodology]");
  if (!container) return;
  container.innerHTML = "";
  if (text(methodology?.summary)) {
    container.appendChild(createElement("p", "power-rankings-method-summary", text(methodology.summary)));
  }
  const list = createElement("div", "power-rankings-method-list");
  (methodology?.components || []).forEach(component => {
    const item = createElement("div", "power-rankings-method");
    const parts = text(component).split(":");
    item.appendChild(createElement("strong", "", parts[0] || "Input"));
    item.appendChild(createElement("span", "", (parts.slice(1).join(":") || component).trim()));
    list.appendChild(item);
  });
  container.appendChild(list);
}

function formatScoringValue(value) {
  return number(value).toFixed(2);
}

function renderScoringProfile(league) {
  const container = document.querySelector("[data-scoring-profile]");
  if (!container) return;
  container.innerHTML = "";
  const profile = league.scoringProfile;
  if (!profile) {
    container.textContent = "Verified scoring settings have not been generated for this league yet.";
    return;
  }

  const grid = createElement("div", "power-ranking-scoring-grid");
  const fields = [
    ["Base Rec", profile.rec],
    ["RB PPR", profile.rbPpr],
    ["WR PPR", profile.wrPpr],
    ["TE PPR", profile.tePpr],
    ["Rush Yd", profile.rushYard],
    ["Rec Yd", profile.receivingYard],
    ["Rush TD", profile.rushTd],
    ["Rec TD", profile.receivingTd],
    ["Pass Yd", profile.passingYard],
    ["Pass TD", profile.passingTd],
    ["INT", profile.interception]
  ];
  fields.forEach(([label, value]) => {
    const item = createElement("div", "power-ranking-component");
    item.appendChild(createElement("strong", "", formatScoringValue(value)));
    item.appendChild(createElement("span", "", label));
    grid.appendChild(item);
  });
  container.appendChild(grid);
  container.appendChild(createElement("p", "power-ranking-source-note", `${text(profile.source)}.`));
}

function renderPositionBoard(position, board) {
  const card = createElement("article", "power-ranking-position-board");
  const heading = createElement("div", "power-ranking-position-board-header");
  heading.appendChild(createElement("h3", "", position));
  card.appendChild(heading);

  const table = createElement("table", "power-ranking-position-table");
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  ["#", "Owner", "Position Score"].forEach(label => headRow.appendChild(createElement("th", "", label)));
  head.appendChild(headRow);
  table.appendChild(head);
  const body = document.createElement("tbody");
  (board.rankings || []).forEach(owner => {
    const row = document.createElement("tr");
    row.appendChild(createElement("td", "", number(owner.rank).toString()));
    row.appendChild(createElement("td", "", text(owner.manager)));
    row.appendChild(createElement("td", "", number(owner.score).toFixed(1)));
    body.appendChild(row);
  });
  table.appendChild(body);
  card.appendChild(table);
  return card;
}

function renderPositionalRankings(league) {
  const container = document.querySelector("[data-positional-rankings]");
  if (!container) return;
  container.innerHTML = "";
  const boards = league.positionalRankings || {};
  const preferredOrder = ["QB", "RB", "WR", "TE", "K", "DEF", "DL", "LB", "DB", "IDP"];
  const positions = Object.keys(boards).sort((a, b) => {
    const aIndex = preferredOrder.indexOf(a);
    const bIndex = preferredOrder.indexOf(b);
    if (aIndex === -1 && bIndex === -1) return a.localeCompare(b);
    if (aIndex === -1) return 1;
    if (bIndex === -1) return -1;
    return aIndex - bIndex;
  });
  positions.forEach(position => {
    if (boards[position]?.rankings?.length) {
      container.appendChild(renderPositionBoard(position, boards[position]));
    }
  });
  if (!container.children.length) {
    container.textContent = "Positional rankings are not available until the league has drafted rostered players.";
  }
}

function renderLeague(data) {
  const activeLeagueRecordId = getActiveLeagueRecordId();
  const league = (data.leagues || []).find(item => text(item.leagueRecordId).toUpperCase() === activeLeagueRecordId);
  const list = document.querySelector("[data-rankings-list]");
  if (!league || !Array.isArray(league.rankings) || !league.rankings.length) {
    if (list) list.textContent = `${activeLeagueRecordId} rankings are not available yet. Run the local power rankings sync to refresh this page.`;
    return;
  }

  const hasCurrentSeasonBoard = text(league.format).toLowerCase() === "dynasty" && Array.isArray(league.currentSeasonRankings) && league.currentSeasonRankings.length;
  if (!hasCurrentSeasonBoard) activeRankingView = "dynasty";
  const isCurrentSeason = hasCurrentSeasonBoard && activeRankingView === "current-season";
  const sourceRankings = isCurrentSeason ? league.currentSeasonRankings : league.rankings;
  const rankings = [...sourceRankings].sort((a, b) => number(a.rank) - number(b.rank));
  const leader = rankings[0];
  const generatedAt = document.querySelector("[data-generated-at]");
  const topScore = document.querySelector("[data-top-score]");
  const topTeam = document.querySelector("[data-top-team]");
  const subtitle = document.querySelector("[data-rankings-subtitle]");
  const kicker = document.querySelector("[data-rankings-kicker]");
  const title = document.querySelector("[data-rankings-title]");
  const featureKicker = document.querySelector("[data-rankings-feature-kicker]");
  const featureHeading = document.querySelector("[data-rankings-feature-heading]");
  const featureDescription = document.querySelector("[data-rankings-feature-description]");
  const listHeading = document.querySelector("[data-rankings-list-heading]");
  const listDescription = document.querySelector("[data-rankings-list-description]");
  const viewControls = document.querySelector("[data-ranking-view-controls]");
  const positionalSection = document.querySelector("[data-positional-section]");

  if (viewControls) {
    viewControls.hidden = !hasCurrentSeasonBoard;
    viewControls.querySelectorAll("[data-ranking-view]").forEach(button => {
      button.classList.toggle("is-active", button.dataset.rankingView === activeRankingView);
      button.onclick = () => {
        activeRankingView = button.dataset.rankingView;
        renderLeague(data);
      };
    });
  }

  if (generatedAt) {
    const snapshotLabel = text(data.snapshot?.display);
    const generatedLabel = formatDate(data.generatedAt);
    generatedAt.textContent = [snapshotLabel, generatedLabel ? `refreshed ${generatedLabel}` : ""].filter(Boolean).join(" - ");
  }
  if (kicker) kicker.textContent = text(league.leagueRecordId);
  if (title) title.textContent = `${text(league.name)} Power Rankings`;
  if (featureKicker) featureKicker.textContent = text(league.name);
  if (featureHeading) featureHeading.textContent = isCurrentSeason ? "2026 Favorite" : "Dynasty Leader";
  if (featureDescription) {
    featureDescription.textContent = isCurrentSeason
      ? `Built from current-season lineup strength, depth, quarterback play, health, and ${text(league.leagueRecordId)} scoring.`
      : "Built from current roster strength, long-term player value, Superflex quarterbacks, and future draft capital.";
  }
  if (listHeading) listHeading.textContent = isCurrentSeason ? `${text(league.leagueRecordId)} 2026 Contenders` : `${text(league.leagueRecordId)} Dynasty Outlook`;
  if (listDescription) {
    listDescription.textContent = isCurrentSeason
      ? "This board focuses only on who is best positioned to win the current season."
      : "This board balances current roster strength with long-term player value and future draft capital.";
  }
  if (topScore) topScore.textContent = number(leader.score).toFixed(1);
  if (topTeam) topTeam.textContent = text(leader.teamName);
  if (positionalSection) positionalSection.hidden = isCurrentSeason;
  if (subtitle) {
    const rosterLabel = formatDate(league.rosterSync?.refreshedAt);
    const readinessLabel = text(league.draftReadiness?.label);
    subtitle.textContent = [
      `${text(league.name)} uses the latest Sleeper roster endpoint saved during the power-ranking sync.`,
      rosterLabel ? `Roster pull: ${rosterLabel}.` : "",
      readinessLabel ? readinessLabel + "." : ""
    ].filter(Boolean).join(" ");
  }

  if (list) {
    list.innerHTML = "";
    rankings.forEach(entry => list.appendChild(renderRankingRow(entry)));
  }
  renderScoringProfile(league);
  renderPositionalRankings(league);
  renderMethodology(isCurrentSeason ? {
    summary: `The 2026 Contenders board measures ${text(league.leagueRecordId)} only for the current season and does not reward youth or future draft capital.`,
    components: [
      "Starting lineup: the strongest legal weekly lineup carries the most weight.",
      "Usable depth: the best immediate bench options support injuries and bye weeks.",
      "Quarterbacks: Superflex quarterback strength is measured for this season only.",
      "Health and ceiling: active availability and current difference-makers shape the final score.",
      "Excluded: player age runway and future rookie picks do not affect this board."
    ]
  } : data.methodology);
}

async function initPowerRankings() {
  try {
    const response = await fetch(POWER_RANKINGS_DATA_URL, { cache: "no-store" });
    if (!response.ok) throw new Error(`Power rankings request failed with status ${response.status}`);
    renderLeague(await response.json());
  } catch (error) {
    const list = document.querySelector("[data-rankings-list]");
    if (list) list.textContent = "Unable to load generated power rankings right now.";
    console.warn("Unable to load power rankings:", error);
  }
}

initPowerRankings();
