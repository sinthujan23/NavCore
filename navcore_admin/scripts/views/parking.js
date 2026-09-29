/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - SMART PARKING DECK MODULE
   ========================================================================== */

const ParkingView = (function () {
  let filterType = 'ALL';

  function render(container, state) {
    const total = state.parkingSpots.length;
    const occupied = state.parkingSpots.filter(p => p.status === 'occupied').length;
    const vacant = state.parkingSpots.filter(p => p.status === 'vacant').length;
    const evCount = state.parkingSpots.filter(p => p.type === 'ev').length;

    let filteredSpots = state.parkingSpots.filter(p => {
      if (filterType === 'VACANT') return p.status === 'vacant';
      if (filterType === 'OCCUPIED') return p.status === 'occupied';
      if (filterType === 'EV') return p.type === 'ev';
      return true;
    });

    container.innerHTML = `
      <!-- Top Parking Deck Stats -->
      <div class="grid-4">
        <div class="card stat-card emerald">
          <div class="stat-top">
            <span class="stat-label">Vacant Parking Spots</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-square-check"></i></div>
          </div>
          <div class="stat-value">${vacant}</div>
          <div class="stat-trend up"><i class="fa-solid fa-car"></i> Ready for incoming vehicles</div>
        </div>

        <div class="card stat-card rose">
          <div class="stat-top">
            <span class="stat-label">Occupied Spots</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-car-side"></i></div>
          </div>
          <div class="stat-value">${occupied}</div>
          <div class="stat-trend neutral"><i class="fa-solid fa-clock"></i> Avg dwell time: 1.8 hrs</div>
        </div>

        <div class="card stat-card cyan">
          <div class="stat-top">
            <span class="stat-label">120kW EV Chargers</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-charging-station"></i></div>
          </div>
          <div class="stat-value">${evCount}</div>
          <div class="stat-trend up"><i class="fa-solid fa-bolt"></i> High-speed DC Chargers active</div>
        </div>

        <div class="card stat-card amber">
          <div class="stat-top">
            <span class="stat-label">Today's Parking Revenue</span>
            <div class="stat-icon-wrapper"><i class="fa-solid fa-money-bill-wave"></i></div>
          </div>
          <div class="stat-value">LKR 48,500</div>
          <div class="stat-trend up"><i class="fa-solid fa-arrow-trend-up"></i> +18% vs yesterday</div>
        </div>
      </div>

      <!-- Main Parking Deck Matrix -->
      <div class="grid-2-1">
        <!-- Left: Interactive Parking Matrix Grid -->
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title"><i class="fa-solid fa-square-parking"></i> Basement 1 Parking Matrix (40 Spots)</div>
              <div class="card-subtitle">Click any parking spot to toggle status (Vacant / Occupied / Reserved).</div>
            </div>
            <div style="display: flex; gap: 8px;">
              <button class="btn btn-sm ${filterType === 'ALL' ? 'btn-primary' : 'btn-secondary'}" onclick="ParkingView.setFilter('ALL')">ALL</button>
              <button class="btn btn-sm ${filterType === 'VACANT' ? 'btn-primary' : 'btn-secondary'}" onclick="ParkingView.setFilter('VACANT')">VACANT</button>
              <button class="btn btn-sm ${filterType === 'OCCUPIED' ? 'btn-primary' : 'btn-secondary'}" onclick="ParkingView.setFilter('OCCUPIED')">OCCUPIED</button>
              <button class="btn btn-sm ${filterType === 'EV' ? 'btn-primary' : 'btn-secondary'}" onclick="ParkingView.setFilter('EV')">EV FAST-CHARGE</button>
            </div>
          </div>

          <div class="parking-matrix-container">
            ${filteredSpots.map(s => `
              <div class="parking-spot-card ${s.type === 'ev' ? 'ev' : s.status}" onclick="NavCoreStore.toggleParkingSpot('${s.id}')" title="Click to toggle status for spot ${s.id}">
                <div class="spot-id">${s.id}</div>
                <i class="fa-solid ${s.type === 'ev' ? 'fa-charging-station' : (s.status === 'occupied' ? 'fa-car' : 'fa-square')}"></i>
                <span class="spot-status-lbl">${s.type === 'ev' ? 'EV 120kW' : s.status}</span>
                ${s.licensePlate ? `<span style="font-family: monospace; font-size: 9px; color: var(--accent-rose); font-weight: 700;">${s.licensePlate}</span>` : ''}
              </div>
            `).join('')}
          </div>
        </div>

        <!-- Right: ALPR Automatic License Plate Recognition Log -->
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title"><i class="fa-solid fa-camera"></i> ALPR Camera Feed Log</div>
              <div class="card-subtitle">Automatic License Plate Recognition entry scanner log</div>
            </div>
          </div>

          <div style="max-height: 420px; overflow-y: auto;">
            <table class="data-table" style="font-size: 12px;">
              <thead>
                <tr>
                  <th>Plate & Spot</th>
                  <th>Vehicle Details</th>
                  <th>Entry Time</th>
                  <th>Fee</th>
                </tr>
              </thead>
              <tbody>
                ${state.alprLogs.map(log => `
                  <tr>
                    <td>
                      <span style="font-family: monospace; font-weight: 800; color: var(--accent-cyan); display: block;">${log.plate}</span>
                      <span class="badge badge-slate">${log.spotId}</span>
                    </td>
                    <td style="font-weight: 600;">${log.vehicle}</td>
                    <td style="color: var(--text-muted); font-size: 11px;">${log.entryTime}</td>
                    <td style="font-family: monospace; font-weight: 700; color: var(--accent-emerald);">LKR ${log.feeLKR}</td>
                  </tr>
                `).join('')}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;
  }

  function setFilter(type) {
    filterType = type;
    NavCoreApp.renderCurrentView();
  }

  return { render, setFilter };
})();
