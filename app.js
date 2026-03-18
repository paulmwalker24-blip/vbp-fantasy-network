const SHEET_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRDyafe_Pi5gkWS7EN8e-p5XBVkDcgMd7ZzA5jZ_GAI8aX6BEmZGbjHrWenElLGfIJ-ZDboxZhyxLkf/pub?gid=0&single=true&output=csv";

let currentFilter = "ALL";
let allLeagues = [];

function parseCSVLine(line) {
  const result = [];
  let current = "";
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    const nextChar = line[i + 1];

    if (char === '"') {
      if (inQuotes && nextChar === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === "," && !inQuotes) {
      result.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }

  result.push(current.trim());
  return result;
}

function setFilter(filter) {
  currentFilter = filter;
  renderStats();
  renderLeagues();
}

function renderStats() {
  const container = document.getElementById("league-stats");
  if (!container) return;

  const types = ["Redraft", "Dynasty", "Best Ball", "Chopped", "Keeper", "Bracket"];
  container.innerHTML = "";

  types.forEach(type => {
    const leagues = allLeagues.filter(l => l.type === type);
    const open = leagues.filter(l => l.status === "OPEN").length;

    if (leagues.length === 0) return;

    const pill = document.createElement("div");
    pill.className = `stat-pill ${currentFilter === type ? "active" : ""}`;
    pill.innerText = `${type} • ${open} open`;
    pill.style.cursor = "pointer";
    pill.onclick = () => setFilter(type);

    container.appendChild(pill);
  });

  const allPill = document.createElement("div");
  allPill.className = `stat-pill ${currentFilter === "ALL" ? "active" : ""}`;
  allPill.innerText = "All";
  allPill.style.cursor = "pointer";
  allPill.onclick = () => setFilter("ALL");

  container.prepend(allPill);
}

function renderLeagues() {
  const container = document.getElementById("leagues");
  container.innerHTML = "";

  const filtered = allLeagues
    .filter(league => {
      if (currentFilter === "ALL") return true;
      return league.type === currentFilter && league.status === "OPEN";
    })
    .sort((a, b) => {
      if (a.status === b.status) return 0;
      if (a.status === "OPEN") return -1;
      return 1;
    });

  if (filtered.length === 0) {
    container.innerHTML = "<p>No leagues found for this filter.</p>";
    return;
  }

  filtered.forEach(league => {
    const isFull = league.status === "FULL";

    const card = document.createElement("div");
    card.className = `card ${isFull ? "full" : ""}`;

    const badgeClass = (league.type || "")
      .toLowerCase()
      .replace(/\s+/g, "-");

    card.innerHTML = `
      <div class="card-header">
        <div>
          <p class="league-id">${league.id || ""}</p>
          <h3>${league.name || "Unnamed League"}</h3>
        </div>
        <span class="badge badge-${badgeClass}">
          ${league.type || "Unknown"}
        </span>
      </div>

      <div class="card-details">
        <div class="detail-box">
          <span class="detail-label">Buy-in</span>
          <span class="detail-value">$${league.buyin || "0"}</span>
        </div>
        <div class="detail-box">
          <span class="detail-label">Spots</span>
          <span class="detail-value">${league.filled || "0"} / ${league.teams || "0"}</span>
        </div>
      </div>

      <div class="card-footer">
        <p class="status ${isFull ? "full" : "open"}">${league.status || "OPEN"}</p>
        ${
          isFull
            ? `<span class="closed">League Full</span>`
            : `<a href="${league.link || "#"}" target="_blank" class="join-btn">Join League</a>`
        }
      </div>
    `;

    container.appendChild(card);
  });
}

fetch(SHEET_URL)
  .then(response => {
    if (!response.ok) {
      throw new Error(`HTTP error ${response.status}`);
    }
    return response.text();
  })
  .then(csv => {
    const lines = csv
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(line => line.length > 0);

    if (lines.length <= 1) {
      document.getElementById("leagues").innerHTML = "<p>No league data found.</p>";
      return;
    }

    const rows = lines.slice(1);

    allLeagues = rows
      .map(row => parseCSVLine(row))
      .filter(cols => cols.length >= 10)
      .map(cols => ({
        id: cols[0] || "",
        name: cols[1] || "",
        type: cols[2] || "",
        division: cols[3] || "",
        buyin: cols[4] || "",
        teams: cols[5] || "",
        filled: cols[6] || "",
        status: (cols[7] || "OPEN").toUpperCase(),
        draftDate: cols[8] || "",
        link: cols[9] || "",
        notes: cols[10] || ""
      }));

     renderLastUpdated();
     renderStats();
     renderLeagues();
  })
  .catch(error => {
    console.error("LOAD ERROR:", error);
    document.getElementById("leagues").innerHTML =
      `<p>Error loading league data: ${error.message}</p>`;
  });

function renderLastUpdated() {
  const el = document.getElementById("last-updated");
  if (!el) return;

  const now = new Date();

  const formatted = now.toLocaleString();

  el.innerText = `Last Updated: ${formatted}`;
}