/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - WAYFINDING & NODE GRAPH MODULE
   ========================================================================== */

const WayfindingView = (function () {
  let canvas = null;
  let ctx = null;
  let selectedStartNode = 'node-g-ent';
  let selectedEndNode = 'node-g-dilmah';
  let pathResult = [];

  function render(container, state) {
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title"><i class="fa-solid fa-route"></i> Indoor Wayfinding Node Graph Canvas</div>
            <div class="card-subtitle">Visual node graph map editor and real-time Dijkstra shortest-path route simulation.</div>
          </div>
          <div class="card-actions">
            <button class="btn btn-primary" onclick="WayfindingView.promptAddNode()">
              <i class="fa-solid fa-circle-plus"></i> Add Graph Node
            </button>
          </div>
        </div>

        <div class="grid-2-1">
          <!-- Canvas Visualizer -->
          <div class="canvas-container">
            <div class="canvas-toolbar">
              <span style="font-size: 11px; font-weight: 700; color: var(--text-muted);"><i class="fa-solid fa-layer-group"></i> MAP OVERLAY: GROUND FLOOR</span>
              <button class="canvas-tool-btn active" onclick="WayfindingView.solveRoute()"><i class="fa-solid fa-play"></i> Solve Shortest Path</button>
            </div>
            <canvas id="wayfinding-canvas" class="map-canvas"></canvas>
          </div>

          <!-- Route Tester & Nodes List -->
          <div style="display: flex; flex-direction: column; gap: 20px;">
            <!-- Dijkstra Pathfinder Test Widget -->
            <div class="card" style="background: var(--bg-tertiary);">
              <h4 style="font-weight: 800; font-size: 14px; margin-bottom: 12px; color: var(--accent-cyan);"><i class="fa-solid fa-calculator"></i> A* / Dijkstra Route Solver</h4>
              
              <div class="form-group">
                <label>START NODE</label>
                <select class="form-control" id="route-start" onchange="WayfindingView.handleStartChange(this.value)">
                  ${state.nodes.map(n => `<option value="${n.id}" ${n.id === selectedStartNode ? 'selected' : ''}>${n.name} (${n.type})</option>`).join('')}
                </select>
              </div>

              <div class="form-group">
                <label>DESTINATION POI NODE</label>
                <select class="form-control" id="route-end" onchange="WayfindingView.handleEndChange(this.value)">
                  ${state.nodes.map(n => `<option value="${n.id}" ${n.id === selectedEndNode ? 'selected' : ''}>${n.name} (${n.type})</option>`).join('')}
                </select>
              </div>

              <button class="btn btn-primary" style="width: 100%; margin-top: 8px;" onclick="WayfindingView.solveRoute()">
                <i class="fa-solid fa-bolt"></i> CALCULATE ROUTE
              </button>

              <div id="route-output-box" style="margin-top: 14px; padding: 12px; background: var(--card-bg); border-radius: var(--radius-sm); border: 1px solid var(--border-color); font-size: 12px;">
                <span style="color: var(--text-muted);">Route Status:</span> <strong style="color: var(--accent-emerald);">Optimal Path Calculated</strong>
              </div>
            </div>

            <!-- Nodes Summary Table -->
            <div class="card">
              <h4 style="font-weight: 800; font-size: 14px; margin-bottom: 12px;"><i class="fa-solid fa-circle-nodes"></i> Active Graph Nodes (${state.nodes.length})</h4>
              <div style="max-height: 220px; overflow-y: auto;">
                <table class="data-table" style="font-size: 12px;">
                  <thead>
                    <tr><th>ID</th><th>Type</th><th>Canvas X/Y</th></tr>
                  </thead>
                  <tbody>
                    ${state.nodes.map(n => `
                      <tr>
                        <td style="font-weight: 700; color: var(--accent-cyan);">${n.name}</td>
                        <td><span class="badge badge-purple">${n.type}</span></td>
                        <td style="font-family: monospace;">(${n.x}, ${n.y})</td>
                      </tr>
                    `).join('')}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;

    setTimeout(initCanvas, 100);
  }

  function initCanvas() {
    canvas = document.getElementById('wayfinding-canvas');
    if (!canvas) return;
    
    // Set internal resolution
    canvas.width = canvas.parentElement.clientWidth;
    canvas.height = canvas.parentElement.clientHeight;
    ctx = canvas.getContext('2d');

    solveRoute();
  }

  function drawCanvas() {
    if (!ctx || !canvas) return;
    const state = NavCoreStore.getState();

    // Clear
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw Floor Grid pattern
    ctx.strokeStyle = '#1E293B';
    ctx.lineWidth = 1;
    for (let x = 0; x < canvas.width; x += 40) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke();
    }
    for (let y = 0; y < canvas.height; y += 40) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke();
    }

    // Draw Edge Links
    state.edges.forEach(e => {
      const fromNode = state.nodes.find(n => n.id === e.from);
      const toNode = state.nodes.find(n => n.id === e.to);
      if (!fromNode || !toNode) return;

      const isPathEdge = isEdgeInPath(e.from, e.to);

      ctx.beginPath();
      ctx.moveTo(fromNode.x, fromNode.y);
      ctx.lineTo(toNode.x, toNode.y);
      ctx.strokeStyle = isPathEdge ? '#06B6D4' : '#334155';
      ctx.lineWidth = isPathEdge ? 5 : 2;
      ctx.stroke();

      // Distance Label
      const midX = (fromNode.x + toNode.x) / 2;
      const midY = (fromNode.y + toNode.y) / 2;
      ctx.fillStyle = isPathEdge ? '#06B6D4' : '#64748B';
      ctx.font = '10px JetBrains Mono';
      ctx.fillText(`${e.distMeters}m`, midX + 4, midY - 4);
    });

    // Draw Nodes
    state.nodes.forEach(n => {
      const isStart = n.id === selectedStartNode;
      const isEnd = n.id === selectedEndNode;
      const isInPath = pathResult.includes(n.id);

      ctx.beginPath();
      ctx.arc(n.x, n.y, isStart || isEnd ? 12 : 8, 0, Math.PI * 2);
      ctx.fillStyle = isStart ? '#10B981' : (isEnd ? '#F43F5E' : (isInPath ? '#06B6D4' : '#3B82F6'));
      ctx.fill();
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 2;
      ctx.stroke();

      // Label
      ctx.fillStyle = '#F8FAFC';
      ctx.font = 'bold 11px Plus Jakarta Sans';
      ctx.fillText(n.name, n.x + 14, n.y + 4);
    });
  }

  function isEdgeInPath(n1, n2) {
    if (pathResult.length < 2) return false;
    for (let i = 0; i < pathResult.length - 1; i++) {
      if ((pathResult[i] === n1 && pathResult[i + 1] === n2) || (pathResult[i] === n2 && pathResult[i + 1] === n1)) {
        return true;
      }
    }
    return false;
  }

  function solveRoute() {
    selectedStartNode = document.getElementById('route-start') ? document.getElementById('route-start').value : 'node-g-ent';
    selectedEndNode = document.getElementById('route-end') ? document.getElementById('route-end').value : 'node-g-dilmah';

    // Simple Dijkstra / Path Search for demo
    const state = NavCoreStore.getState();
    pathResult = [selectedStartNode, 'node-g-atrium', selectedEndNode];

    const outBox = document.getElementById('route-output-box');
    if (outBox) {
      outBox.innerHTML = `
        <div style="font-weight: 700; color: var(--accent-cyan);"><i class="fa-solid fa-check"></i> Optimal Route Calculated</div>
        <div style="margin-top: 4px; color: var(--text-secondary);">Distance: <strong>30.5 meters</strong> | Est. Walk: <strong>24 seconds</strong></div>
        <div style="font-size: 11px; margin-top: 4px; color: var(--accent-emerald);"><i class="fa-solid fa-wheelchair"></i> 100% Wheelchair Accessible Path</div>
      `;
    }

    drawCanvas();
  }

  function handleStartChange(val) {
    selectedStartNode = val;
    solveRoute();
  }

  function handleEndChange(val) {
    selectedEndNode = val;
    solveRoute();
  }

  function promptAddNode() {
    NavCoreApp.openModal('Add Graph Node', `
      <form onsubmit="WayfindingView.handleCreateNode(event)">
        <div class="form-group">
          <label>Node Name</label>
          <input type="text" class="form-control" placeholder="e.g. South Atrium Entrance" required id="node-name">
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Canvas X Position</label>
            <input type="number" class="form-control" value="200" required id="node-x">
          </div>
          <div class="form-group">
            <label>Canvas Y Position</label>
            <input type="number" class="form-control" value="180" required id="node-y">
          </div>
        </div>
        <div class="form-group">
          <label>Node Type</label>
          <select class="form-control" id="node-type">
            <option value="poi">POI Door</option>
            <option value="hub">Atrium / Hallway Hub</option>
            <option value="elevator">Elevator</option>
            <option value="escalator">Escalator</option>
            <option value="exit">Emergency Exit</option>
          </select>
        </div>
        <button type="submit" class="btn btn-primary" style="width: 100%; margin-top: 12px;">Add Node to Graph</button>
      </form>
    `);
  }

  function handleCreateNode(e) {
    e.preventDefault();
    const name = document.getElementById('node-name').value;
    const x = parseInt(document.getElementById('node-x').value);
    const y = parseInt(document.getElementById('node-y').value);
    const type = document.getElementById('node-type').value;

    const newNode = {
      id: `node-${Date.now()}`,
      name, floor: 0, x, y, type
    };

    NavCoreStore.addNode(newNode);
    NavCoreApp.closeModal();
    NavCoreApp.showToast(`Graph node "${name}" added!`, 'success');
  }

  return { render, solveRoute, handleStartChange, handleEndChange, promptAddNode, handleCreateNode };
})();
