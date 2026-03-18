const SHEET_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRDyafe_Pi5gkWS7EN8e-p5XBVkDcgMd7ZzA5jZ_GAI8aX6BEmZGbjHrWenElLGfIJ-ZDboxZhyxLkf/pub?gid=0&single=true&output=csv";
const DONATION_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vSO-kh0CyOIwgGHf25x4lfXG44cIZrpvr6dP74eiWKFiqIplbmsB3z5WGrNRyj1zLeTM4_KZA62KHnF/pub?gid=0&single=true&output=csv";

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
    const isFull = (league.status || "").trim().toUpperCase() === "FULL";
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
        <p class="status ${isFull ? "full" : "open"}">${isFull ? "FULL" : "OPEN"}</p>
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

function loadDonations() {
  fetch(DONATION_URL)
    .then(res => res.text())
    .then(csv => {
      const rows = csv.split(/\r?\n/).slice(1).filter(Boolean);
      let total = 0;
      const projects = [];

    rows.forEach(row => {
      const cols = parseCSVLine(row);
      const slot = cols[0] || "";
      const name = cols[1] || "Unnamed Project";
      const state = cols[2] || "";
      const donated = parseFloat(cols[3]) || 0;
      const goal = parseFloat(cols[4]) || 0;

        total += donated;

        projects.push({
          slot,
          name,
          state,
          donated,
          goal
        });
      });

      renderDonationTotal(total);
      renderDonationProjects(projects);
    })
    .catch(err => {
      console.error("Donation load error:", err);
    });
}

function renderDonationTotal(total) {
  const el = document.getElementById("donation-total");
  if (!el) return;
  el.innerText = `DonorsChoose Donations (Community Reported • Paid Directly to DonorsChoose): $${total.toFixed(2)}`;
}

function renderDonationProjects(projects) {
  const container = document.getElementById("donation-projects");
  if (!container) return;

  container.innerHTML = "";

  projects.forEach(project => {
    const progressText = project.goal > 0
      ? `$${project.donated.toFixed(2)} raised of $${project.goal.toFixed(2)}`
      : `$${project.donated.toFixed(2)} raised`;

    const card = document.createElement("div");
    card.className = "info-card";
    card.innerHTML = `
      <h3>${project.slot}: ${project.name}</h3>
      ${project.state ? `<p>${project.state}</p>` : ""}
      <p><strong>$${project.donated.toFixed(2)}</strong> raised</p>
      ${project.goal > 0 ? `<p>Goal: $${project.goal.toFixed(2)}</p>` : ""}
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
        status: (cols[7] || "OPEN").trim().toUpperCase(),
        draftDate: cols[8] || "",
        link: cols[9] || "",
        notes: cols[10] || "",
        lastUpdated: cols[11] || ""
      }));

     renderLastUpdated();
     loadDonations();
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
  if (!el || allLeagues.length === 0) return;

  const values = allLeagues
    .map(l => (l.lastUpdated || "").trim())
    .filter(v => v);

  el.innerText = values.length
    ? `Last Updated: ${values[0]}`
    : "Last Updated: Not Available";
}
