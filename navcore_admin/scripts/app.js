/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - MAIN APPLICATION CONTROLLER
   ========================================================================== */

const NavCoreApp = (function () {
  let currentView = 'dashboard';

  function init() {
    // 1. Check Authentication Status
    checkAuthStatus();

    // 2. Subscribe to Store Updates
    NavCoreStore.subscribe(onStoreUpdate);

    // 3. Setup Hash Router
    window.addEventListener('hashchange', handleHashChange);
    handleHashChange();

    // 4. Setup Clock Timer
    setInterval(updateClock, 1000);
    updateClock();

    // 5. Setup Mobile Sidebar Toggle
    const sidebarToggle = document.getElementById('sidebar-toggle');
    if (sidebarToggle) {
      sidebarToggle.addEventListener('click', () => {
        document.querySelector('.sidebar').classList.toggle('open');
      });
    }

    // 6. Populate Building Selector
    populateBuildingSelector();
  }

  function handleHashChange() {
    const hash = window.location.hash.replace('#', '') || 'dashboard';
    navigateTo(hash);
  }

  function navigateTo(viewName) {
    const validViews = ['dashboard', 'malls', 'shops', 'wayfinding', 'anchors', 'parking', 'emergency', 'telemetry', 'analytics', 'settings'];
    if (!validViews.includes(viewName)) viewName = 'dashboard';
    
    currentView = viewName;

    // Update Nav Active State
    document.querySelectorAll('.nav-item').forEach(item => {
      if (item.getAttribute('data-view') === viewName) {
        item.classList.add('active');
      } else {
        item.classList.remove('active');
      }
    });

    // Hide all view panels
    document.querySelectorAll('.view-panel').forEach(panel => {
      panel.classList.add('hidden');
      panel.classList.remove('active');
    });

    // Show target view panel
    const targetPanel = document.getElementById(`view-${viewName}`);
    if (targetPanel) {
      targetPanel.classList.remove('hidden');
      targetPanel.classList.add('active');
    }

    // Update Page Header Titles
    updateHeaderTitles(viewName);

    // Render View Content
    renderCurrentView();
  }

  function updateHeaderTitles(viewName) {
    const titles = {
      dashboard: { title: 'Live Operational Dashboard', sub: 'Real-time AR navigation sessions, building occupancy, and spatial sensor health.' },
      malls: { title: 'Venue & Floor Elevation Profile Manager', sub: 'Calibrate multi-building floor heights, geodetic entrance anchors, and vector maps.' },
      shops: { title: 'Shops & Spatial POI Directory', sub: 'Manage tenant locations, floor levels, geodetic coordinates, images, and operating status.' },
      wayfinding: { title: 'Indoor Wayfinding Node Graph Canvas', sub: 'Interactive node graph map editor and real-time Dijkstra shortest-path route solver.' },
      anchors: { title: 'AR Spatial Anchors & BLE Beacons', sub: 'Configure physical QR posters, VPS anchor coordinates, and BLE beacon transmitters.' },
      parking: { title: 'Smart Parking Deck Hub (Basement B1)', sub: 'Real-time parking spot matrix, ALPR scanner logs, and EV charging status.' },
      emergency: { title: 'Emergency Evacuation & Safety Control', sub: 'One-click hazard alert broadcast and automatic mobile AR route override.' },
      telemetry: { title: 'App Fleet Telemetry & Sensor Diagnostics', sub: 'Real-time mobile camera PnP pose solvers, FPS counters, and tracking modes.' },
      analytics: { title: 'Footfall & Spatial Analytics Insights', sub: 'Visitor density distribution, top search keywords, and dwell time rankings.' },
      settings: { title: 'System Settings & REST API Access Control', sub: 'Manage backend REST API keys, Mobile WebSockets sync endpoints, and backup data.' }
    };

    const t = titles[viewName] || titles.dashboard;
    document.getElementById('page-title').textContent = t.title;
    document.getElementById('page-subtitle').textContent = t.sub;
  }

  function renderCurrentView() {
    const state = NavCoreStore.getState();
    const activePanel = document.getElementById(`view-${currentView}`);
    if (!activePanel) return;

    switch (currentView) {
      case 'dashboard': DashboardView.render(activePanel, state); break;
      case 'malls': MallsView.render(activePanel, state); break;
      case 'shops': ShopsView.render(activePanel, state); break;
      case 'wayfinding': WayfindingView.render(activePanel, state); break;
      case 'anchors': AnchorsView.render(activePanel, state); break;
      case 'parking': ParkingView.render(activePanel, state); break;
      case 'emergency': EmergencyView.render(activePanel, state); break;
      case 'telemetry': TelemetryView.render(activePanel, state); break;
      case 'analytics': AnalyticsView.render(activePanel, state); break;
      case 'settings': SettingsView.render(activePanel, state); break;
    }
  }

  function onStoreUpdate(state) {
    // Sync Emergency Banner
    const banner = document.getElementById('emergency-banner');
    const badgeEmergency = document.getElementById('badge-emergency-status');
    
    if (state.emergencyActive) {
      if (banner) {
        banner.classList.remove('hidden');
        document.getElementById('emergency-banner-text').textContent = `CRITICAL ALERT: ${state.emergencyReason.toUpperCase()}`;
      }
      if (badgeEmergency) {
        badgeEmergency.textContent = 'ALARM ACTIVE';
        badgeEmergency.className = 'badge badge-rose';
      }
    } else {
      if (banner) banner.classList.add('hidden');
      if (badgeEmergency) {
        badgeEmergency.textContent = 'SAFE';
        badgeEmergency.className = 'badge badge-emerald';
      }
    }

    // Sync Badges
    const bShops = document.getElementById('badge-total-pois');
    if (bShops) bShops.textContent = state.shops.length;

    const bSessions = document.getElementById('badge-active-sessions');
    if (bSessions) bSessions.textContent = `${state.activeSessions.length} Live`;

    const occ = state.parkingSpots.filter(p => p.status === 'occupied').length;
    const pct = Math.round((occ / state.parkingSpots.length) * 100);
    const bPark = document.getElementById('badge-parking-occ');
    if (bPark) bPark.textContent = `${pct}%`;

    // Populate Selector if needed
    populateBuildingSelector();

    // Re-render
    renderCurrentView();
  }

  function populateBuildingSelector() {
    const select = document.getElementById('global-building-select');
    if (!select) return;
    const state = NavCoreStore.getState();

    select.innerHTML = state.buildings.map(b => `
      <option value="${b.id}" ${b.id === state.activeBuildingId ? 'selected' : ''}>
        ${b.name} (${b.city})
      </option>
    `).join('');
  }

  function updateClock() {
    const clockEl = document.getElementById('header-time-clock');
    if (clockEl) {
      const now = new Date();
      clockEl.textContent = now.toLocaleTimeString();
    }
  }

  // Theme Toggle
  function toggleTheme() {
    const body = document.body;
    const icon = document.getElementById('theme-icon');
    if (body.classList.contains('dark-theme')) {
      body.classList.remove('dark-theme');
      body.classList.add('light-theme');
      if (icon) icon.className = 'fa-solid fa-sun';
      NavCoreStore.getState().theme = 'light';
    } else {
      body.classList.remove('light-theme');
      body.classList.add('dark-theme');
      if (icon) icon.className = 'fa-solid fa-moon';
      NavCoreStore.getState().theme = 'dark';
    }
  }

  // Modal Controls
  function openModal(title, contentHtml, isLarge = false) {
    document.getElementById('modal-title').textContent = title;
    document.getElementById('modal-body').innerHTML = contentHtml;
    const dialog = document.querySelector('.modal-dialog');
    if (isLarge) dialog.classList.add('lg');
    else dialog.classList.remove('lg');
    document.getElementById('modal-backdrop').classList.remove('hidden');
  }

  function closeModal() {
    document.getElementById('modal-backdrop').classList.add('hidden');
  }

  function closeAllModals(e) {
    if (e.target.id === 'modal-backdrop') {
      closeModal();
    }
  }

  // Toast System
  function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    
    let iconClass = 'fa-circle-info';
    if (type === 'success') iconClass = 'fa-circle-check';
    if (type === 'error') iconClass = 'fa-triangle-exclamation';
    if (type === 'warning') iconClass = 'fa-bell';

    toast.innerHTML = `
      <i class="fa-solid ${iconClass}"></i>
      <span style="font-size: 13px; font-weight: 600;">${message}</span>
    `;

    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(100%)';
      setTimeout(() => toast.remove(), 300);
    }, 4000);
  }

  // Global Search Handler
  function handleGlobalSearch(e) {
    const val = e.target.value.trim().toLowerCase();
    const dropdown = document.getElementById('search-dropdown');
    if (!dropdown) return;

    if (val.length < 2) {
      dropdown.classList.add('hidden');
      return;
    }

    const state = NavCoreStore.getState();
    const matchingShops = state.shops.filter(s => s.name.toLowerCase().includes(val) || s.category.toLowerCase().includes(val));
    const matchingSpots = state.parkingSpots.filter(p => p.id.toLowerCase().includes(val));
    const matchingMarkers = state.markers.filter(m => m.name.toLowerCase().includes(val) || m.id.toLowerCase().includes(val));

    let html = '';
    if (matchingShops.length > 0) {
      html += `<div style="font-size: 10px; font-weight: 800; color: var(--text-muted); padding: 6px 12px;">SHOPS & POIS</div>`;
      matchingShops.slice(0, 3).forEach(s => {
        html += `<div style="padding: 8px 12px; cursor: pointer; border-bottom: 1px solid var(--border-color);" onclick="NavCoreApp.navigateTo('shops'); document.getElementById('search-dropdown').classList.add('hidden');">
          <strong style="color: var(--accent-cyan);">${s.name}</strong> - Floor ${s.floorNumber}
        </div>`;
      });
    }

    if (matchingSpots.length > 0) {
      html += `<div style="font-size: 10px; font-weight: 800; color: var(--text-muted); padding: 6px 12px;">PARKING SPOTS</div>`;
      matchingSpots.slice(0, 3).forEach(p => {
        html += `<div style="padding: 8px 12px; cursor: pointer; border-bottom: 1px solid var(--border-color);" onclick="NavCoreApp.navigateTo('parking'); document.getElementById('search-dropdown').classList.add('hidden');">
          <strong style="color: var(--accent-amber);">${p.id}</strong> - Status: ${p.status}
        </div>`;
      });
    }

    if (matchingMarkers.length > 0) {
      html += `<div style="font-size: 10px; font-weight: 800; color: var(--text-muted); padding: 6px 12px;">AR ANCHORS</div>`;
      matchingMarkers.slice(0, 2).forEach(m => {
        html += `<div style="padding: 8px 12px; cursor: pointer;" onclick="NavCoreApp.navigateTo('anchors'); document.getElementById('search-dropdown').classList.add('hidden');">
          <strong style="color: var(--accent-purple);">${m.name}</strong> (${m.id})
        </div>`;
      });
    }

    if (html === '') {
      html = `<div style="padding: 12px; font-size: 12px; color: var(--text-muted);">No matching POIs or Anchors found.</div>`;
    }

    dropdown.innerHTML = html;
    dropdown.classList.remove('hidden');
    dropdown.style.cssText = `
      position: absolute; top: 46px; left: 0; right: 0;
      background: var(--card-bg); border: 1px solid var(--border-color-light);
      border-radius: var(--radius-md); box-shadow: var(--shadow-lg); z-index: 200;
    `;
  }

  // Quick Actions Modal
  function toggleQuickActionsModal() {
    openModal('Quick Actions & System Shortcuts', `
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 14px;">
        <button class="btn btn-secondary" style="padding: 16px; flex-direction: column; gap: 8px;" onclick="NavCoreApp.closeModal(); ShopsView.promptAddShop();">
          <i class="fa-solid fa-store" style="font-size: 24px; color: var(--accent-cyan);"></i>
          <span>Add New Shop / POI</span>
        </button>
        <button class="btn btn-secondary" style="padding: 16px; flex-direction: column; gap: 8px;" onclick="NavCoreApp.closeModal(); AnchorsView.promptAddMarker();">
          <i class="fa-solid fa-qrcode" style="font-size: 24px; color: var(--accent-purple);"></i>
          <span>Add AR Spatial Anchor</span>
        </button>
        <button class="btn btn-secondary" style="padding: 16px; flex-direction: column; gap: 8px;" onclick="NavCoreApp.closeModal(); NavCoreApp.promptEmergencyTrigger();">
          <i class="fa-solid fa-bullhorn" style="font-size: 24px; color: var(--accent-rose);"></i>
          <span>Trigger Evacuation Alert</span>
        </button>
        <button class="btn btn-secondary" style="padding: 16px; flex-direction: column; gap: 8px;" onclick="NavCoreApp.closeModal(); SettingsView.exportFullBackup();">
          <i class="fa-solid fa-database" style="font-size: 24px; color: var(--accent-emerald);"></i>
          <span>Export System Backup</span>
        </button>
      </div>
    `);
  }

  function promptEmergencyTrigger() {
    navigateTo('emergency');
  }

  function deactivateEmergency() {
    NavCoreStore.setEmergency(false);
    showToast('Deactivated Emergency Evacuation Rerouting.', 'success');
  }

  function toggleNotificationsModal() {
    showToast('No new unread system notifications.', 'info');
  }

  // ==========================================================================
  // AUTHENTICATION & SESSION MANAGEMENT CONTROLLER
  // ==========================================================================

  function checkAuthStatus() {
    const isLoggedIn = NavCoreStore.isLoggedIn();
    const loginWrapper = document.getElementById('login-wrapper');
    const adminWrapper = document.querySelector('.admin-wrapper');

    if (isLoggedIn) {
      if (loginWrapper) loginWrapper.classList.add('hidden');
      if (adminWrapper) adminWrapper.classList.remove('hidden');
      updateUserProfileDisplay();
    } else {
      if (loginWrapper) loginWrapper.classList.remove('hidden');
      if (adminWrapper) adminWrapper.classList.add('hidden');
    }
  }

  function updateUserProfileDisplay() {
    const user = NavCoreStore.getUser();
    if (!user) return;
    const avatarEl = document.getElementById('header-user-avatar');
    const nameEl = document.getElementById('header-user-name');
    const roleEl = document.getElementById('header-user-role');

    if (avatarEl) avatarEl.textContent = user.avatar || 'SA';
    if (nameEl) nameEl.textContent = user.name || 'Sinthujan A.';
    if (roleEl) roleEl.textContent = user.role || 'Super Admin';
  }

  function handleLogin(e) {
    if (e) e.preventDefault();

    const emailInput = document.getElementById('login-email');
    const pwInput = document.getElementById('login-password');
    const roleSelect = document.getElementById('login-role');
    const errAlert = document.getElementById('login-error-alert');
    const btnSubmit = document.getElementById('btn-login-submit');
    const btnText = document.getElementById('btn-login-text');

    const email = emailInput ? emailInput.value.trim() : '';
    const password = pwInput ? pwInput.value.trim() : '';
    const role = roleSelect ? roleSelect.value : 'Super Admin';

    if (!email || !password) {
      if (errAlert) {
        document.getElementById('login-error-text').textContent = 'Please enter both Email and Access Key.';
        errAlert.classList.remove('hidden');
      }
      return;
    }

    if (errAlert) errAlert.classList.add('hidden');

    // Loading State Animation
    if (btnSubmit) btnSubmit.disabled = true;
    if (btnText) btnText.textContent = 'VERIFYING CREDENTIALS...';

    setTimeout(() => {
      const user = NavCoreStore.login(email, password, role);
      if (btnSubmit) btnSubmit.disabled = false;
      if (btnText) btnText.textContent = 'AUTHENTICATE & LAUNCH DASHBOARD';

      checkAuthStatus();
      renderCurrentView();
      showToast(`Welcome back, ${user.name}! Session authenticated as ${user.role}.`, 'success');
    }, 500);
  }

  function quickLogin(roleType) {
    let email = 'admin@navcore.io';
    let name = 'Sinthujan A.';
    if (roleType === 'Venue Operations Manager') {
      email = 'sarah.j@navcore.io';
      name = 'Sarah Jenkins';
    } else if (roleType === 'Security & Emergency Officer') {
      email = 'dave.m@navcore.io';
      name = 'Cmdr. Dave Miller';
    }

    const errAlert = document.getElementById('login-error-alert');
    if (errAlert) errAlert.classList.add('hidden');

    const user = NavCoreStore.login(email, 'demo123', roleType, name);
    checkAuthStatus();
    renderCurrentView();
    showToast(`Quick Login Successful! Logged in as ${user.name} (${user.role}).`, 'success');
  }

  function logout() {
    NavCoreStore.logout();
    checkAuthStatus();
    showToast('Logged out of NavCore Spatial Ops Hub.', 'info');
  }

  function togglePasswordVisibility() {
    const pwInput = document.getElementById('login-password');
    const icon = document.getElementById('pw-toggle-icon');
    if (!pwInput) return;

    if (pwInput.type === 'password') {
      pwInput.type = 'text';
      if (icon) icon.className = 'fa-solid fa-eye-slash';
    } else {
      pwInput.type = 'password';
      if (icon) icon.className = 'fa-solid fa-eye';
    }
  }

  // Initialize App when DOM is loaded
  document.addEventListener('DOMContentLoaded', init);

  return {
    checkAuthStatus,
    handleLogin,
    quickLogin,
    logout,
    togglePasswordVisibility,
    navigateTo,
    renderCurrentView,
    toggleTheme,
    openModal,
    closeModal,
    closeAllModals,
    showToast,
    handleGlobalSearch,
    toggleQuickActionsModal,
    promptEmergencyTrigger,
    deactivateEmergency,
    toggleNotificationsModal
  };
})();
