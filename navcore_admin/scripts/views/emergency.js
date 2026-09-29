/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - EMERGENCY EVACUATION MODULE
   ========================================================================== */

const EmergencyView = (function () {

  function render(container, state) {
    const activeBuilding = state.buildings.find(b => b.id === state.activeBuildingId) || state.buildings[0];

    container.innerHTML = `
      <div class="card" style="border: 2px solid ${state.emergencyActive ? 'var(--accent-rose)' : 'var(--border-color)'};">
        <div class="card-header">
          <div>
            <div class="card-title" style="color: ${state.emergencyActive ? 'var(--accent-rose)' : 'var(--text-primary)'};">
              <i class="fa-solid fa-shield-cat"></i> Emergency Evacuation & Hazard Control Center
            </div>
            <div class="card-subtitle">Real-time emergency broadcast, mobile AR route override, and crowd evacuation safety system.</div>
          </div>
          <span class="badge ${state.emergencyActive ? 'badge-rose' : 'badge-emerald'}" style="font-size: 14px; padding: 6px 12px;">
            ${state.emergencyActive ? 'EMERGENCY REROUTE ACTIVE' : 'SYSTEM STATUS: SAFE'}
          </span>
        </div>

        ${state.emergencyActive ? `
          <div style="background: rgba(244, 63, 94, 0.12); border: 1px solid var(--accent-rose); border-radius: var(--radius-md); padding: 20px; margin-bottom: 24px;">
            <div style="display: flex; align-items: center; justify-content: space-between;">
              <div>
                <h3 style="color: var(--accent-rose); font-weight: 800;"><i class="fa-solid fa-triangle-exclamation"></i> CRITICAL ALARM ACTIVE FOR ${activeBuilding.name.toUpperCase()}</h3>
                <p style="font-size: 13px; color: #FFF; margin-top: 4px;">Reason: <strong>${state.emergencyReason}</strong></p>
                <p style="font-size: 12px; color: var(--text-secondary); margin-top: 2px;">All mobile app AR Viewports are currently forcing evacuation arrows towards North & West Emergency Exits.</p>
              </div>
              <button class="btn btn-lg btn-outline-danger" onclick="NavCoreApp.deactivateEmergency()">
                <i class="fa-solid fa-shield-check"></i> DEACTIVATE EMERGENCY & RESTORE NORMAL ROUTING
              </button>
            </div>
          </div>
        ` : ''}

        <div class="grid-2">
          <!-- Emergency Hazard Trigger Box -->
          <div class="card" style="background: var(--bg-tertiary);">
            <h4 style="font-weight: 800; font-size: 15px; margin-bottom: 14px; color: var(--accent-rose);">
              <i class="fa-solid fa-bullhorn"></i> Trigger Emergency Evacuation Alert
            </h4>
            <p style="font-size: 12px; color: var(--text-secondary); margin-bottom: 16px;">
              Select an emergency hazard condition to immediately broadcast audio alerts to mobile apps and reroute AR wayfinding arrows away from danger zones.
            </p>

            <form onsubmit="EmergencyView.handleTrigger(event)">
              <div class="form-group">
                <label>Emergency Type / Reason</label>
                <select class="form-control" id="emergency-type-select">
                  <option value="Fire Alarm & Smoke Hazard - Level 2 Atrium">Fire Alarm & Smoke Hazard (Level 2 Atrium)</option>
                  <option value="Earthquake Evacuation Drill">Earthquake Evacuation Alert</option>
                  <option value="Security Lockdown & Hazard Alert">Security Lockdown / Restricted Corridor</option>
                  <option value="Power Outage & Structural Inspection">Power Outage & Structural Inspection</option>
                </select>
              </div>

              <div class="form-group">
                <label>Evacuation Reroute Strategy</label>
                <select class="form-control" id="emergency-strategy-select">
                  <option value="ALL_EXITS">Direct to All Nearest Emergency Stairwells & Exits</option>
                  <option value="AVOID_ELEVATORS">Disable Elevators & Direct to Stairwell Exits</option>
                  <option value="GROUND_ESCAPE">Direct to Ground Main Atrium Exit Gates</option>
                </select>
              </div>

              <button type="submit" class="btn btn-lg btn-danger" style="width: 100%; margin-top: 12px;">
                <i class="fa-solid fa-triangle-exclamation"></i> BROADCAST EMERGENCY REROUTE
              </button>
            </form>
          </div>

          <!-- Mobile App Broadcast Simulation Preview -->
          <div class="card">
            <h4 style="font-weight: 800; font-size: 15px; margin-bottom: 14px;">
              <i class="fa-solid fa-mobile"></i> Mobile AR Viewport Emergency Overlay Preview
            </h4>
            
            <div style="background: #0F172A; border: 2px solid var(--accent-rose); border-radius: var(--radius-lg); padding: 20px; color: #FFF; position: relative; overflow: hidden; min-height: 220px; display: flex; flex-direction: column; justify-content: space-between;">
              <div style="display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 10px;">
                <span style="font-weight: 800; font-size: 12px; color: var(--accent-rose);"><i class="fa-solid fa-bell"></i> NAVCORE EMERGENCY BROADCAST</span>
                <span style="font-size: 10px; background: rgba(244,63,94,0.3); padding: 2px 6px; border-radius: 4px;">HIGH PRIORITY PUSH</span>
              </div>

              <div style="margin: 16px 0;">
                <h4 style="font-size: 16px; font-weight: 800; color: #FFF;">EVACUATE BUILDING IMMEDIATELY</h4>
                <p style="font-size: 12px; color: #CBD5E1; margin-top: 4px;">${state.emergencyActive ? state.emergencyReason : 'Follow green glowing AR arrows to the nearest Emergency Exit Stairwell. Do not use elevators.'}</p>
              </div>

              <div style="display: flex; align-items: center; gap: 10px; background: rgba(16, 185, 129, 0.2); border: 1px solid var(--accent-emerald); padding: 10px; border-radius: var(--radius-md);">
                <i class="fa-solid fa-person-running" style="font-size: 20px; color: var(--accent-emerald);"></i>
                <div>
                  <span style="font-size: 11px; font-weight: 700; color: var(--accent-emerald); display: block;">AR EVACUATION ROUTE ACTIVE</span>
                  <span style="font-size: 10px; color: #E2E8F0;">Distance to North Exit Gate: <strong>14.2 meters</strong></span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  function handleTrigger(e) {
    e.preventDefault();
    const reason = document.getElementById('emergency-type-select').value;
    NavCoreStore.setEmergency(true, reason);
    NavCoreApp.showToast(`BROADCASTED EMERGENCY ALERT: ${reason}`, 'error');
  }

  return { render, handleTrigger };
})();
