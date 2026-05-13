const POWER_RANKINGS_DATA_URL = "data/power-rankings.json";
const DEFAULT_LEAGUE_RECORD_ID = "DYN2";

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

function renderComponentGrid(container, components) {
  const grid = createElement("div", "power-ranking-component-grid");
  Object.entries(components || {}).forEach(([key, value]) => {
    const item = createElement("div", "power-ranking-component");
    item.appendChild(createElement("strong", "", number(value).toFixed(1)));
    item.appendChild(createElement("span", "", key.replace(/([A-Z])/g, " $1").toLowerCase()));
    grid.appendChild(item);
  });
  container.appendChild(grid);
}

function renderPlayerPills(container, players) {
  const list = createElement("div", "power-ranking-pill-list");
  (players || []).slice(0, 8).forEach(player => {
    const label = [text(player.name), text(player.position), text(player.team)].filter(Boolean).join(" - ");
    const pill = createElement("span", "power-ranking-pill", label);
    if (text(player.injuryStatus)) {
      pill.classList.add("has-status");
      pill.title = `Sleeper status: ${text(player.injuryStatus)}`;
    }
    list.appendChild(pill);
  });
  container.appendChild(list);
}

function renderSnapshot(title, players) {
  const section = createElement("div", "power-ranking-snapshot");
  section.appendChild(createElement("strong", "", title));
  const list = createElement("div", "power-ranking-mini-grid");
  (players || []).forEach(player => {
    const slot = text(player.slot);
    const label = slot
      ? `${slot}: ${text(player.name)} (${text(player.position)}, ${number(player.value).toFixed(1)})`
      : `${text(player.name)} (${text(player.position)}, ${number(player.value).toFixed(1)})`;
    list.appendChild(createElement("span", "", label));
  });
  section.appendChild(list);
  return section;
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

  const reasons = (entry.reasons || []).filter(Boolean);
  if (reasons.length) body.appendChild(createElement("p", "power-ranking-core", reasons.join(" | ")));

  renderComponentGrid(body, entry.components);
  renderPlayerPills(body, entry.topPlayers);

  const details = createElement("details", "power-ranking-details");
  details.appendChild(createElement("summary", "", "Show starters, bench, and scoring trail"));
  details.appendChild(renderSnapshot("Optimized starters", entry.starterSnapshot || []));
  details.appendChild(renderSnapshot("Top bench", entry.benchSnapshot || []));
  body.appendChild(details);

  row.appendChild(body);
  return row;
}

function renderMethodology(methodology) {
  const container = document.querySelector("[data-ranking-methodology]");
  if (!container) return;
  container.innerHTML = "";
  (methodology?.components || []).forEach(component => {
    const item = createElement("div", "power-rankings-method");
    const parts = text(component).split(":");
    item.appendChild(createElement("strong", "", parts[0] || "Input"));
    item.appendChild(createElement("span", "", (parts.slice(1).join(":") || component).trim()));
    container.appendChild(item);
  });
}

function renderLeague(data) {
  const activeLeagueRecordId = getActiveLeagueRecordId();
  const league = (data.leagues || []).find(item => text(item.leagueRecordId).toUpperCase() === activeLeagueRecordId);
  const list = document.querySelector("[data-rankings-list]");
  if (!league || !Array.isArray(league.rankings) || !league.rankings.length) {
    if (list) list.textContent = `${activeLeagueRecordId} rankings are not available yet. Run the local power rankings sync to refresh this page.`;
    return;
  }

  const rankings = [...league.rankings].sort((a, b) => number(a.rank) - number(b.rank));
  const leader = rankings[0];
  const generatedAt = document.querySelector("[data-generated-at]");
  const topScore = document.querySelector("[data-top-score]");
  const topTeam = document.querySelector("[data-top-team]");
  const subtitle = document.querySelector("[data-rankings-subtitle]");
  const kicker = document.querySelector("[data-rankings-kicker]");
  const title = document.querySelector("[data-rankings-title]");
  const featureKicker = document.querySelector("[data-rankings-feature-kicker]");
  const listHeading = document.querySelector("[data-rankings-list-heading]");

  if (generatedAt) {
    const snapshotLabel = text(data.snapshot?.display);
    const generatedLabel = formatDate(data.generatedAt);
    generatedAt.textContent = [snapshotLabel, generatedLabel ? `refreshed ${generatedLabel}` : ""].filter(Boolean).join(" - ");
  }
  if (kicker) kicker.textContent = text(league.leagueRecordId);
  if (title) title.textContent = `${text(league.name)} Power Rankings`;
  if (featureKicker) featureKicker.textContent = text(league.name);
  if (listHeading) listHeading.textContent = `${text(league.leagueRecordId)} Rankings`;
  if (topScore) topScore.textContent = number(leader.score).toFixed(1);
  if (topTeam) topTeam.textContent = text(leader.teamName);
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
  renderMethodology(data.methodology);
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
