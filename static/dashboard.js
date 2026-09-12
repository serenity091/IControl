const $ = id => document.getElementById(id);
const colors = ['#315b48', '#55719a', '#a77544', '#866795'];
let config, selected;
const empty = document.createElement('p'); empty.className = 'subtle'; empty.textContent = 'No players yet. Scan the QR code to connect a phone.'; $('players').append(empty);
for (let i = 1; i <= 4; i++) {
  const row = document.createElement('div');
  row.className = 'player-row'; row.id = `player-${i}`;
  row.style.setProperty('--player', colors[i - 1]);
  row.innerHTML = `<span class="player-number">${i}</span><div class="player-info"><div class="player-name">Player ${i}</div><div class="player-description">Waiting for a phone</div></div><span class="player-pill">AVAILABLE</span><button class="release" hidden>Release</button>`;
  row.querySelector('button').onclick = async () => {
    try {
      const response = await fetch(`/api/players/${i}/release`, {method: 'POST', headers: {'X-Admin-Token': config.adminToken}});
      if (!response.ok) throw new Error('Could not release player. Reload the dashboard and try again.');
      await poll();
    } catch (error) { $('notice').hidden = false; $('notice').textContent = error.message; }
  };
  $('players').append(row);
}
function update(status) {
  $('server-state').textContent = status.error ? 'Driver needs attention' : status.mode === 'preview' ? 'Preview mode · no output' : 'Server running';
  $('server-dot').className = `status-dot${status.error ? ' error' : ''}`;
  $('notice').hidden = !status.error && status.mode !== 'preview';
  $('notice').textContent = status.error || 'Preview mode: phone inputs are visible here, but no virtual controllers are connected to Windows. Restart without --simulate to play.';
  const connectedCount = status.players.filter(p => p.connected).length;
  $('player-count').textContent = `${connectedCount} connected`;
  empty.hidden = status.players.some(p => p.connected || p.reserved);
  status.players.forEach(player => {
    const row = $(`player-${player.player}`);
    row.hidden = !player.connected && !player.reserved;
    row.classList.toggle('connected', player.connected);
    row.querySelector('.player-name').textContent = player.connected || player.reserved ? `${player.name || 'Phone'} · Player ${player.player}` : `Player ${player.player}`;
    const inputs = [...player.state.buttons];
    if (player.state.zl) inputs.push('ZL'); if (player.state.zr) inputs.push('ZR');
    if (Math.abs(player.state.lx) + Math.abs(player.state.ly) > .05) inputs.push('Left stick');
    if (Math.abs(player.state.rx) + Math.abs(player.state.ry) > .05) inputs.push('Right stick');
    row.querySelector('.player-description').textContent = player.connected ? (inputs.join(' + ') || 'Connected · ready to play') : player.reserved ? 'Reconnecting · slot held for 15 seconds' : 'Waiting for a phone';
    row.querySelector('.player-pill').hidden = player.connected || player.reserved;
    row.querySelector('button').hidden = !player.connected && !player.reserved;
  });
}
function selectAddress() {
  selected = config.addresses.find(a => a.ip === $('network').value);
  $('qr').src = `/api/qr?ip=${encodeURIComponent(selected.ip)}`;
  $('address').textContent = new URL(selected.url).host;
  $('test-controller').href = `/play${new URL(selected.url).hash}`;
}
$('network').onchange = selectAddress;
$('copy').onclick = async () => {
  try { await navigator.clipboard.writeText(selected.url); $('copy').textContent = '✓'; setTimeout(() => $('copy').textContent = '⧉', 1600); }
  catch { $('notice').hidden = false; $('notice').textContent = `Pairing link: ${selected.url}`; }
};
async function poll() {
  try {
    const r = await fetch('/api/status'); if (!r.ok) throw new Error();
    const status = await r.json();
    if (!config || config.instance !== status.instance) await loadConfig();
    update(status);
  }
  catch { $('server-state').textContent = 'Server offline'; $('server-dot').className = 'status-dot error'; }
}
async function loadConfig() {
    const r = await fetch('/api/bootstrap'); if (!r.ok) throw new Error('Open this dashboard on the laptop at localhost.');
    config = await r.json();
    $('network').replaceChildren();
    config.addresses.forEach((address, i) => { const option = new Option(`${address.ip}${i === 0 ? ' · recommended' : ''}`, address.ip); $('network').add(option); });
    selectAddress(); update(config);
}
async function start() {
  try {
    await loadConfig();
  } catch (error) { $('notice').hidden = false; $('notice').textContent = error.message; }
  setInterval(poll, 500);
}
start();
