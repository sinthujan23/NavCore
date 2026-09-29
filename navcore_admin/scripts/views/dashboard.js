/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - DASHBOARD VIEW MODULE
   ========================================================================== */

const DashboardView = (function () {
  let footfallChart = null;

  function render(container, state) {
    const activeBuilding = state.buildings.find(b => b.id === state.activeBuildingId) || state.buildings[0];
    const totalShops = state.shops.length;
    const activeSessionsCount = state.activeSessions.length;
    const occupiedSpots = state.parkingSpots.filter(p => p.status === 'occupied').length;
    const totalSpots = state.parkingSpots.length;
    const parkingPct = Math.round((occupiedSpots / totalSpots) * 100);

    container.innerHTML = `
      <!-- Emergency Trigger Bar (if not active) -->
      ${!state.emergencyActive ? `
        <div class="card" style="border-left: 4px solid var(--accent-rose); background: linear-gradient(90deg, rgba(244, 63, 94, 0.08), transparent);">
          <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 16px;">
            <div style="display: flex; align-items: center; gap: 14px;">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: rgba(244, 63, 94, 0.15); display: flex; align-items: center; justify-content: center; color: var(--accent-rose); font-size: 20px;">
                <i class="fa-solid fa-triangle-exclamation"></i>
              </div>
              <div>
                <h4 style="font-weight: 800; font-size: 15px;">Emergency & Safety Override Hub</h4>
                <p style="font-size: 12px; color: var(--text-secondary);">One-click hazard broadcast & AR indoor path rerouting for ${activeBuilding.name}.</p>
              </div>
            </div>
            <button class="btn btn-danger" onclick="NavCoreApp.promptEmergencyTrigger()">
              <i class="fa-solid fa-bullhorn"></i> TRIGGER EMERGENCY REROUTE
            </button>
          </div>
        </div>
      ` : ''}

      <!-- Top KPI Stats Row -->
      <div class="grid-4">
        <div class="card stat-card blue">
          <div class="stat-top">
            <span class="stat-label">Active AR Sessions</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-mobile-screen-button"></i></div>
          </div>
          <div class="stat-value">${activeSessionsCount}</div>
          <div class="stat-trend up"><i class="fa-solid fa-arrow-trend-up"></i> +24% vs peak hour</div>
        </div>

        <div class="card stat-card emerald">
          <div class="stat-top">
            <span class="stat-label">Indexed Shops & POIs</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-store"></i></div>
          </div>
          <div class="stat-value">${totalShops}</div>
          <div class="stat-trend neutral"><i class="fa-solid fa-layer-group"></i> Across 6 Floors</div>
        </div>

        <div class="card stat-card amber">
          <div class="stat-top">
            <span class="stat-label">B1 Deck Parking</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-square-parking"></i></div>
          </div>
          <div class="stat-value">${parkingPct}%</div>
          <div class="stat-trend down"><i class="fa-solid fa-car"></i> ${occupiedSpots} / ${totalSpots} Spots Occupied</div>
        </div>

        <div class="card stat-card rose">
          <div class="stat-top">
            <span class="stat-label">ECEF VPS Accuracy</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-crosshairs"></i></div>
          </div>
          <div class="stat-value">&lt; 0.4m</div>
          <div class="stat-trend up"><i class="fa-solid fa-circle-check"></i> PnP Pose Solver Sub-meter</div>
        </div>
      </div>

      <!-- Main Analytics & Live Floor Matrix Grid -->
      <div class="grid-2-1">
        <!-- Left: Real-time Footfall Chart -->
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title"><i class="fa-solid fa-chart-column"></i> Today's AR Footfall & Navigation Volume</div>
              <div class="card-subtitle">Live hourly active users exploring ${activeBuilding.name}</div>
            </div>
            <div class="card-actions">
              <span class="badge badge-cyan">LIVE SYNC</span>
            </div>
          </div>
          <div style="height: 300px; position: relative;">
            <canvas id="footfall-chart-canvas"></canvas>
          </div>
        </div>

        <!-- Right: Active Venue Summary Card -->
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title"><i class="fa-solid fa-building"></i> ${activeBuilding.name}</div>
              <div class="card-subtitle">${activeBuilding.city}, ${activeBuilding.country}</div>
            </div>
            <span class="badge badge-emerald">${activeBuilding.status}</span>
          </div>

          <div style="display: flex; flex-direction: column; gap: 12px; margin-top: 6px;">
            <div style="display: flex; justify-content: space-between; font-size: 13px; border-bottom: 1px dashed var(--border-color); padding-bottom: 8px;">
              <span style="color: var(--text-secondary);">Base Elevation:</span>
              <span style="font-weight: 700; font-family: monospace; color: var(--accent-cyan);">${activeBuilding.baseElevation}m ASL</span>
            </div>
            <div style="display: flex; justify-content: space-between; font-size: 13px; border-bottom: 1px dashed var(--border-color); padding-bottom: 8px;">
              <span style="color: var(--text-secondary);">Entrance Anchor:</span>
              <span style="font-weight: 700; font-family: monospace; color: var(--text-primary);">${activeBuilding.latitude.toFixed(6)}, ${activeBuilding.longitude.toFixed(6)}</span>
            </div>
            <div style="display: flex; justify-content: space-between; font-size: 13px; border-bottom: 1px dashed var(--border-color); padding-bottom: 8px;">
              <span style="color: var(--text-secondary);">Compass Heading:</span>
              <span style="font-weight: 700; color: var(--accent-amber);">${activeBuilding.compassHeading}° True North</span>
            </div>
            <div style="display: flex; justify-content: space-between; font-size: 13px; border-bottom: 1px dashed var(--border-color); padding-bottom: 8px;">
              <span style="color: var(--text-secondary);">Offline Mesh Size:</span>
              <span style="font-weight: 700; color: var(--accent-purple);">${activeBuilding.packageSizeBytesMB} MB</span>
            </div>
          </div>

          <div style="margin-top: 20px;">
            <button class="btn btn-secondary" style="width: 100%;" onclick="NavCoreApp.navigateTo('malls')">
              <i class="fa-solid fa-sliders"></i> Edit Venue Floor Profile
            </button>
          </div>
        </div>
      </div>

      <!-- Live App Connected Fleet Session Preview -->
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-tower-broadcast"></i> Live Connected Mobile AR Sessions</div>
            <div class="card-subtitle">Real-time PnP pose estimator telemetry from active mobile devices</div>
          </div>
          <button class="btn btn-sm btn-secondary" onclick="NavCoreApp.navigateTo('telemetry')">View All Sessions</button>
        </div>

        <div class="table-responsive">
          <table class="data-table">
            <thead>
              <tr>
                <th>Session ID</th>
                <th>Device Model</th>
                <th>Tracking Mode</th>
                <th>Current Floor</th>
                <th>ECEF Coordinates</th>
                <th>FPS & Battery</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              ${state.activeSessions.map(sess => `
                <tr>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">${sess.id}</td>
                  <td style="font-weight: 700;">${sess.device}</td>
                  <td><span class="badge badge-slate"><i class="fa-solid fa-eye"></i> ${sess.trackingEngine}</span></td>
                  <td>${sess.floor}</td>
                  <td style="font-family: monospace; font-size: 11px;">${sess.lat.toFixed(6)}, ${sess.lon.toFixed(6)}</td>
                  <td><span style="color: var(--accent-emerald); font-weight: 700;">${sess.fps} FPS</span> | ${sess.battery}</td>
                  <td><span class="badge badge-emerald">${sess.status}</span></td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `;

    // Render Chart.js Footfall Graph
    setTimeout(initChart, 100);
  }

  function initChart() {
    const ctx = document.getElementById('footfall-chart-canvas');
    if (!ctx) return;

    if (footfallChart) footfallChart.destroy();

    footfallChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: ['08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00'],
        datasets: [
          {
            label: 'AR Navigation Users',
            data: [12, 45, 120, 210, 380, 410, 350, 480, 520, 610],
            borderColor: '#06B6D4',
            backgroundColor: 'rgba(6, 182, 212, 0.12)',
            fill: true,
            tension: 0.4,
            borderWidth: 3,
            pointRadius: 4,
            pointBackgroundColor: '#06B6D4'
          },
          {
            label: 'Parking Spot Queries',
            data: [8, 30, 85, 140, 220, 290, 240, 310, 380, 420],
            borderColor: '#F59E0B',
            backgroundColor: 'rgba(245, 158, 11, 0.05)',
            fill: true,
            tension: 0.4,
            borderWidth: 2,
            borderDash: [5, 5],
            pointRadius: 3
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { labels: { color: '#94A3B8', font: { family: 'Plus Jakarta Sans', weight: '600' } } }
        },
        scales: {
          x: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#64748B' } },
          y: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#64748B' } }
        }
      }
    });
  }

  return { render };
})();
