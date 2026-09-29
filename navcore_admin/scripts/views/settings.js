/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - SYSTEM & API SETTINGS MODULE
   ========================================================================== */

const SettingsView = (function () {

  function render(container, state) {
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-sliders"></i> System Settings & API Access Control</div>
            <div class="card-subtitle">Manage backend REST API keys, Mobile WebSockets sync endpoints, and admin roles.</div>
          </div>
          <button class="btn btn-primary" onclick="SettingsView.promptGenerateKey()">
            <i class="fa-solid fa-key"></i> Generate API Key
          </button>
        </div>

        <div class="grid-2-1">
          <!-- API Keys Table -->
          <div class="card">
            <h4 style="font-weight: 800; font-size: 15px; margin-bottom: 14px;"><i class="fa-solid fa-code"></i> Active REST API Keys (NexNav.io API v2.4)</h4>
            <div class="table-responsive">
              <table class="data-table">
                <thead>
                  <tr>
                    <th>Key Name</th>
                    <th>Secret Key Token</th>
                    <th>Created Date</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  ${state.apiKeys.map(k => `
                    <tr>
                      <td style="font-weight: 700;">${k.name}</td>
                      <td style="font-family: monospace; color: var(--accent-cyan);">${k.key}</td>
                      <td style="color: var(--text-muted); font-size: 11px;">${k.created}</td>
                      <td><span class="badge badge-emerald">${k.status}</span></td>
                    </tr>
                  `).join('')}
                </tbody>
              </table>
            </div>
          </div>

          <!-- System Backup & Controls -->
          <div class="card" style="background: var(--bg-tertiary);">
            <h4 style="font-weight: 800; font-size: 15px; margin-bottom: 14px;"><i class="fa-solid fa-database"></i> System Data Backup & Export</h4>
            <p style="font-size: 12px; color: var(--text-secondary); margin-bottom: 16px;">
              Export full spatial venue catalog, POI geodetic locations, and node graphs to a single backup package.
            </p>

            <button class="btn btn-primary" style="width: 100%; margin-bottom: 10px;" onclick="SettingsView.exportFullBackup()">
              <i class="fa-solid fa-download"></i> EXPORT FULL SYSTEM BACKUP (.JSON)
            </button>

            <div style="border-top: 1px solid var(--border-color); padding-top: 16px; margin-top: 16px;">
              <h5 style="font-weight: 700; font-size: 13px; margin-bottom: 8px;">REST API Base URL</h5>
              <input type="text" class="form-control" value="https://api.NexNav.io/v1" readonly>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  function promptGenerateKey() {
    const keyName = prompt("Enter a name for the new API Key:", "Mobile App Client Production Key");
    if (keyName) {
      const newKey = {
        id: `key-gen-${Date.now()}`,
        name: keyName,
        key: `nx_live_${Math.random().toString(36).substring(2, 12)}${Math.random().toString(36).substring(2, 8)}`,
        created: new Date().toISOString().split('T')[0],
        status: 'ACTIVE'
      };
      NavCoreStore.getState().apiKeys.push(newKey);
      NavCoreApp.renderCurrentView();
      NavCoreApp.showToast(`Generated API Key: ${newKey.key}`, 'success');
    }
  }

  function exportFullBackup() {
    const state = NavCoreStore.getState();
    const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(state, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute("href", dataStr);
    downloadAnchor.setAttribute("download", "navcore_full_system_backup.json");
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();
    NavCoreApp.showToast('Downloaded navcore_full_system_backup.json!', 'success');
  }

  return { render, promptGenerateKey, exportFullBackup };
})();
