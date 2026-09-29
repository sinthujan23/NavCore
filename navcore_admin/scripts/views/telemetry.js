/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - FLEET TELEMETRY & DIAGNOSTICS MODULE
   ========================================================================== */

const TelemetryView = (function () {

  function render(container, state) {
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-tower-broadcast"></i> Connected App Fleet Telemetry & Sensor Diagnostics</div>
            <div class="card-subtitle">Real-time mobile camera PnP pose solvers, magnetometer calibration, and AR tracking mode health.</div>
          </div>
          <button class="btn btn-secondary" onclick="NavCoreApp.showToast('Telemetry diagnostics refreshed!', 'info')">
            <i class="fa-solid fa-arrows-rotate"></i> Refresh Telemetry
          </button>
        </div>

        <div class="grid-4" style="margin-bottom: 20px;">
          <div class="card stat-card blue">
            <div class="stat-top"><span class="stat-label">Active App Sessions</span><i class="fa-solid fa-signal"></i></div>
            <div class="stat-value">${state.activeSessions.length}</div>
            <div class="stat-trend up">Live WebSockets Connected</div>
          </div>
          <div class="card stat-card emerald">
            <div class="stat-top"><span class="stat-label">Avg PnP Camera FPS</span><i class="fa-solid fa-gauge-high"></i></div>
            <div class="stat-value">59.2</div>
            <div class="stat-trend up">Smooth AR Render</div>
          </div>
          <div class="card stat-card cyan">
            <div class="stat-top"><span class="stat-label">VPS Anchor Precision</span><i class="fa-solid fa-crosshairs"></i></div>
            <div class="stat-value">0.12m</div>
            <div class="stat-trend up">Sub-meter Pose Lock</div>
          </div>
          <div class="card stat-card purple">
            <div class="stat-top"><span class="stat-label">System API Uptime</span><i class="fa-solid fa-server"></i></div>
            <div class="stat-value">99.98%</div>
            <div class="stat-trend up">Zero Downtime</div>
          </div>
        </div>

        <!-- Detailed Mobile App Sessions Table -->
        <div class="table-responsive">
          <table class="data-table">
            <thead>
              <tr>
                <th>Session ID</th>
                <th>Device Model</th>
                <th>Tracking Mode</th>
                <th>Current Floor</th>
                <th>Geodetic ECEF Coordinates</th>
                <th>Battery</th>
                <th>FPS</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              ${state.activeSessions.map(sess => `
                <tr>
                  <td style="font-family: monospace; font-weight: 700; color: var(--accent-cyan);">${sess.id}</td>
                  <td style="font-weight: 700;">${sess.device}</td>
                  <td><span class="badge badge-purple">${sess.trackingEngine}</span></td>
                  <td><span class="badge badge-cyan">${sess.floor}</span></td>
                  <td style="font-family: monospace; font-size: 11px;">Lat: ${sess.lat.toFixed(6)}, Lon: ${sess.lon.toFixed(6)}</td>
                  <td>${sess.battery}</td>
                  <td><span style="color: var(--accent-emerald); font-weight: 700;">${sess.fps} FPS</span></td>
                  <td><span class="badge badge-emerald">${sess.status}</span></td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `;
  }

  return { render };
})();
