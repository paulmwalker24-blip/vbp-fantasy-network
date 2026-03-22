const LEAGUES_JSON_URL = "data/leagues.json";
const DONATION_CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vSO-kh0CyOIwgGHf25x4lfXG44cIZrpvr6dP74eiWKFiqIplbmsB3z5WGrNRyj1zLeTM4_KZA62KHnF/pub?gid=0&single=true&output=csv";

const FORMAT_META = {
  redraft: { label: "Redraft", description: "Standard seasonal competition with balanced scoring." },
  dynasty: { label: "Dynasty", description: "Build and manage a roster long term." },
  bestball: { label: "Best Ball", description: "Draft once and let optimal scoring handle the lineup." },
  bracket: { label: "Bracket", description: "Tournament-style competition across divisions." },
  keeper: { label: "Keeper", description: "Returning format slot reserved for future launch." },
  chopped: { label: "Chopped", description: "Planned format slot reserved for future launch." }
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
  const v = (value || "").toLowerCase().replace(/\s+/g, "").trim();
  if (v.includes("best")) return "bestball";
  if (v.includes("bracket")) return "bracket";
  if (v.includes("dynasty")) return "dynasty";
  if (v.includes("keeper")) return "keeper";
  if (v.includes("chopped")) return "chopped";
  if (v.includes("redraft")) return "redraft";
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
      spotsLeft: Math.max(league.teams - league.filled, 0)
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
      spotsLeft: Math.max(hydrated.teams - hydrated.filled, 0)
    };
  } catch (error) {
    console.warn(`Sleeper sync failed for ${league.id || league.name}:`, error);
    return {
      ...league,
      link: league.inviteLink,
      spotsLeft: Math.max(league.teams - league.filled, 0)
    };
  }
}

function createLeagueCard(league) {
  const card = document.createElement("article");
  card.className = `league-card${league.spotsLeft === 0 ? " full-card" : ""}`;

  const spotsBadgeClass = league.spotsLeft === 0
    ? "badge badge-full"
    : league.spotsLeft <= 3
      ? "badge badge-urgent"
      : "badge badge-spots";

  const spotsBadgeText = league.spotsLeft === 0
    ? "Full"
    : `${league.spotsLeft} Spot${league.spotsLeft === 1 ? "" : "s"} Left`;

  const name = document.createElement("h3");
  name.className = "league-name";
  name.textContent = league.name;

  const details = document.createElement("div");
  details.className = "league-line";
  details.textContent = `${formatCurrency(league.buyIn)} | ${FORMAT_META[league.format].label}`;

  const fillStatus = document.createElement("div");
  fillStatus.className = "league-line";
  fillStatus.textContent = `${league.filled} / ${league.teams} Filled`;

  const badges = document.createElement("div");
  badges.className = "league-badges";

  const badge = document.createElement("span");
  badge.className = spotsBadgeClass;
  badge.textContent = spotsBadgeText;
  badges.appendChild(badge);

  const actions = document.createElement("div");
  actions.className = "league-actions";
  actions.appendChild(
    league.spotsLeft === 0
      ? createButton("League Full", "btn btn-disabled")
      : createButton(
        league.link ? "Join League" : "Join Unavailable",
        league.link ? "btn btn-primary" : "btn btn-disabled",
        league.link
      )
  );

  card.append(name, details, fillStatus, badges, actions);
  return card;
}

function renderLimitedSpots(leagues) {
  const container = document.getElementById("limitedSpotsContainer");
  if (!container) return;

  const limited = leagues
    .filter(league => league.spotsLeft > 0)
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
    summary.textContent = `${grouped.length} League${grouped.length === 1 ? "" : "s"}${grouped.length ? ` | ${openSpots} Spot${openSpots === 1 ? "" : "s"} Open` : ""}`;

    header.append(titleWrap, summary);

    const grid = document.createElement("div");
    grid.className = "card-grid";

    if (!grouped.length) {
      grid.appendChild(createEmptyState(`No active ${meta.label.toLowerCase()} leagues are listed right now.`));
    } else {
      sortLeaguesByDisplayOrder(grouped)
        .forEach(league => grid.appendChild(createLeagueCard(league)));
    }

    section.append(header, grid);
    container.appendChild(section);
  });

  const lastUpdated = document.getElementById("lastUpdated");
  if (lastUpdated) {
    lastUpdated.textContent = `Data loaded: ${new Date().toLocaleString()}`;
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

    const remaining = Math.max(project.goal - project.donated, 0);
    const fundedPercent = project.goal > 0
      ? Math.min((project.donated / project.goal) * 100, 100)
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

function normalizeDonationText(value) {
  return String(value || "").trim().toLowerCase();
}

function donationRowText(row) {
  return row.map(normalizeDonationText).join(" | ");
}

function donationRowLooksLikeNonProject(row) {
  const text = donationRowText(row);

  return !text
    || text.includes("timestamp")
    || text.includes("how much did you donate")
    || text.includes("project donated to")
    || text.includes("email address")
    || text.includes("upload screenshot")
    || text.includes("submit")
    || text.includes("project name,state,donated,goal,link")
    || text.includes("project slot")
    || text.includes("form")
    || text.includes("response");
}

function donationSlotValue(value) {
  return String(value || "").trim();
}

function donationSlotNumber(value) {
  const match = donationSlotValue(value).match(/\d+/);
  return match ? Number(match[0]) : NaN;
}

function looksLikeUrl(value) {
  return /^https?:\/\//i.test(String(value || "").trim());
}

function getDonationProjectName(row) {
  const colB = String(row[1] || "").trim();
  const colA = String(row[0] || "").trim();

  if (colB && !/^project\s*\d+$/i.test(colB)) {
    return colB;
  }

  if (colA && !/^\d+$/i.test(colA) && !/^project\s*\d+$/i.test(colA)) {
    return colA;
  }

  return colB || colA;
}

function isLikelyProjectRow(row) {
  if (!row || !row.length || donationRowLooksLikeNonProject(row)) {
    return false;
  }

  const name = getDonationProjectName(row);
  const state = String(row[2] || "").trim();
  const donated = toNumber(row[3]);
  const goal = toNumber(row[4]);
  const link = String(row[5] || "").trim();

  const hasProjectSignal = !!name || !!state || donated > 0 || goal > 0 || looksLikeUrl(link);
  const badName = /how much did you donate|project donated to|timestamp|response/i.test(name);

  return hasProjectSignal && !badName;
}

async function loadDonations() {
  const response = await fetch(DONATION_CSV_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Donation CSV request failed with status ${response.status}`);
  }

  const text = await response.text();
  const rows = parseCSV(text);

  if (!rows.length) {
    return [];
  }

  return rows
    .filter(isLikelyProjectRow)
    .map((row, index) => {
      const slot = donationSlotValue(row[0]);
      const slotNumber = donationSlotNumber(slot);
      const name = getDonationProjectName(row);

      return {
        slot,
        slotNumber: Number.isFinite(slotNumber) ? slotNumber : index + 1,
        slotLabel: Number.isFinite(slotNumber) ? slotNumber : index + 1,
        name,
        state: String(row[2] || "").trim(),
        donated: toNumber(row[3]),
        goal: toNumber(row[4]),
        link: String(row[5] || "").trim()
      };
    })
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
