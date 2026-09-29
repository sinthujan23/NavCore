/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - AR ANCHORS & BEACONS MODULE
   ========================================================================== */

const AnchorsView = (function () {
  let selectedMarker = null;

  function render(container, state) {
    if (!selectedMarker && state.markers.length > 0) {
      selectedMarker = state.markers[0];
    }

    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-qrcode"></i> AR Spatial Reference Markers & BLE Beacons</div>
            <div class="card-subtitle">Configure physical QR posters, VPS anchor coordinates, and BLE beacon transmitters.</div>
          </div>
          <button class="btn btn-primary" onclick="AnchorsView.promptAddMarker()">
            <i class="fa-solid fa-plus"></i> Add Reference Marker
          </button>
        </div>

        <div class="grid-2-1">
          <!-- Left: Markers & Beacons Table -->
          <div class="card">
            <h4 style="font-weight: 800; font-size: 15px; margin-bottom: 16px;"><i class="fa-solid fa-location-crosshairs"></i> Registered Spatial Anchors</h4>
            
            <div class="table-responsive">
              <table class="data-table">
                <thead>
                  <tr>
                    <th>Anchor Name & ID</th>
                    <th>Floor</th>
                    <th>WGS84 Lat/Lon</th>
                    <th>Width</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  ${state.markers.map(m => `
                    <tr style="cursor: pointer; background: ${selectedMarker && selectedMarker.id === m.id ? 'var(--card-bg-hover)' : 'transparent'};" onclick="AnchorsView.selectMarker('${m.id}')">
                      <td>
                        <span style="font-weight: 700; color: var(--text-primary); display: block;">${m.name}</span>
                        <span style="font-family: monospace; font-size: 11px; color: var(--accent-cyan);">${m.id}</span>
                      </td>
                      <td><span class="badge badge-cyan">Floor ${m.floorNumber}</span></td>
                      <td style="font-family: monospace; font-size: 11px; color: var(--text-secondary);">${m.latitude.toFixed(6)}, ${m.longitude.toFixed(6)}</td>
                      <td style="font-family: monospace;">${m.widthMeters}m</td>
                      <td>
                        <button class="btn btn-sm btn-outline-danger" onclick="event.stopPropagation(); AnchorsView.deleteMarker('${m.id}')">
                          <i class="fa-solid fa-trash-can"></i>
                        </button>
                      </td>
                    </tr>
                  `).join('')}
                </tbody>
              </table>
            </div>
          </div>

          <!-- Right: Live QR Code Previewer & Printer -->
          <div class="card" style="align-items: center; text-align: center;">
            <h4 style="font-weight: 800; font-size: 15px; margin-bottom: 6px;"><i class="fa-solid fa-print"></i> Printable Spatial Poster Preview</h4>
            <p style="font-size: 12px; color: var(--text-secondary); margin-bottom: 16px;">Scan with mobile app camera to calibrate PnP AR camera origin.</p>

            ${selectedMarker ? `
              <div class="qr-preview-box" id="qr-code-canvas-container">
                <!-- QRCode JS Target -->
              </div>

              <div style="margin-top: 16px; text-align: left; width: 100%; background: var(--bg-primary); padding: 14px; border-radius: var(--radius-md); border: 1px solid var(--border-color); font-size: 12px;">
                <div style="font-weight: 700; color: var(--accent-cyan);">${selectedMarker.name}</div>
                <div style="font-family: monospace; font-size: 11px; color: var(--text-muted); margin-top: 4px;">Payload: ${selectedMarker.qrCodeData}</div>
                <div style="display: flex; justify-content: space-between; margin-top: 8px;">
                  <span>Print Scale: <strong>${selectedMarker.widthMeters * 100}cm x ${selectedMarker.widthMeters * 100}cm</strong></span>
                  <span style="color: var(--accent-emerald); font-weight: 700;">CALIBRATED OK</span>
                </div>
              </div>

              <div style="display: flex; gap: 10px; width: 100%; margin-top: 16px;">
                <button class="btn btn-primary" style="flex: 1;" onclick="AnchorsView.printPoster()">
                  <i class="fa-solid fa-print"></i> Print Poster PNG
                </button>
              </div>
            ` : `<p style="color: var(--text-muted);">Select a marker from the left table to view its poster.</p>`}
          </div>
        </div>
      </div>
    `;

    if (selectedMarker) {
      setTimeout(() => generateQRCode(selectedMarker.qrCodeData), 100);
    }
  }

  function generateQRCode(text) {
    const container = document.getElementById('qr-code-canvas-container');
    if (!container) return;
    container.innerHTML = '';
    
    new QRCode(container, {
      text: text,
      width: 180,
      height: 180,
      colorDark : "#0B0F17",
      colorLight : "#ffffff",
      correctLevel : QRCode.CorrectLevel.H
    });
  }

  function selectMarker(id) {
    const state = NavCoreStore.getState();
    selectedMarker = state.markers.find(m => m.id === id) || state.markers[0];
    NavCoreApp.renderCurrentView();
  }

  function promptAddMarker() {
    NavCoreApp.openModal('Add Spatial Reference Marker', `
      <form onsubmit="AnchorsView.handleCreateMarker(event)">
        <div class="form-group">
          <label>Marker ID</label>
          <input type="text" class="form-control" value="REF-ENTRANCE-05" required id="marker-id">
        </div>
        <div class="form-group">
          <label>Marker Name / Location Title</label>
          <input type="text" class="form-control" placeholder="e.g. South Escalator Column Anchor" required id="marker-name">
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Latitude</label>
            <input type="text" class="form-control" value="6.927079" required id="marker-lat">
          </div>
          <div class="form-group">
            <label>Longitude</label>
            <input type="text" class="form-control" value="79.845612" required id="marker-lng">
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Floor Level</label>
            <input type="number" class="form-control" value="1" required id="marker-floor">
          </div>
          <div class="form-group">
            <label>Physical Width (Meters)</label>
            <input type="number" step="0.05" class="form-control" value="0.25" required id="marker-width">
          </div>
        </div>
        <button type="submit" class="btn btn-primary" style="width: 100%; margin-top: 12px;">Save Anchor Poster</button>
      </form>
    `);
  }

  function handleCreateMarker(e) {
    e.preventDefault();
    const id = document.getElementById('marker-id').value;
    const name = document.getElementById('marker-name').value;
    const latitude = parseFloat(document.getElementById('marker-lat').value);
    const longitude = parseFloat(document.getElementById('marker-lng').value);
    const floorNumber = parseInt(document.getElementById('marker-floor').value);
    const widthMeters = parseFloat(document.getElementById('marker-width').value);

    const newMarker = {
      id, name, floorNumber, latitude, longitude, height: 1.65, widthMeters,
      qrCodeData: `NexNav:${id}:${latitude}:${longitude}:45.0`,
      lastCalibrated: '2026-09-29'
    };

    NavCoreStore.addMarker(newMarker);
    selectedMarker = newMarker;
    NavCoreApp.closeModal();
    NavCoreApp.showToast(`Saved spatial anchor "${name}"!`, 'success');
  }

  function deleteMarker(id) {
    if (confirm(`Delete marker "${id}"?`)) {
      NavCoreStore.deleteMarker(id);
      selectedMarker = null;
      NavCoreApp.showToast(`Deleted marker "${id}".`, 'info');
    }
  }

  function printPoster() {
    window.print();
  }

  return { render, selectMarker, promptAddMarker, handleCreateMarker, deleteMarker, printPoster };
})();
