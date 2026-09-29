/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - FOOTFALL & ANALYTICS MODULE
   ========================================================================== */

const AnalyticsView = (function () {
  let categoryChart = null;

  function render(container, state) {
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-chart-pie"></i> Mall Analytics & Spatial Traffic Insights</div>
            <div class="card-subtitle">Footfall density distribution, popular search keywords, and dwell time analysis.</div>
          </div>
          <button class="btn btn-secondary" onclick="NavCoreApp.showToast('Exported Analytics Report PDF!', 'success')">
            <i class="fa-solid fa-file-pdf"></i> Export PDF Report
          </button>
        </div>

        <div class="grid-2">
          <!-- Category Traffic Share Chart -->
          <div class="card" style="background: var(--bg-tertiary);">
            <h4 style="font-weight: 800; font-size: 14px; margin-bottom: 12px;"><i class="fa-solid fa-chart-pie"></i> Navigation Queries by Category</h4>
            <div style="height: 260px; position: relative;">
              <canvas id="category-chart-canvas"></canvas>
            </div>
          </div>

          <!-- Top Popular Search POIs Ranking -->
          <div class="card">
            <h4 style="font-weight: 800; font-size: 14px; margin-bottom: 14px;"><i class="fa-solid fa-fire-flame-curved"></i> Top Searched POI Destinations</h4>
            <table class="data-table" style="font-size: 12px;">
              <thead>
                <tr><th>Rank</th><th>POI Name</th><th>Floor</th><th>Queries</th></tr>
              </thead>
              <tbody>
                <tr>
                  <td><span class="badge badge-amber">#1</span></td>
                  <td style="font-weight: 700;">Dilmah Ceylon Tea Lounge</td>
                  <td>Ground Floor</td>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">1,420</td>
                </tr>
                <tr>
                  <td><span class="badge badge-slate">#2</span></td>
                  <td style="font-weight: 700;">PVR Scope Cinemas IMAX</td>
                  <td>Level 3</td>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">1,280</td>
                </tr>
                <tr>
                  <td><span class="badge badge-slate">#3</span></td>
                  <td style="font-weight: 700;">Ministry of Crab Express</td>
                  <td>Level 2</td>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">950</td>
                </tr>
                <tr>
                  <td><span class="badge badge-slate">#4</span></td>
                  <td style="font-weight: 700;">Odel Flagship Store</td>
                  <td>Ground Floor</td>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">880</td>
                </tr>
                <tr>
                  <td><span class="badge badge-slate">#5</span></td>
                  <td style="font-weight: 700;">B1 Eco EV Charging Hub</td>
                  <td>Basement 1</td>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">720</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;

    setTimeout(initChart, 100);
  }

  function initChart() {
    const ctx = document.getElementById('category-chart-canvas');
    if (!ctx) return;

    if (categoryChart) categoryChart.destroy();

    categoryChart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: ['Dining & Cafes', 'Fashion & Apparel', 'Tech & Electronics', 'Entertainment', 'Services'],
        datasets: [{
          data: [35, 25, 20, 12, 8],
          backgroundColor: ['#06B6D4', '#3B82F6', '#10B981', '#F59E0B', '#8B5CF6'],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: 'right', labels: { color: '#94A3B8', font: { family: 'Plus Jakarta Sans', weight: '600' } } }
        }
      }
    });
  }

  return { render };
})();
