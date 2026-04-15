const LEAGUES_JSON_URL = "data/leagues.json";
const DONATIONS_JSON_URL = "data/donations.json";

const FORMAT_META = {
  bestball: { label: "Best Ball", description: "Draft once and let optimal scoring handle the lineup." },
  bracket: { label: "Redraft Bracket", description: "Tournament-style redraft competition across divisions." },
  chopped: { label: "Chopped", description: "Planned format slot reserved for future launch." },
  dynasty: { label: "Dynasty", description: "Build and manage a roster long term." },
  dynastybracket: { label: "Dynasty Bracket", description: "Multi-division dynasty feeding a shared playoff bracket." },
  keeper: { label: "Keeper", description: "Annual redraft with two offseason keepers and rising draft costs." },
  redraft: { label: "Redraft", description: "Standard seasonal competition with balanced scoring." }
};

let currentLeagueFilter = "all";

function parseCSV(text) {
  const rows = [];
  let row = [];
  let value = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    const next = text[i + 1];

    if (char === '"') {
      if (inQuotes && next === '"') {
        value += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === "," && !inQuotes) {
      row.push(value);
      value = "";
    } else if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && next === "\n") {
        i += 1;
      }
      row.push(value);
      if (row.some(cell => String(cell || "").trim() !== "")) {
        rows.push(row);
      }
      row = [];
      value = "";
    } else {
      value += char;
    }
  }

  if (value.length > 0 || row.length > 0) {
    row.push(value);
    if (row.some(cell => String(cell || "").trim() !== "")) {
      rows.push(row);
    }
  }

  return rows;
}

function toNumber(value) {
  const cleaned = String(value || "").replace(/[$,%\s]/g, "").replace(/,/g, "");
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeFormat(value) {
  const v = (value || "").toLowerCase().replace(/[\s-]+/g, "").trim();
  if (v.includes("dynastybracket")) return "dynastybracket";
  if (v.includes("best")) return "bestball";
  if (v.includes("bracket")) return "bracket";
  if (v.includes("dynasty")) return "dynasty";
  if (v.includes("keeper")) return "keeper";
  if (v.includes("chopped")) return "chopped";
  if (v.includes("redraft")) return "redraft";
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

function slugify(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function formatCurrency(value) {
  return `$${Number(value || 0).toLocaleString()}`;
}

function normalizeFilledCount(teams, filled) {
  const safeTeams = Math.max(toNumber(teams), 0);
  const safeFilled = Math.max(toNumber(filled), 0);
  return Math.min(safeFilled, safeTeams);
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

function isSafeExternalUrl(value) {
  try {
    const url = new URL(String(value || "").trim());
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
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

function createEmptyState(message) {
  const state = document.createElement("div");
  state.className = "empty-state";
  state.textContent = message;
  return state;
}

function getLeagueDivisionLabel(league) {
  const division = String(league.division || "").trim();
  if (!division) return "";

  return division;
}

function getDraftStyleLabel(league) {
  if (league.format === "bracket") {
    return "";
  }

  if (league.draftStyle === "fast") {
    return "Fast Draft";
  }

  if (league.draftStyle === "slow") {
    return "Slow Draft";
  }

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

function getBalancedRowSizes(count) {
  if (count <= 0) return [];
  if (count <= 4) return [count];

  const rowCount = Math.ceil(count / 5);
  const baseSize = Math.floor(count / rowCount);
  const remainder = count % rowCount;
  const sizes = [];

  for (let index = 0; index < rowCount; index += 1) {
    sizes.push(baseSize + (index < remainder ? 1 : 0));
  }

  return sizes;
}

function normalizeLeagueEntry(entry) {
  const format = normalizeFormat(entry.format);
  const teams = toNumber(entry.teams);
  const explicitFilled = entry.filled === "" || entry.filled === null || entry.filled === undefined
    ? null
    : toNumber(entry.filled);
  const status = String(entry.status || "").trim().toLowerCase();
  const filled = explicitFilled === null
    ? status === "full"
      ? teams
      : 0
    : explicitFilled;

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
    buyIn: toNumber(entry.buyIn),
    inviteLink: String(entry.inviteLink || "").trim(),
    leagueSafeLink: String(entry.leagueSafeLink || "").trim(),
    constitutionPage: String(entry.constitutionPage || "").trim(),
    status,
    notes: String(entry.notes || "").trim(),
    lastUpdated: String(entry.lastUpdated || "").trim()
  };
}

async function fetchSleeperLeagueData(sleeperLeagueId) {
  const [leagueResponse, rostersResponse] = await Promise.all([
    fetch(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}`, { cache: "no-store" }),
    fetch(`https://api.sleeper.app/v1/league/${encodeURIComponent(sleeperLeagueId)}/rosters`, { cache: "no-store" })
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

async function hydrateLeague(entry) {
  const league = normalizeLeagueEntry(entry);

  if (!league.sleeperLeagueId) {
    return {
      ...league,
      link: league.inviteLink,
      spotsLeft: getLeagueSpotsLeft(league),
      liveSyncEligible: false,
      liveSyncState: "manual"
    };
  }

  try {
    const sleeper = await fetchSleeperLeagueData(league.sleeperLeagueId);
    const teams = sleeper.teams || league.teams;
    const filled = normalizeFilledCount(teams, sleeper.filled);
    const hydrated = {
      ...league,
      teams,
      filled,
      sleeperSeason: sleeper.season || league.sleeperSeason
    };

    return {
      ...hydrated,
      link: hydrated.inviteLink,
      spotsLeft: getLeagueSpotsLeft(hydrated),
      liveSyncEligible: true,
      liveSyncState: "live"
    };
  } catch (error) {
    console.warn(`Sleeper sync failed for ${league.id || league.name}:`, error);
    return {
      ...league,
      link: league.inviteLink,
      spotsLeft: getLeagueSpotsLeft(league),
      liveSyncEligible: true,
      liveSyncState: "fallback"
    };
  }
}

function createLeagueCard(league) {
  const card = document.createElement("article");
  const isComingSoon = isComingSoonLeague(league);
  card.className = `league-card${isComingSoon ? " coming-soon-card" : league.spotsLeft === 0 ? " full-card" : ""}`;

  const spotsBadgeClass = isComingSoon
    ? "badge badge-coming-soon"
    : league.spotsLeft === 0
    ? "badge badge-full"
    : league.spotsLeft <= 3
      ? "badge badge-urgent"
      : "badge badge-spots";

  const spotsBadgeText = isComingSoon
    ? "Coming Soon"
    : league.spotsLeft === 0
    ? "Full"
    : `${league.spotsLeft} Spot${league.spotsLeft === 1 ? "" : "s"} Left`;

  const name = document.createElement("h3");
  name.className = "league-name";
  name.textContent = league.name;

  const details = document.createElement("div");
  details.className = "league-line";
  details.textContent = `${formatCurrency(league.buyIn)} | ${FORMAT_META[league.format].label}`;

  const divisionLabel = getLeagueDivisionLabel(league);
  const division = document.createElement("div");
  division.className = "league-line";
  division.textContent = divisionLabel;

  const fillStatus = document.createElement("div");
  fillStatus.className = "league-line";
  fillStatus.textContent = isComingSoon
    ? `${league.teams} Teams | Setup in progress`
    : `${league.filled} / ${league.teams} Filled`;

  const note = document.createElement("div");
  note.className = "league-line";
  const contextNote = getLeagueContextNote(league);
  note.textContent = contextNote;

  const badges = document.createElement("div");
  badges.className = "league-badges";

  const badge = document.createElement("span");
  badge.className = spotsBadgeClass;
  badge.textContent = spotsBadgeText;
  const draftStyleLabel = getDraftStyleLabel(league);
  const bracketDivisionLabel = league.format === "bracket" && divisionLabel
    ? `${divisionLabel} Draft`
    : "";

  if (draftStyleLabel) {
    const draftStyleBadge = document.createElement("span");
    draftStyleBadge.className = `badge badge-draft-${league.draftStyle}`;
    draftStyleBadge.textContent = draftStyleLabel;
    badges.appendChild(draftStyleBadge);
  }

  if (bracketDivisionLabel) {
    const bracketDivisionBadge = document.createElement("span");
    const normalizedDivision = divisionLabel.toLowerCase();
    bracketDivisionBadge.className = `badge ${normalizedDivision === "fast" ? "badge-draft-fast" : "badge-draft-slow"}`;
    bracketDivisionBadge.textContent = bracketDivisionLabel;
    badges.appendChild(bracketDivisionBadge);
  }

  badges.appendChild(badge);

  const actions = document.createElement("div");
  actions.className = "league-actions";
  actions.appendChild(
    isComingSoon
      ? createButton("Coming Soon", "btn btn-disabled")
      : league.spotsLeft === 0
      ? createButton("League Full", "btn btn-disabled")
      : createButton(
        league.link ? "Join League" : "Join Unavailable",
        league.link ? "btn btn-primary" : "btn btn-disabled",
        league.link
      )
  );

  const content = [name, details];

  if (divisionLabel && league.format !== "bracket") {
    content.push(division);
  }

  content.push(fillStatus);

  if (contextNote) {
    content.push(note);
  }

  content.push(badges, actions);
  card.append(...content);
  return card;
}

function renderLimitedSpots(leagues) {
  const container = document.getElementById("limitedSpotsContainer");
  if (!container) return;

  const limited = leagues
    .filter(league => !isComingSoonLeague(league) && league.spotsLeft > 0)
    .sort((a, b) => a.spotsLeft - b.spotsLeft || a.filled - b.filled)
    .slice(0, 2);

  container.innerHTML = "";

  if (!limited.length) {
    container.appendChild(createEmptyState("No leagues currently have open spots."));
    return;
  }

  limited.forEach(league => container.appendChild(createLeagueCard(league)));
}

function renderLeagues(leagues) {
  const container = document.getElementById("leaguesContainer");
  if (!container) return;

  container.innerHTML = "";

  Object.entries(FORMAT_META).forEach(([formatKey, meta]) => {
    if (currentLeagueFilter !== "all" && currentLeagueFilter !== formatKey) {
      return;
    }

    const grouped = leagues.filter(league => league.format === formatKey);
    const section = document.createElement("section");
    section.className = "league-group";
    section.id = `format-${slugify(formatKey)}`;

    const openSpots = grouped.reduce((sum, league) => sum + Math.max(league.spotsLeft, 0), 0);

    const header = document.createElement("div");
    header.className = "league-group-header";

    const titleWrap = document.createElement("div");
    const title = document.createElement("h3");
    title.className = "league-group-title";
    title.textContent = meta.label;
    const description = document.createElement("div");
    description.className = "league-group-meta";
    description.textContent = meta.description;
    titleWrap.append(title, description);

    const summary = document.createElement("div");
    summary.className = "league-group-meta";
    const allComingSoon = grouped.length > 0 && grouped.every(isComingSoonLeague);
    summary.textContent = grouped.length
      ? `${grouped.length} League${grouped.length === 1 ? "" : "s"} | ${allComingSoon ? "Coming soon" : `${openSpots} Spot${openSpots === 1 ? "" : "s"} Open`}`
      : "0 Leagues";

    header.append(titleWrap, summary);

    const grid = document.createElement("div");
    grid.className = "card-grid-stack";

    if (!grouped.length) {
      const emptyGrid = document.createElement("div");
      emptyGrid.className = "card-grid";
      emptyGrid.appendChild(createEmptyState(`No active ${meta.label.toLowerCase()} leagues are listed right now.`));
      grid.appendChild(emptyGrid);
    } else {
      const orderedLeagues = sortLeaguesByDisplayOrder(grouped);
      let offset = 0;

      getBalancedRowSizes(orderedLeagues.length).forEach(size => {
        const row = document.createElement("div");
        row.className = "balanced-card-row";
        row.style.setProperty("--balanced-cols", String(size));

        orderedLeagues.slice(offset, offset + size)
          .forEach(league => row.appendChild(createLeagueCard(league)));

        grid.appendChild(row);
        offset += size;
      });
    }

    section.append(header, grid);
    container.appendChild(section);
  });

  const lastUpdated = document.getElementById("lastUpdated");
  if (lastUpdated) {
    const totalLeagues = leagues.length;
    const totalOpenSpots = leagues.reduce((sum, league) => sum + Math.max(league.spotsLeft, 0), 0);
    const sleeperBackedCount = leagues.filter(league => league.liveSyncEligible).length;
    const liveSyncedCount = leagues.filter(league => league.liveSyncState === "live").length;
    const summaryParts = [
      `${totalLeagues} League${totalLeagues === 1 ? "" : "s"} Listed`,
      `${totalOpenSpots} Spot${totalOpenSpots === 1 ? "" : "s"} Open`
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
}

function initLeagueFilters(allLeagues) {
  const container = document.getElementById("formatFilters");
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
  const container = document.getElementById("donationProjectsContainer");
  if (!container) return;
  container.innerHTML = "";
  container.appendChild(createEmptyState(message));
}

function renderDonations(projects) {
  const container = document.getElementById("donationProjectsContainer");
  if (!container) return;

  container.innerHTML = "";

  if (!Array.isArray(projects) || !projects.length) {
    renderDonationFallback("No classroom projects are available right now.");
    return;
  }

  projects.slice(0, 3).forEach(project => {
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

    const badge = document.createElement("div");
    badge.className = "badge badge-spots";
    badge.textContent = `Project ${project.slotLabel}`;

    const title = document.createElement("h3");
    title.textContent = project.name;

    const state = document.createElement("div");
    state.className = "donation-meta";
    state.textContent = project.state;

    const donated = document.createElement("div");
    donated.className = "donation-amount";
    donated.textContent = `${formatCurrency(project.donated)} donated by VBP community`;

    const goal = document.createElement("div");
    goal.className = "donation-meta";
    goal.textContent = `${formatCurrency(project.goal)} goal`;

    const progressRow = document.createElement("div");
    progressRow.className = "donation-progress-row";
    const funded = document.createElement("span");
    funded.textContent = `${Math.round(fundedPercent)}% funded`;
    const remainingLabel = document.createElement("span");
    remainingLabel.textContent = `${formatCurrency(remaining)} remaining`;
    progressRow.append(funded, remainingLabel);

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

    card.append(badge, title, state, donated, goal, progressRow, progress, actions);
    container.appendChild(card);
  });
}

async function loadLeagues() {
  const response = await fetch(LEAGUES_JSON_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Local leagues JSON request failed with status ${response.status}`);
  }

  const payload = await response.json();
  const leagues = Array.isArray(payload) ? payload : payload.leagues;

  if (!Array.isArray(leagues)) {
    throw new Error("Local leagues JSON is missing a leagues array.");
  }

  const hydrated = await Promise.all(leagues.map(hydrateLeague));
  return hydrated.filter(league => league.name && league.format && league.teams > 0);
}

async function loadDonations() {
  const response = await fetch(DONATIONS_JSON_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Local donations JSON request failed with status ${response.status}`);
  }

  const payload = await response.json();
  const projects = Array.isArray(payload) ? payload : payload.projects;

  if (!Array.isArray(projects)) {
    throw new Error("Local donations JSON is missing a projects array.");
  }

  return projects
    .map((project, index) => ({
      slot: String(project.slot || `Project ${index + 1}`).trim(),
      slotLabel: project.slotLabel === "" || project.slotLabel === null || project.slotLabel === undefined
        ? index + 1
        : Number.isFinite(Number(project.slotLabel))
          ? Number(project.slotLabel)
          : index + 1,
      name: String(project.name || "").trim(),
      state: String(project.state || "").trim(),
      donated: toNumber(project.donated),
      goal: toNumber(project.goal),
      remaining: project.remaining === "" || project.remaining === null || project.remaining === undefined
        ? null
        : toNumber(project.remaining),
      link: String(project.link || "").trim()
    }))
    .filter(project => project.name || project.state || project.goal > 0 || project.link)
    .slice(0, 3);
}

async function initLeagues() {
  try {
    const leagues = await loadLeagues();
    renderLimitedSpots(leagues);
    renderLeagues(leagues);
    initLeagueFilters(leagues);
  } catch (error) {
    console.error("League load failed:", error);

    const leaguesContainer = document.getElementById("leaguesContainer");
    const limitedSpotsContainer = document.getElementById("limitedSpotsContainer");

    if (leaguesContainer) {
      leaguesContainer.innerHTML = "";
      leaguesContainer.appendChild(createEmptyState("Unable to load league data right now."));
    }

    if (limitedSpotsContainer) {
      limitedSpotsContainer.innerHTML = "";
      limitedSpotsContainer.appendChild(createEmptyState("Unable to load limited spot leagues right now."));
    }
  }
}

async function initDonations() {
  try {
    const projects = await loadDonations();

    if (!projects.length) {
      renderDonationFallback("No classroom projects are available right now. If this should show projects, the published CSV is likely pointing to the wrong sheet tab.");
      return;
    }

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
