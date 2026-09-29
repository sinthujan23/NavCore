/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - VENUES & FLOORS VIEW MODULE
   ========================================================================== */

const MallsView = (function () {

  function render(container, state) {
    const activeBuilding = state.buildings.find(b => b.id === state.activeBuildingId) || state.buildings[0];

    container.innerHTML = `
      <!-- Venue Catalog Row -->
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-building-columns"></i> Managed Venues & Mall Network</div>
            <div class="card-subtitle">Select a venue to view or calibrate its elevation profile and spatial anchors.</div>
          </div>
          <button class="btn btn-primary" onclick="MallsView.promptAddBuilding()">
            <i class="fa-solid fa-plus"></i> Add New Venue
          </button>
        </div>

        <div class="grid-3" style="margin-top: 10px;">
          ${state.buildings.map(b => `
            <div class="card" style="cursor: pointer; border: 1.5px solid ${b.id === state.activeBuildingId ? 'var(--accent-cyan)' : 'var(--border-color)'}; background: ${b.id === state.activeBuildingId ? 'var(--card-bg-hover)' : 'var(--card-bg)'};" onclick="NavCoreStore.setActiveBuilding('${b.id}')">
              <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                <div>
                  <h4 style="font-weight: 800; font-size: 15px; color: var(--text-primary);">${b.name}</h4>
                  <p style="font-size: 12px; color: var(--text-secondary);"><i class="fa-solid fa-location-dot"></i> ${b.city}, ${b.country}</p>
                </div>
                <span class="badge ${b.id === state.activeBuildingId ? 'badge-cyan' : 'badge-slate'}">${b.id === state.activeBuildingId ? 'ACTIVE' : b.status}</span>
              </div>
              
              <div style="margin-top: 14px; display: flex; align-items: center; justify-content: space-between; font-size: 12px; border-top: 1px solid var(--border-color); padding-top: 10px;">
                <span><i class="fa-solid fa-layer-group"></i> ${b.floorCount} Floors</span>
                <span><i class="fa-solid fa-star" style="color: var(--accent-amber);"></i> ${b.rating}</span>
                <span style="font-family: monospace; color: var(--accent-cyan);">${b.packageSizeBytesMB} MB</span>
              </div>
            </div>
          `).join('')}
        </div>
      </div>

      <!-- Active Building Details & Elevation Configurator -->
      <div class="grid-2-1">
        <!-- Left: Floor Elevation Profile Table -->
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title"><i class="fa-solid fa-layer-group"></i> Floor Elevation Profile - ${activeBuilding.name}</div>
              <div class="card-subtitle">Building floor height offsets and vertical ECEF Z-elevation mapping.</div>
            </div>
            <button class="btn btn-sm btn-secondary" onclick="MallsView.promptAddFloor()">
              <i class="fa-solid fa-plus"></i> Add Floor Level
            </button>
          </div>

          <div class="table-responsive">
            <table class="data-table">
              <thead>
                <tr>
                  <th>Code</th>
                  <th>Floor Name</th>
                  <th>Height Offset (m)</th>
                  <th>Abs Elevation</th>
                  <th>POIs Count</th>
                  <th>Map Overlay</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                ${state.floors.map(f => `
                  <tr>
                    <td><span class="badge badge-cyan" style="font-family: monospace;">${f.code}</span></td>
                    <td style="font-weight: 700;">${f.name}</td>
                    <td style="font-family: monospace; color: var(--accent-amber);">${f.heightMeters.toFixed(1)} m</td>
                    <td style="font-family: monospace; color: var(--accent-emerald);">${(activeBuilding.baseElevation + (f.heightMeters - 35.0)).toFixed(1)} m ASL</td>
                    <td><span class="badge badge-slate">${f.poiCount} POIs</span></td>
                    <td><span style="font-size: 11px; color: var(--accent-blue);"><i class="fa-solid fa-file-code"></i> vector_f${f.number}.svg</span></td>
                    <td>
                      <button class="btn btn-sm btn-secondary" onclick="NavCoreApp.showToast('Floor ${f.code} vector map re-aligned.', 'info')">
                        <i class="fa-solid fa-pen"></i>
                      </button>
                    </td>
                  </tr>
                `).join('')}
              </tbody>
            </table>
          </div>
        </div>

        <!-- Right: Geodetic Anchor Calibration Box -->
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title"><i class="fa-solid fa-compass"></i> Entrance Anchor Calibration</div>
              <div class="card-subtitle">Geodetic reference anchor for PnP ECEF spatial transformation</div>
            </div>
          </div>

          <form onsubmit="MallsView.handleAnchorSave(event)">
            <div class="form-group">
              <label>Latitude (WGS84)</label>
              <input type="text" class="form-control" id="anchor-lat" value="${activeBuilding.latitude}" required>
            </div>
            <div class="form-group">
              <label>Longitude (WGS84)</label>
              <input type="text" class="form-control" id="anchor-lng" value="${activeBuilding.longitude}" required>
            </div>
            <div class="form-group">
              <label>Base Height (Altitude Meters)</label>
              <input type="number" step="0.1" class="form-control" id="anchor-height" value="${activeBuilding.baseElevation}" required>
            </div>
            <div class="form-group">
              <label>Compass True Heading (°)</label>
              <input type="number" step="0.1" class="form-control" id="anchor-heading" value="${activeBuilding.compassHeading}" required>
            </div>

            <div style="margin-top: 20px;">
              <button type="submit" class="btn btn-primary" style="width: 100%;">
                <i class="fa-solid fa-floppy-disk"></i> SAVE ANCHOR CALIBRATION
              </button>
            </div>
          </form>
        </div>
      </div>
    `;
  }

  function promptAddBuilding() {
    NavCoreApp.openModal('Add New Venue to NavCore', `
      <form onsubmit="MallsView.handleCreateBuilding(event)">
        <div class="form-group">
          <label>Venue / Mall Name</label>
          <input type="text" class="form-control" placeholder="e.g. Marina Bay Sands Plaza" required id="new-mall-name">
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>City</label>
            <input type="text" class="form-control" placeholder="Colombo" required id="new-mall-city">
          </div>
          <div class="form-group">
            <label>Country</label>
            <input type="text" class="form-control" placeholder="Sri Lanka" required id="new-mall-country">
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Latitude</label>
            <input type="text" class="form-control" value="6.9270" required id="new-mall-lat">
          </div>
          <div class="form-group">
            <label>Longitude</label>
            <input type="text" class="form-control" value="79.8456" required id="new-mall-lng">
          </div>
        </div>
        <button type="submit" class="btn btn-primary" style="width: 100%; margin-top: 12px;">Create Venue Package</button>
      </form>
    `);
  }

  function handleCreateBuilding(e) {
    e.preventDefault();
    const name = document.getElementById('new-mall-name').value;
    const city = document.getElementById('new-mall-city').value;
    const country = document.getElementById('new-mall-country').value;
    const lat = parseFloat(document.getElementById('new-mall-lat').value) || 6.9270;
    const lng = parseFloat(document.getElementById('new-mall-lng').value) || 79.8456;

    const newBuilding = {
      id: `mall-${name.toLowerCase().replace(/[^a-z0-9]/g, '-')}`,
      name: name,
      city: city,
      country: country,
      latitude: lat,
      longitude: lng,
      baseElevation: 35.0,
      compassHeading: 180.0,
      floorCount: 4,
      packageSizeBytesMB: 12.0,
      category: 'Commercial Venue',
      rating: '4.5 ★',
      status: 'ONLINE'
    };

    NavCoreStore.getState().buildings.push(newBuilding);
    NavCoreStore.setActiveBuilding(newBuilding.id);
    NavCoreApp.closeModal();
    NavCoreApp.showToast(`Venue "${name}" created and set as active!`, 'success');
  }

  function handleAnchorSave(e) {
    e.preventDefault();
    const lat = parseFloat(document.getElementById('anchor-lat').value);
    const lng = parseFloat(document.getElementById('anchor-lng').value);
    const alt = parseFloat(document.getElementById('anchor-height').value);
    const head = parseFloat(document.getElementById('anchor-heading').value);

    const state = NavCoreStore.getState();
    const b = state.buildings.find(item => item.id === state.activeBuildingId);
    if (b) {
      b.latitude = lat;
      b.longitude = lng;
      b.baseElevation = alt;
      b.compassHeading = head;
    }
    NavCoreApp.showToast('Entrance Geodetic Anchor re-calibrated successfully!', 'success');
  }

  return { render, promptAddBuilding, handleCreateBuilding, handleAnchorSave };
})();
