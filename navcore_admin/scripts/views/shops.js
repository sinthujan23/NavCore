/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - SHOPS & POI DIRECTORY VIEW MODULE
   ========================================================================== */

const ShopsView = (function () {
  let selectedCategory = 'ALL';
  let selectedFloorFilter = 'ALL';
  let searchQuery = '';

  function render(container, state) {
    let filteredShops = state.shops.filter(s => {
      const matchCat = (selectedCategory === 'ALL' || s.category === selectedCategory);
      const matchFloor = (selectedFloorFilter === 'ALL' || s.floorNumber.toString() === selectedFloorFilter);
      const matchQuery = searchQuery === '' || 
        s.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
        s.id.toLowerCase().includes(searchQuery.toLowerCase()) ||
        s.description.toLowerCase().includes(searchQuery.toLowerCase());
      return matchCat && matchFloor && matchQuery;
    });

    const categories = ['ALL', 'DINING & CAFES', 'FASHION & APPAREL', 'TECH & ELECTRONICS', 'SERVICES', 'ENTERTAINMENT', 'HEALTH & BEAUTY'];

    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-store"></i> Tenant Shops & Spatial POI Directory</div>
            <div class="card-subtitle">Manage mall tenants, POI geodetic locations, images, floor levels, and open status.</div>
          </div>
          <div class="card-actions">
            <button class="btn btn-secondary" onclick="ShopsView.exportJSON()">
              <i class="fa-solid fa-file-export"></i> Export JSON
            </button>
            <button class="btn btn-primary" onclick="ShopsView.promptAddShop()">
              <i class="fa-solid fa-plus"></i> Add New POI / Shop
            </button>
          </div>
        </div>

        <!-- Filter Controls Row -->
        <div style="display: flex; gap: 16px; align-items: center; margin-bottom: 20px; flex-wrap: wrap; background: var(--bg-primary); padding: 14px; border-radius: var(--radius-md); border: 1px solid var(--border-color);">
          <div style="flex: 1; min-width: 220px;">
            <input type="text" class="form-control" placeholder="Filter by shop name or ID..." value="${searchQuery}" onkeyup="ShopsView.handleSearch(this.value)">
          </div>

          <div style="display: flex; gap: 10px; align-items: center;">
            <label style="font-size: 11px; font-weight: 700; color: var(--text-muted);">CATEGORY:</label>
            <select class="form-control" onchange="ShopsView.handleCategoryFilter(this.value)">
              ${categories.map(cat => `<option value="${cat}" ${selectedCategory === cat ? 'selected' : ''}>${cat}</option>`).join('')}
            </select>
          </div>

          <div style="display: flex; gap: 10px; align-items: center;">
            <label style="font-size: 11px; font-weight: 700; color: var(--text-muted);">FLOOR:</label>
            <select class="form-control" onchange="ShopsView.handleFloorFilter(this.value)">
              <option value="ALL">ALL FLOORS</option>
              <option value="-1" ${selectedFloorFilter === '-1' ? 'selected' : ''}>Basement 1 (B1)</option>
              <option value="0" ${selectedFloorFilter === '0' ? 'selected' : ''}>Ground Floor (G)</option>
              <option value="1" ${selectedFloorFilter === '1' ? 'selected' : ''}>Level 1 (L1)</option>
              <option value="2" ${selectedFloorFilter === '2' ? 'selected' : ''}>Level 2 (L2)</option>
              <option value="3" ${selectedFloorFilter === '3' ? 'selected' : ''}>Level 3 (L3)</option>
              <option value="4" ${selectedFloorFilter === '4' ? 'selected' : ''}>Level 4 (L4)</option>
            </select>
          </div>
        </div>

        <!-- Directory Table -->
        <div class="table-responsive">
          <table class="data-table">
            <thead>
              <tr>
                <th>Shop Image & Details</th>
                <th>Category</th>
                <th>Floor</th>
                <th>Coordinates (Lat / Lon)</th>
                <th>Status</th>
                <th>Rating</th>
                <th style="text-align: right;">Actions</th>
              </tr>
            </thead>
            <tbody>
              ${filteredShops.length > 0 ? filteredShops.map(s => `
                <tr>
                  <td>
                    <div class="shop-cell-info">
                      <img src="${s.imageUrl}" class="table-shop-img" alt="${s.name}" onerror="this.src='https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=100'">
                      <div>
                        <span class="shop-cell-title">${s.name}</span>
                        <span class="shop-cell-sub">ID: ${s.id}</span>
                      </div>
                    </div>
                  </td>
                  <td><span class="badge badge-purple">${s.category}</span></td>
                  <td><span class="badge badge-cyan" style="font-family: monospace;">Floor ${s.floorNumber}</span></td>
                  <td style="font-family: monospace; font-size: 11px; color: var(--text-secondary);">
                    ${s.latitude.toFixed(6)}, ${s.longitude.toFixed(6)} (${s.height}m)
                  </td>
                  <td>
                    <span class="badge ${s.openStatus === 'OPEN NOW' || s.openStatus === '24/7' ? 'badge-emerald' : 'badge-amber'}">${s.openStatus}</span>
                  </td>
                  <td><span style="font-weight: 700; color: var(--accent-amber);"><i class="fa-solid fa-star"></i> ${s.rating}</span></td>
                  <td style="text-align: right;">
                    <button class="btn btn-sm btn-secondary" onclick="ShopsView.promptEditShop('${s.id}')" title="Edit Shop">
                      <i class="fa-solid fa-pen-to-square"></i>
                    </button>
                    <button class="btn btn-sm btn-outline-danger" onclick="ShopsView.deleteShop('${s.id}')" title="Delete POI">
                      <i class="fa-solid fa-trash-can"></i>
                    </button>
                  </td>
                </tr>
              `).join('') : `
                <tr>
                  <td colspan="7" style="text-align: center; padding: 40px; color: var(--text-muted);">
                    <i class="fa-solid fa-store-slash" style="font-size: 32px; margin-bottom: 12px; display: block;"></i>
                    No shops match the selected filters.
                  </td>
                </tr>
              `}
            </tbody>
          </table>
        </div>
      </div>
    `;
  }

  function handleSearch(val) {
    searchQuery = val;
    NavCoreApp.renderCurrentView();
  }

  function handleCategoryFilter(val) {
    selectedCategory = val;
    NavCoreApp.renderCurrentView();
  }

  function handleFloorFilter(val) {
    selectedFloorFilter = val;
    NavCoreApp.renderCurrentView();
  }

  function promptAddShop() {
    NavCoreApp.openModal('Add New Shop / POI', getShopFormHtml());
  }

  function promptEditShop(shopId) {
    const shop = NavCoreStore.getState().shops.find(s => s.id === shopId);
    if (!shop) return;
    NavCoreApp.openModal(`Edit Shop: ${shop.name}`, getShopFormHtml(shop));
  }

  function getShopFormHtml(shop = null) {
    const isEdit = shop !== null;
    return `
      <form onsubmit="ShopsView.handleSaveShop(event, '${isEdit ? shop.id : ''}')">
        <div class="form-row">
          <div class="form-group">
            <label>Shop ID</label>
            <input type="text" class="form-control" id="shop-id" value="${isEdit ? shop.id : 'poi-g-' + Math.floor(10 + Math.random() * 90)}" ${isEdit ? 'readonly' : ''} required>
          </div>
          <div class="form-group">
            <label>Shop / POI Name</label>
            <input type="text" class="form-control" id="shop-name" value="${isEdit ? shop.name : ''}" placeholder="e.g. Dilmah Tea Lounge" required>
          </div>
        </div>

        <div class="form-row">
          <div class="form-group">
            <label>Category</label>
            <select class="form-control" id="shop-category">
              <option value="DINING & CAFES" ${isEdit && shop.category === 'DINING & CAFES' ? 'selected' : ''}>DINING & CAFES</option>
              <option value="FASHION & APPAREL" ${isEdit && shop.category === 'FASHION & APPAREL' ? 'selected' : ''}>FASHION & APPAREL</option>
              <option value="TECH & ELECTRONICS" ${isEdit && shop.category === 'TECH & ELECTRONICS' ? 'selected' : ''}>TECH & ELECTRONICS</option>
              <option value="SERVICES" ${isEdit && shop.category === 'SERVICES' ? 'selected' : ''}>SERVICES</option>
              <option value="ENTERTAINMENT" ${isEdit && shop.category === 'ENTERTAINMENT' ? 'selected' : ''}>ENTERTAINMENT</option>
              <option value="HEALTH & BEAUTY" ${isEdit && shop.category === 'HEALTH & BEAUTY' ? 'selected' : ''}>HEALTH & BEAUTY</option>
            </select>
          </div>
          <div class="form-group">
            <label>Floor Level</label>
            <select class="form-control" id="shop-floor">
              <option value="-1" ${isEdit && shop.floorNumber === -1 ? 'selected' : ''}>Basement 1 (B1)</option>
              <option value="0" ${isEdit && shop.floorNumber === 0 ? 'selected' : ''}>Ground Floor (G)</option>
              <option value="1" ${isEdit && shop.floorNumber === 1 ? 'selected' : ''}>Level 1 (L1)</option>
              <option value="2" ${isEdit && shop.floorNumber === 2 ? 'selected' : ''}>Level 2 (L2)</option>
              <option value="3" ${isEdit && shop.floorNumber === 3 ? 'selected' : ''}>Level 3 (L3)</option>
              <option value="4" ${isEdit && shop.floorNumber === 4 ? 'selected' : ''}>Level 4 (L4)</option>
            </select>
          </div>
        </div>

        <div class="form-row">
          <div class="form-group">
            <label>Latitude (WGS84)</label>
            <input type="text" class="form-control" id="shop-lat" value="${isEdit ? shop.latitude : '6.927079'}" required>
          </div>
          <div class="form-group">
            <label>Longitude (WGS84)</label>
            <input type="text" class="form-control" id="shop-lng" value="${isEdit ? shop.longitude : '79.845612'}" required>
          </div>
        </div>

        <div class="form-row">
          <div class="form-group">
            <label>Elevation Height (m)</label>
            <input type="number" step="0.1" class="form-control" id="shop-height" value="${isEdit ? shop.height : '35.0'}" required>
          </div>
          <div class="form-group">
            <label>Open Status</label>
            <select class="form-control" id="shop-status">
              <option value="OPEN NOW" ${isEdit && shop.openStatus === 'OPEN NOW' ? 'selected' : ''}>OPEN NOW</option>
              <option value="24/7" ${isEdit && shop.openStatus === '24/7' ? 'selected' : ''}>24/7</option>
              <option value="CLOSED" ${isEdit && shop.openStatus === 'CLOSED' ? 'selected' : ''}>CLOSED</option>
              <option value="UNDER RENOVATION" ${isEdit && shop.openStatus === 'UNDER RENOVATION' ? 'selected' : ''}>UNDER RENOVATION</option>
            </select>
          </div>
        </div>

        <div class="form-group">
          <label>Image URL</label>
          <input type="text" class="form-control" id="shop-img" value="${isEdit ? shop.imageUrl : ''}" placeholder="https://images.unsplash.com/photo-..." required>
        </div>

        <div class="form-group">
          <label>Description & Promotional Info</label>
          <textarea class="form-control" id="shop-desc" rows="3" placeholder="Brief description for mobile AR viewport info card...">${isEdit ? shop.description : ''}</textarea>
        </div>

        <button type="submit" class="btn btn-primary" style="width: 100%; margin-top: 12px;">
          ${isEdit ? 'Update Shop POI' : 'Save New Shop POI'}
        </button>
      </form>
    `;
  }

  function handleSaveShop(e, editId) {
    e.preventDefault();
    const id = document.getElementById('shop-id').value;
    const name = document.getElementById('shop-name').value;
    const category = document.getElementById('shop-category').value;
    const floorNumber = parseInt(document.getElementById('shop-floor').value);
    const latitude = parseFloat(document.getElementById('shop-lat').value);
    const longitude = parseFloat(document.getElementById('shop-lng').value);
    const height = parseFloat(document.getElementById('shop-height').value);
    const openStatus = document.getElementById('shop-status').value;
    const imageUrl = document.getElementById('shop-img').value;
    const description = document.getElementById('shop-desc').value;

    const shopData = {
      id, name, category, floorNumber, rating: 4.8, latitude, longitude, height, openStatus, imageUrl, description
    };

    if (editId) {
      NavCoreStore.updateShop(editId, shopData);
      NavCoreApp.showToast(`Updated "${name}" successfully!`, 'success');
    } else {
      NavCoreStore.addShop(shopData);
      NavCoreApp.showToast(`Added "${name}" to shop directory!`, 'success');
    }

    NavCoreApp.closeModal();
  }

  function deleteShop(id) {
    if (confirm(`Are you sure you want to delete POI "${id}"?`)) {
      NavCoreStore.deleteShop(id);
      NavCoreApp.showToast(`Deleted POI "${id}".`, 'info');
    }
  }

  function exportJSON() {
    const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(NavCoreStore.getState().shops, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute("href", dataStr);
    downloadAnchor.setAttribute("download", "navcore_shops_directory.json");
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();
    NavCoreApp.showToast('Downloaded navcore_shops_directory.json!', 'success');
  }

  return { render, handleSearch, handleCategoryFilter, handleFloorFilter, promptAddShop, promptEditShop, handleSaveShop, deleteShop, exportJSON };
})();
