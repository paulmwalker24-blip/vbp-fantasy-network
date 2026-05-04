const DATA_URLS = {
  leagues: "data/leagues.json",
  donations: "data/donations.json"
};

const ELEMENT_IDS = {
  limitedSpots: "limitedSpotsContainer",
  formatFilters: "formatFilters",
  leagues: "leaguesContainer",
  donations: "donationProjectsContainer",
  lastUpdated: "lastUpdated"
};

const FORMAT_META = {
  bestball: { label: "Best Ball", description: "Draft once and let optimal scoring handle the lineup." },
  bracket: { label: "Redraft Bracket", description: "Tournament-style redraft competition across divisions." },
  chopped: { label: "Chopped", description: "Elimination redraft where the goal is to survive the weekly cut." },
  dynasty: { label: "Dynasty", description: "Build and manage a roster long term." },
  dynastybracket: { label: "Dynasty Bracket", description: "Multi-division dynasty feeding a shared playoff bracket." },
  keeper: { label: "Keeper", description: "Annual redraft with keepers, rising costs, and long-term strategy." },
  redraft: { label: "Redraft", description: "Standard seasonal competition with balanced scoring." }
};

let currentLeagueFilter = "all";

function getElement(id) {
  return document.getElementById(id);
}

function clearElement(element) {
  if (element) {
    element.innerHTML = "";
  }
}

function toNumber(value) {
  const cleaned = String(value || "").replace(/[$,%\s]/g, "").replace(/,/g, "");
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatCurrency(value) {
  return `$${Number(value || 0).toLocaleString()}`;
}

function slugify(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function pluralize(count, singular, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}

function normalizeFormat(value) {
  const normalized = String(value || "").toLowerCase().replace(/[\s-]+/g, "").trim();

  if (normalized.includes("dynastybracket")) return "dynastybracket";
  if (normalized.includes("best")) return "bestball";
  if (normalized.includes("bracket")) return "bracket";
  if (normalized.includes("dynasty")) return "dynasty";
  if (normalized.includes("keeper")) return "keeper";
  if (normalized.includes("chopped")) return "chopped";
  if (normalized.includes("redraft")) return "redraft";

  return "";
}

function normalizeDraftStyle(value, format) {
  if (format === "bracket") {
    return "";
  }

  const normalized = String(value || "").toLowerCase().replace(/\s+/g, " ").trim();
  if (normalized === "fast" || normalized === "fast draft") return "fast";
  if (normalized === "slow" || normalized === "slow draft") return "slow";
  return "";
}

function normalizeFilledCount(teams, filled) {
  const safeTeams = Math.max(toNumber(teams), 0);
  const safeFilled = Math.max(toNumber(filled), 0);
  return Math.min(safeFilled, safeTeams);
}

function normalizeLeagueEntry(entry) {
  const format = normalizeFormat(entry.format);
  const teams = toNumber(entry.teams);
  const status = String(entry.status || "").trim().toLowerCase();
  const hasExplicitFilled = entry.filled !== "" && entry.filled !== null && entry.filled !== undefined;
  const filled = hasExplicitFilled
    ? toNumber(entry.filled)
    : status === "full"
      ? teams
      : 0;

  return {
    id: String(entry.id || "").trim(),
    sleeperLeagueId: String(entry.sleeperLeagueId || "").trim(),
    sleeperSeason: String(entry.sleeperSeason || "").trim(),
    name: String(entry.name || "").trim(),
    format,
    draftStyle: normalizeDraftStyle(entry.draftStyle, format),
    division: String(entry.division || "").trim(),
    teams,
    filled: normalizeFilledCount(teams, filled),
    sleeperFilled: entry.sleeperFilled === "" || entry.sleeperFilled === null || entry.sleeperFilled === undefined
      ? null
      : normalizeFilledCount(teams, entry.sleeperFilled),
    buyIn: toNumber(entry.buyIn),
    inviteLink: String(entry.inviteLink || "").trim(),
    leagueSafeLink: String(entry.leagueSafeLink || "").trim(),
    constitutionPage: String(entry.constitutionPage || "").trim(),
    status,
    notes: String(entry.notes || "").trim(),
    lastUpdated: String(entry.lastUpdated || "").trim()
  };
}

function normalizeDonationProject(project, index) {
  const slotLabel = project.slotLabel === "" || project.slotLabel === null || project.slotLabel === undefined
    ? index + 1
    : Number.isFinite(Number(project.slotLabel))
      ? Number(project.slotLabel)
      : index + 1;

  return {
    slot: String(project.slot || `Project ${index + 1}`).trim(),
    slotLabel,
    name: String(project.name || "").trim(),
    state: String(project.state || "").trim(),
    donated: toNumber(project.donated),
    goal: toNumber(project.goal),
    remaining: project.remaining === "" || project.remaining === null || project.remaining === undefined
      ? null
      : toNumber(project.remaining),
    link: String(project.link || "").trim()
  };
}

function isComingSoonLeague(league) {
  return String(league?.status || "").trim().toLowerCase() === "coming-soon";
}

function getLeagueSpotsLeft(league) {
  if (isComingSoonLeague(league)) {
    return 0;
  }

  return Math.max(league.teams - league.filled, 0);
}

function getLeagueOrderValue(league) {
  const match = String(league.id || "").match(/(\d+)$/);
  return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER;
}

function sortLeaguesByDisplayOrder(leagues) {
  return [...leagues].sort((a, b) => {
    const idOrder = getLeagueOrderValue(a) - getLeagueOrderValue(b);
    if (idOrder !== 0) return idOrder;
    return a.name.localeCompare(b.name);
  });
}

function getBalancedRowSizes(count) {
  if (count <= 0) return [];
  if (count <= 4) return [count];

  const rowCount = Math.ceil(count / 5);
  const baseSize = Math.floor(count / rowCount);
  const remainder = count % rowCount;

  return Array.from(
    { length: rowCount },
    (_, index) => baseSize + (index < remainder ? 1 : 0)
  );
}

function getLeagueDivisionLabel(league) {
  return String(league.division || "").trim();
}

function getDraftStyleLabel(league) {
  if (league.format === "bracket") {
    return "";
  }

  if (league.draftStyle === "fast") return "Fast Draft";
  if (league.draftStyle === "slow") return "Slow Draft";
  return "";
}

function getLeagueContextNote(league) {
  const explicitNote = String(league.notes || "").trim();
  if (explicitNote) {
    return explicitNote;
  }

  if (league.format === "dynastybracket" || league.constitutionPage === "dynasty-bracket-constitution.html") {
    return "Part of 48 Team Dynasty Bracket";
  }

  if (league.format === "bracket") {
    return "Part of 60 Team Redraft Bracket";
  }

  return "";
}

function isSafeExternalUrl(value) {
  try {
    const url = new URL(String(value || "").trim());
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function createEmptyState(message) {
  const state = document.createElement("div");
  state.className = "empty-state";
  state.textContent = message;
  return state;
}

function createButton(label, className, href) {
  if (href && isSafeExternalUrl(href)) {
    const link = document.createElement("a");
    link.className = className;
    link.href = href;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = label;
    return link;
  }

  const span = document.createElement("span");
  span.className = className;
  span.textContent = label;
  return span;
}

function createTextElement(tagName, className, text) {
  const element = document.createElement(tagName);
  if (className) {
    element.className = className;
  }
  element.textContent = text;
  return element;
}

async function fetchJson(url, label) {
  const response = await fetch(url, { cache: "no-store" });

  if (!response.ok) {
    throw new Error(`${label} request failed with status ${response.status}`);
  }

  return response.json();
}

async function fetchSleeperLeagueData(sleeperLeagueId) {
  const encodedLeagueId = encodeURIComponent(sleeperLeagueId);
  const [leagueResponse, rostersResponse] = await Promise.all([
    fetch(`https://api.sleeper.app/v1/league/${encodedLeagueId}`, { cache: "no-store" }),
    fetch(`https://api.sleeper.app/v1/league/${encodedLeagueId}/rosters`, { cache: "no-store" })
  ]);

  if (!leagueResponse.ok) {
    throw new Error(`Sleeper league request failed with status ${leagueResponse.status}`);
  }

  if (!rostersResponse.ok) {
    throw new Error(`Sleeper league rosters request failed with status ${rostersResponse.status}`);
  }

  const league = await leagueResponse.json();
  const rosters = await rostersResponse.json();
  const filled = Array.isArray(rosters)
    ? rosters.filter(roster => String(roster?.owner_id || "").trim() !== "").length
    : 0;

  return {
    name: String(league.name || "").trim(),
    teams: toNumber(league.total_rosters),
    filled,
    season: String(league.season || "").trim(),
    status: String(league.status || "").trim().toLowerCase()
  };
}

function buildLeagueRenderModel(league, syncState, syncEligible = false) {
  return {
    ...league,
    link: league.inviteLink,
    spotsLeft: getLeagueSpotsLeft(league),
    liveSyncEligible: syncEligible,
    liveSyncState: syncState
  };
}

async function hydrateLeague(entry) {
  const league = normalizeLeagueEntry(entry);

  if (!league.sleeperLeagueId) {
    return buildLeagueRenderModel(league, "manual", false);
  }

  try {
    const sleeper = await fetchSleeperLeagueData(league.sleeperLeagueId);
    const teams = sleeper.teams || league.teams;
    const hydrated = {
      ...league,
      teams,
      filled: normalizeFilledCount(teams, league.filled),
      sleeperFilled: normalizeFilledCount(teams, sleeper.filled),
      sleeperSeason: sleeper.season || league.sleeperSeason
    };

    return buildLeagueRenderModel(hydrated, "live", true);
  } catch (error) {
    console.warn(`Sleeper sync failed for ${league.id || league.name}:`, error);
    return buildLeagueRenderModel(league, "fallback", true);
  }
}

async function loadLeagues() {
  const payload = await fetchJson(DATA_URLS.leagues, "Local leagues JSON");
  const leagueEntries = Array.isArray(payload) ? payload : payload.leagues;

  if (!Array.isArray(leagueEntries)) {
    throw new Error("Local leagues JSON is missing a leagues array.");
  }

  const hydrated = await Promise.all(leagueEntries.map(hydrateLeague));
  return hydrated.filter(league => league.name && league.format && league.teams > 0);
}

async function loadDonations() {
  const payload = await fetchJson(DATA_URLS.donations, "Local donations JSON");
  const projects = Array.isArray(payload) ? payload : payload.projects;

  if (!Array.isArray(projects)) {
    throw new Error("Local donations JSON is missing a projects array.");
  }

  return projects
    .map(normalizeDonationProject)
    .filter(project => project.name || project.state || project.goal > 0 || project.link)
    .slice(0, 3);
}

function getSpotsBadge(league) {
  if (isComingSoonLeague(league)) {
    return { className: "badge badge-coming-soon", text: "Coming Soon" };
  }

  if (league.spotsLeft === 0) {
    return { className: "badge badge-full", text: "Full" };
  }

  return {
    className: league.spotsLeft <= 3 ? "badge badge-urgent" : "badge badge-spots",
    text: `${league.spotsLeft} Spot${league.spotsLeft === 1 ? "" : "s"} Left`
  };
}

function appendDraftBadges(badges, league, divisionLabel) {
  const draftStyleLabel = getDraftStyleLabel(league);
  const bracketDivisionLabel = league.format === "bracket" && divisionLabel
    ? `${divisionLabel} Draft`
    : "";

  if (draftStyleLabel) {
    badges.appendChild(
      createTextElement("span", `badge badge-draft-${league.draftStyle}`, draftStyleLabel)
    );
  }

  if (bracketDivisionLabel) {
    const normalizedDivision = divisionLabel.toLowerCase();
    const badgeClass = normalizedDivision === "fast" ? "badge-draft-fast" : "badge-draft-slow";
    badges.appendChild(createTextElement("span", `badge ${badgeClass}`, bracketDivisionLabel));
  }
}

function createLeagueAction(league, isComingSoon) {
  if (isComingSoon) {
    return createButton("Coming Soon", "btn btn-disabled");
  }

  if (league.spotsLeft === 0) {
    return createButton("League Full", "btn btn-disabled");
  }

  return createButton(
    league.link ? "Join League" : "Join Unavailable",
    league.link ? "btn btn-primary" : "btn btn-disabled",
    league.link
  );
}

function createLeagueCard(league) {
  const isComingSoon = isComingSoonLeague(league);
  const card = document.createElement("article");
  card.className = `league-card${isComingSoon ? " coming-soon-card" : league.spotsLeft === 0 ? " full-card" : ""}`;

  const divisionLabel = getLeagueDivisionLabel(league);
  const contextNote = getLeagueContextNote(league);
  const spotsBadge = getSpotsBadge(league);

  const details = `${formatCurrency(league.buyIn)} | ${FORMAT_META[league.format].label}`;
  const fillStatus = isComingSoon
    ? `${league.teams} Teams | Setup in progress`
    : `${league.filled} / ${league.teams} Filled`;

  const badges = document.createElement("div");
  badges.className = "league-badges";
  appendDraftBadges(badges, league, divisionLabel);
  badges.appendChild(createTextElement("span", spotsBadge.className, spotsBadge.text));

  const actions = document.createElement("div");
  actions.className = "league-actions";
  actions.appendChild(createLeagueAction(league, isComingSoon));

  card.append(
    createTextElement("h3", "league-name", league.name),
    createTextElement("div", "league-line", details)
  );

  if (divisionLabel && league.format !== "bracket") {
    card.appendChild(createTextElement("div", "league-line", divisionLabel));
  }

  card.appendChild(createTextElement("div", "league-line", fillStatus));

  if (contextNote) {
    card.appendChild(createTextElement("div", "league-line", contextNote));
  }

  card.append(badges, actions);
  return card;
}

function renderLimitedSpots(leagues) {
  const container = getElement(ELEMENT_IDS.limitedSpots);
  if (!container) return;

  const limited = leagues
    .filter(league => !isComingSoonLeague(league) && league.spotsLeft > 0)
    .sort((a, b) => a.spotsLeft - b.spotsLeft || a.filled - b.filled)
    .slice(0, 2);

  clearElement(container);

  if (!limited.length) {
    container.appendChild(createEmptyState("No leagues currently have open spots."));
    return;
  }

  limited.forEach(league => container.appendChild(createLeagueCard(league)));
}

function createLeagueGroupHeader(formatKey, grouped) {
  const meta = FORMAT_META[formatKey];
  const openSpots = grouped.reduce((sum, league) => sum + Math.max(league.spotsLeft, 0), 0);
  const allComingSoon = grouped.length > 0 && grouped.every(isComingSoonLeague);

  const header = document.createElement("div");
  header.className = "league-group-header";

  const titleWrap = document.createElement("div");
  titleWrap.append(
    createTextElement("h3", "league-group-title", meta.label),
    createTextElement("div", "league-group-meta", meta.description)
  );

  const summary = grouped.length
    ? `${pluralize(grouped.length, "League")} | ${allComingSoon ? "Coming soon" : `${pluralize(openSpots, "Spot")} Open`}`
    : "0 Leagues";

  header.append(titleWrap, createTextElement("div", "league-group-meta", summary));
  return header;
}

function createLeagueGroupGrid(formatKey, grouped) {
  const grid = document.createElement("div");
  grid.className = "card-grid-stack";

  if (!grouped.length) {
    const emptyGrid = document.createElement("div");
    emptyGrid.className = "card-grid";
    emptyGrid.appendChild(createEmptyState(`No active ${FORMAT_META[formatKey].label.toLowerCase()} leagues are listed right now.`));
    grid.appendChild(emptyGrid);
    return grid;
  }

  const orderedLeagues = sortLeaguesByDisplayOrder(grouped);
  let offset = 0;

  getBalancedRowSizes(orderedLeagues.length).forEach(size => {
    const row = document.createElement("div");
    row.className = "balanced-card-row";
    row.style.setProperty("--balanced-cols", String(size));

    orderedLeagues
      .slice(offset, offset + size)
      .forEach(league => row.appendChild(createLeagueCard(league)));

    grid.appendChild(row);
    offset += size;
  });

  return grid;
}

function renderLeagues(leagues) {
  const container = getElement(ELEMENT_IDS.leagues);
  if (!container) return;

  clearElement(container);

  Object.keys(FORMAT_META).forEach(formatKey => {
    if (currentLeagueFilter !== "all" && currentLeagueFilter !== formatKey) {
      return;
    }

    const grouped = leagues.filter(league => league.format === formatKey);
    const section = document.createElement("section");
    section.className = "league-group";
    section.id = `format-${slugify(formatKey)}`;
    section.append(
      createLeagueGroupHeader(formatKey, grouped),
      createLeagueGroupGrid(formatKey, grouped)
    );

    container.appendChild(section);
  });

  renderLeagueSummary(leagues);
}

function renderLeagueSummary(leagues) {
  const lastUpdated = getElement(ELEMENT_IDS.lastUpdated);
  if (!lastUpdated) return;

  const totalOpenSpots = leagues.reduce((sum, league) => sum + Math.max(league.spotsLeft, 0), 0);
  const sleeperBackedCount = leagues.filter(league => league.liveSyncEligible).length;
  const liveSyncedCount = leagues.filter(league => league.liveSyncState === "live").length;
  const summaryParts = [
    `${pluralize(leagues.length, "League")} Listed`,
    `${pluralize(totalOpenSpots, "Spot")} Open`
  ];

  if (sleeperBackedCount > 0) {
    summaryParts.push(`Sleeper Live Sync ${liveSyncedCount}/${sleeperBackedCount}`);

    if (liveSyncedCount < sleeperBackedCount) {
      summaryParts.push("Fallback local data shown where live refresh failed");
    }
  }

  summaryParts.push(`Refreshed ${new Date().toLocaleString()}`);
  lastUpdated.textContent = summaryParts.join(" | ");
}

function initLeagueFilters(allLeagues) {
  const container = getElement(ELEMENT_IDS.formatFilters);
  if (!container) return;

  container.addEventListener("click", event => {
    const button = event.target.closest(".format-filter");
    if (!button) return;

    currentLeagueFilter = button.dataset.format || "all";

    container.querySelectorAll(".format-filter").forEach(filterButton => {
      filterButton.classList.toggle("is-active", filterButton === button);
    });

    renderLeagues(allLeagues);

    const leaguesSection = document.getElementById("leagues");
    if (leaguesSection) {
      leaguesSection.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  });
}

function renderDonationFallback(message) {
  const container = getElement(ELEMENT_IDS.donations);
  if (!container) return;

  clearElement(container);
  container.appendChild(createEmptyState(message));
}

function createDonationCard(project) {
  const card = document.createElement("article");
  card.className = "donation-card";

  const remaining = project.remaining === null
    ? Math.max(project.goal - project.donated, 0)
    : Math.max(toNumber(project.remaining), 0);
  const fundedAmount = project.goal >= remaining
    ? Math.max(project.goal - remaining, 0)
    : 0;
  const fundedPercent = project.goal > 0
    ? Math.min((fundedAmount / project.goal) * 100, 100)
    : 0;

  const progressRow = document.createElement("div");
  progressRow.className = "donation-progress-row";
  progressRow.append(
    createTextElement("span", "", `${Math.round(fundedPercent)}% funded`),
    createTextElement("span", "", `${formatCurrency(remaining)} remaining`)
  );

  const progress = document.createElement("div");
  progress.className = "donation-progress";
  progress.setAttribute("aria-hidden", "true");
  const progressFill = document.createElement("span");
  progressFill.style.width = `${fundedPercent}%`;
  progress.appendChild(progressFill);

  const actions = document.createElement("div");
  actions.className = "league-actions";
  actions.appendChild(
    createButton(
      project.link ? "Support This Project" : "Project Link Unavailable",
      project.link ? "btn btn-primary" : "btn btn-disabled",
      project.link
    )
  );

  card.append(
    createTextElement("div", "badge badge-spots", `Project ${project.slotLabel}`),
    createTextElement("h3", "", project.name),
    createTextElement("div", "donation-meta", project.state),
    createTextElement("div", "donation-amount", `${formatCurrency(project.donated)} donated by VBP community`),
    createTextElement("div", "donation-meta", `${formatCurrency(project.goal)} goal`),
    progressRow,
    progress,
    actions
  );

  return card;
}

function renderDonations(projects) {
  const container = getElement(ELEMENT_IDS.donations);
  if (!container) return;

  clearElement(container);

  if (!Array.isArray(projects) || !projects.length) {
    renderDonationFallback("No classroom projects are available right now.");
    return;
  }

  projects.forEach(project => container.appendChild(createDonationCard(project)));
}

function renderLeagueLoadError() {
  const leaguesContainer = getElement(ELEMENT_IDS.leagues);
  const limitedSpotsContainer = getElement(ELEMENT_IDS.limitedSpots);

  if (leaguesContainer) {
    clearElement(leaguesContainer);
    leaguesContainer.appendChild(createEmptyState("Unable to load league data right now."));
  }

  if (limitedSpotsContainer) {
    clearElement(limitedSpotsContainer);
    limitedSpotsContainer.appendChild(createEmptyState("Unable to load limited spot leagues right now."));
  }
}

async function initLeagues() {
  try {
    const leagues = await loadLeagues();
    renderLimitedSpots(leagues);
    renderLeagues(leagues);
    initLeagueFilters(leagues);
  } catch (error) {
    console.error("League load failed:", error);
    renderLeagueLoadError();
  }
}

async function initDonations() {
  try {
    const projects = await loadDonations();
    renderDonations(projects);
  } catch (error) {
    console.error("Donation load failed:", error);
    renderDonationFallback("Unable to load classroom projects right now.");
  }
}

function init() {
  initLeagues();
  initDonations();
}

init();
