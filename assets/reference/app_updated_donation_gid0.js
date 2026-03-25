const LEAGUE_CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRDyafe_Pi5gkWS7EN8e-p5XBVkDcgMd7ZzA5jZ_GAI8aX6BEmZGbjHrWenElLGfIJ-ZDboxZhyxLkf/pub?output=csv";
const DONATION_CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vSO-kh0CyOIwgGHf25x4lfXG44cIZrpvr6dP74eiWKFiqIplbmsB3z5WGrNRyj1zLeTM4_KZA62KHnF/pub?gid=0&single=true&output=csv";

const FORMAT_META = {
  redraft: { label: "Redraft", description: "Standard seasonal competition with balanced scoring." },
  dynasty: { label: "Dynasty", description: "Build and manage a roster long term." },
  bestball: { label: "Best Ball", description: "Draft once and let optimal scoring handle the lineup." },
  bracket: { label: "Bracket", description: "Tournament-style competition across divisions." },
  keeper: { label: "Keeper", description: "Returning format slot reserved for future launch." },
  chopped: { label: "Chopped", description: "Planned format slot reserved for future launch." }
};

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
    } else if (char === ',' && !inQuotes) {
      row.push(value);
      value = "";
    } else if ((char === '\n' || char === '\r') && !inQuotes) {
      if (char === '\r' && next === '\n') {
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

function rowsToObjects(rows) {
  if (!rows.length) return [];
  const headers = rows[0].map(cell => cell.trim());
  return rows.slice(1).map(row => {
    const obj = {};
    headers.forEach((header, index) => {
      obj[header] = (row[index] || "").trim();
    });
    return obj;
  });
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

function toNumber(value) {
  const cleaned = String(value || "").replace(/[$,%\s]/g, "").replace(/,/g, "");
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : 0;
}

function pick(obj, keys) {
  for (const key of keys) {
    if (obj[key] !== undefined && String(obj[key]).trim() !== "") {
      return String(obj[key]).trim();
    }
  }
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

  const actionHtml = league.spotsLeft === 0
    ? `<span class="btn btn-disabled">League Full</span>`
    : league.link
      ? `<a href="${league.link}" target="_blank" rel="noopener noreferrer" class="btn btn-primary">Join League</a>`
      : `<span class="btn btn-disabled">Join Unavailable</span>`;

  card.innerHTML = `
    <h3 class="league-name">${league.name}</h3>
    <div class="league-line">${formatCurrency(league.buyIn)} • ${FORMAT_META[league.format].label}</div>
    <div class="league-line">${league.filled} / ${league.teams} Filled</div>
    <div class="league-badges">
      <span class="${spotsBadgeClass}">${spotsBadgeText}</span>
    </div>
    <div class="league-actions">${actionHtml}</div>
  `;

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
    container.innerHTML = `<div class="empty-state">No leagues currently have open spots.</div>`;
    return;
  }

  limited.forEach(league => container.appendChild(createLeagueCard(league)));
}

function renderLeagues(leagues) {
  const container = document.getElementById("leaguesContainer");
  if (!container) return;

  container.innerHTML = "";

  Object.entries(FORMAT_META).forEach(([formatKey, meta]) => {
    const grouped = leagues.filter(league => league.format === formatKey);
    const section = document.createElement("section");
    section.className = "league-group";
    section.id = `format-${slugify(formatKey)}`;

    const openSpots = grouped.reduce((sum, league) => sum + Math.max(league.spotsLeft, 0), 0);

    section.innerHTML = `
      <div class="league-group-header">
        <div>
          <h3 class="league-group-title">${meta.label}</h3>
          <div class="league-group-meta">${meta.description}</div>
        </div>
        <div class="league-group-meta">${grouped.length} League${grouped.length === 1 ? "" : "s"}${grouped.length ? ` • ${openSpots} Spot${openSpots === 1 ? "" : "s"} Open` : ""}</div>
      </div>
      <div class="card-grid"></div>
    `;

    const grid = section.querySelector(".card-grid");

    if (!grouped.length) {
      grid.innerHTML = `<div class="empty-state">No active ${meta.label.toLowerCase()} leagues are listed right now.</div>`;
    } else {
      grouped
        .sort((a, b) => a.spotsLeft - b.spotsLeft || a.name.localeCompare(b.name))
        .forEach(league => grid.appendChild(createLeagueCard(league)));
    }

    container.appendChild(section);
  });

  const lastUpdated = document.getElementById("lastUpdated");
  if (lastUpdated) {
    lastUpdated.textContent = `League data updated: ${new Date().toLocaleString()}`;
  }
}

function renderDonationFallback(message) {
  const container = document.getElementById("donationProjectsContainer");
  if (!container) return;
  container.innerHTML = `<div class="empty-state">${message}</div>`;
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

    const buttonHtml = project.link
      ? `<a href="${project.link}" target="_blank" rel="noopener noreferrer" class="btn btn-primary">Support This Project</a>`
      : `<span class="btn btn-disabled">Project Link Unavailable</span>`;

    card.innerHTML = `
      <div class="badge badge-spots">Project ${project.slotLabel}</div>
      <h3>${project.name}</h3>
      <div class="donation-meta">${project.state}</div>
      <div class="donation-amount">${formatCurrency(project.donated)} donated by VBP community</div>
      <div class="donation-meta">${formatCurrency(project.goal)} goal</div>
      <div class="donation-progress-row">
        <span>${Math.round(fundedPercent)}% funded</span>
        <span>${formatCurrency(remaining)} remaining</span>
      </div>
      <div class="donation-progress" aria-hidden="true">
        <span style="width: ${fundedPercent}%;"></span>
      </div>
      <div class="league-actions">${buttonHtml}</div>
    `;

    container.appendChild(card);
  });
}

async function loadLeagues() {
  const response = await fetch(LEAGUE_CSV_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`League CSV request failed with status ${response.status}`);
  }

  const text = await response.text();
  const rows = rowsToObjects(parseCSV(text));

  return rows
    .map(row => {
      const name = pick(row, ["League_Name", "League Name", "Name"]);
      const format = normalizeFormat(pick(row, ["League_Type", "League Type", "Format"]));
      const teams = toNumber(pick(row, ["Teams", "League_Size", "League Size"]));
      const filled = toNumber(pick(row, ["Spots_Filled", "Spots Filled", "Filled"]));
      const buyIn = toNumber(pick(row, ["Buy_In", "Buy In", "Buy-In"]));
      const link = pick(row, ["Join_Link", "Join Link", "Link"]);

      return {
        name,
        format,
        teams,
        filled,
        spotsLeft: Math.max(teams - filled, 0),
        buyIn,
        link
      };
    })
    .filter(league => league.name && league.format && league.teams > 0);
}

function normalizeDonationText(value) {
  return String(value || "").trim().toLowerCase();
}

function donationRowLooksLikeHeader(row) {
  const normalized = row.map(normalizeDonationText);
  return normalized.includes("project slot")
    || normalized.includes("project name")
    || normalized.includes("state")
    || normalized.includes("donated")
    || normalized.includes("goal")
    || normalized.includes("link")
    || normalized.includes("timestamp")
    || normalized.includes("how much did you donate?")
    || normalized.includes("project donated to.");
}

function donationSlotValue(value) {
  return String(value || "").trim();
}

function donationSlotNumber(value) {
  const match = donationSlotValue(value).match(/\d+/);
  return match ? Number(match[0]) : NaN;
}

function isLikelyProjectRow(row) {
  const slot = donationSlotValue(row[0]);
  const name = String(row[1] || "").trim();
  const state = String(row[2] || "").trim();
  const goal = toNumber(row[4]);
  const link = String(row[5] || "").trim();

  const slotNumber = donationSlotNumber(slot);
  const slotLooksValid = Number.isFinite(slotNumber) || /^project\s*[a-z0-9-]+$/i.test(slot);
  const nameLooksLikeQuestion = /how much did you donate\??/i.test(name);
  const stateLooksLikeQuestion = /project donated to\.?/i.test(state);
  const linkLooksValid = /^https?:\/\//i.test(link);

  return slotLooksValid
    && !!name
    && !nameLooksLikeQuestion
    && !stateLooksLikeQuestion
    && (goal > 0 || linkLooksValid || !!state);
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

  const cleanedRows = rows.filter(row => !donationRowLooksLikeHeader(row));

  return cleanedRows
    .filter(isLikelyProjectRow)
    .map(row => {
      const slot = donationSlotValue(row[0]);
      const slotNumber = donationSlotNumber(slot);

      return {
        slot,
        slotNumber: Number.isFinite(slotNumber) ? slotNumber : Number.MAX_SAFE_INTEGER,
        slotLabel: Number.isFinite(slotNumber) ? slotNumber : slot || "—",
        name: String(row[1] || "").trim(),
        state: String(row[2] || "").trim(),
        donated: toNumber(row[3]),
        goal: toNumber(row[4]),
        link: String(row[5] || "").trim()
      };
    })
    .sort((a, b) => a.slotNumber - b.slotNumber)
    .slice(0, 3);
}

async function initLeagues() {
  try {
    const leagues = await loadLeagues();
    renderLimitedSpots(leagues);
    renderLeagues(leagues);
  } catch (error) {
    console.error("League load failed:", error);

    const leaguesContainer = document.getElementById("leaguesContainer");
    const limitedSpotsContainer = document.getElementById("limitedSpotsContainer");

    if (leaguesContainer) {
      leaguesContainer.innerHTML = `<div class="empty-state">Unable to load league data right now.</div>`;
    }

    if (limitedSpotsContainer) {
      limitedSpotsContainer.innerHTML = `<div class="empty-state">Unable to load limited spot leagues right now.</div>`;
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
