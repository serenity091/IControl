const $ = id => document.getElementById(id);
const surface = $('controller');
const colors = ['#315b48', '#55719a', '#a77544', '#866795'];
const definitions = [
  ['L','LB','shoulder',12,13,.9], ['ZL','LT','shoulder',26,13,.9],
  ['ZR','RT','shoulder',74,13,.9], ['R','RB','shoulder',88,13,.9],
  ['MINUS','−','system',44,20,.5], ['PLUS','+','system',56,20,.5],
  ['LS','L','stick',16,44,1.7], ['RS','R','stick',67,75,1.7],
  ['UP','▲','dpad',30,61,.65], ['DOWN','▼','dpad',30,87,.65],
  ['LEFT','◀','dpad',25,74,.65], ['RIGHT','▶','dpad',35,74,.65],
  ['Y','Y','face',84,30,.85], ['B','B','face',90,47,.85],
  ['A','A','face',84,64,.85], ['X','X','face',78,47,.85],
  ['L3','L3','system',12,85,.55], ['R3','R3','system',89,85,.55],
  ['HOME','⌂','system',50,80,.5],
];
const descriptions = {L:'LB',R:'RB',ZL:'LT',ZR:'RT',LS:'Left stick', RS:'Right stick', L3:'Left stick click', R3:'Right stick click', MINUS:'Back', PLUS:'Start', HOME:'Home', UP:'D-pad up', DOWN:'D-pad down', LEFT:'D-pad left', RIGHT:'D-pad right'};
const storage = {
  get(key, fallback) { try { return localStorage.getItem(key) ?? fallback; } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem(key, value); return true; } catch { return false; } }
};
let key = new URLSearchParams(location.hash.slice(1)).get('key');
try { if (key) sessionStorage.setItem('icontrol-key', key); else key = sessionStorage.getItem('icontrol-key'); } catch {}
// Keep the pairing secret out of history and requests once this tab has it.
if (key) history.replaceState(null, '', location.pathname);
let client = storage.get('icontrol-device', '');
if (!client) { const bytes = new Uint8Array(16); crypto.getRandomValues(bytes); client = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join(''); storage.set('icontrol-device', client); }
$('name').value = storage.get('icontrol-name', '');
let ws, connected = false, reconnectTimer, fatal = false, retryDelay = 800, editing = false, selected = null;
let orientation, layout, unit, dirty = true, lastSent = 0, wakeLock;
let inputEpoch = 0, lastTick = performance.now(), surfaceSize = '', activeTouches = [];
const pointers = new Map();
const elements = new Map();
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
function defaults() {
  const result = Object.fromEntries(definitions.map(([id,, ,x,y]) => [id,{x,y,scale:1}]));
  if (orientation === 'portrait') {
    const positions = {L:[14,9],ZL:[35,9],ZR:[65,9],R:[86,9],MINUS:[43,21],PLUS:[57,21],LS:[24,36],RS:[73,71],UP:[25,64.5],DOWN:[25,75.5],LEFT:[15,70],RIGHT:[35,70],Y:[75,29],B:[88,36],A:[75,43],X:[62,36],L3:[17,91],R3:[84,91],HOME:[50,91]};
    Object.entries(positions).forEach(([id,[x,y]]) => Object.assign(result[id],{x,y}));
  }
  return result;
}
function loadLayout() {
  layout = defaults();
  try {
    const saved = JSON.parse(storage.get(`icontrol-layout-v2-${orientation}`, 'null'));
    if (saved) for (const [id, value] of Object.entries(saved)) {
      if (layout[id] && value && [value.x,value.y,value.scale].every(Number.isFinite))
        layout[id] = {x:clamp(value.x,0,100),y:clamp(value.y,0,100),scale:clamp(value.scale,.6,1.6)};
    }
  } catch {}
}
function saveLayout() {
  if (!storage.set(`icontrol-layout-v2-${orientation}`, JSON.stringify(layout))) $('play-hint').textContent = 'Browser storage unavailable · layout lasts this session';
}
function render() {
  const w = surface.clientWidth, h = surface.clientHeight;
  if (!w || !h) return;
  unit = orientation === 'portrait' ? Math.min(w/7, h/7) : Math.min(w/12, h/4.8);
  surface.style.setProperty('--unit', `${unit}px`);
  definitions.forEach(([id,,, , ,size]) => {
    const el = elements.get(id), p = layout[id];
    el.style.setProperty('--size',size*p.scale);
    const width = unit*size*p.scale*(el.classList.contains('shoulder')?1.55:1);
    const height = unit*size*p.scale*(el.classList.contains('shoulder')?.62:1);
    p.x = clamp(p.x, (width/2+5)/w*100, 100-(width/2+5)/w*100);
    p.y = clamp(p.y, (height/2+5)/h*100, 100-(height/2+5)/h*100);
    el.style.setProperty('--x',p.x); el.style.setProperty('--y',p.y);
  });
}
function resize() {
  const size = `${surface.clientWidth}:${surface.clientHeight}`;
  if (surfaceSize && size !== surfaceSize) clearInputs();
  surfaceSize = size;
  const next = matchMedia('(orientation: portrait)').matches ? 'portrait' : 'landscape';
  if (next !== orientation) {
    clearInputs(); if (layout) saveLayout(); orientation = next; loadLayout(); select(null);
  }
  render();
}
function select(id) {
  selected = id;
  elements.forEach((el, key) => el.classList.toggle('selected',key === id));
  const scale = id ? layout[id].scale : 1;
  $('selected-label').textContent = id ? (descriptions[id] || id) : 'All controls';
  $('size').value = Math.round(scale*100); $('size-value').textContent = `${Math.round(scale*100)}%`;
}
definitions.forEach(([id,label,kind]) => {
  const el = document.createElement('button');
  el.type = 'button'; el.className = `control ${kind}`; el.dataset.control = id;
  el.setAttribute('aria-label', descriptions[id] || id);
  if (kind === 'stick') { const thumb = document.createElement('span'); thumb.className = 'stick-thumb'; thumb.textContent = label; el.append(thumb); }
  else el.textContent = label;
  el.oncontextmenu = event => event.preventDefault();
  el.addEventListener('pointerdown', event => {
    event.preventDefault();
    if (event.pointerType === 'mouse' && event.button !== 0) return;
    releasePointer(event.pointerId, false); // Browsers may reuse an ID after a missed release.
    if ((!connected && !editing) || [...pointers.values()].some(p => p.id === id)) return;
    let captured = false;
    try { el.setPointerCapture(event.pointerId); captured = el.hasPointerCapture(event.pointerId); } catch {}
    const rect = el.getBoundingClientRect();
    pointers.set(event.pointerId,{id, captured, pointerType:event.pointerType, touchId:undefined,
      x:0, y:0, startX:event.clientX, startY:event.clientY, originalX:layout[id].x, originalY:layout[id].y,
      centerX:rect.left+rect.width/2, centerY:rect.top+rect.height/2, radius:rect.width*.32});
    if (editing) select(id); else { el.classList.add('pressed'); move(event); dirty = true; send(); }
  });
  el.addEventListener('lostpointercapture', event => {
    if (pointers.get(event.pointerId)?.id === id && !el.hasPointerCapture(event.pointerId)) releasePointer(event.pointerId);
  });
  surface.append(el); elements.set(id,el);
});
function move(event) {
  const pointer = pointers.get(event.pointerId); if (!pointer) return;
  if ((pointer.pointerType === 'mouse' || pointer.pointerType === 'pen') && event.buttons === 0) {
    releasePointer(event.pointerId); return;
  }
  if (editing) {
    layout[pointer.id].x = pointer.originalX + (event.clientX-pointer.startX)/surface.clientWidth*100;
    layout[pointer.id].y = pointer.originalY + (event.clientY-pointer.startY)/surface.clientHeight*100;
    render(); return;
  }
  if (pointer.id === 'LS' || pointer.id === 'RS') {
    let dx = (event.clientX-pointer.centerX)/pointer.radius, dy = (event.clientY-pointer.centerY)/pointer.radius;
    const length = Math.hypot(dx,dy); if (length>1) {dx/=length;dy/=length;}
    pointer.x = Math.abs(dx)<.06 ? 0 : dx; pointer.y = Math.abs(dy)<.06 ? 0 : -dy;
    elements.get(pointer.id).querySelector('.stick-thumb').style.transform = `translate(${dx*pointer.radius}px,${dy*pointer.radius}px)`;
    dirty = true;
  }
}
function releasePointer(pointerId, transmit = true) {
  const pointer = pointers.get(pointerId); if (!pointer) return;
  pointers.delete(pointerId); const el = elements.get(pointer.id);
  el.classList.remove('pressed'); const thumb = el.querySelector('.stick-thumb'); if (thumb) thumb.style.transform='';
  try { if (el.hasPointerCapture(pointerId)) el.releasePointerCapture(pointerId); } catch {}
  if (editing) saveLayout();
  dirty = true; if (transmit) send();
}
function clearInputs(transmit = true) {
  activeTouches = [];
  for (const pointerId of [...pointers.keys()]) releasePointer(pointerId, false);
  elements.forEach(el => {el.classList.remove('pressed'); const thumb=el.querySelector('.stick-thumb'); if (thumb) thumb.style.transform='';});
  dirty = true; if (transmit) send();
}
// These listeners still see releases outside the original button or after capture fails.
window.addEventListener('pointermove', move, true);
for (const type of ['pointerup','pointercancel']) window.addEventListener(type, event => releasePointer(event.pointerId), true);
function reconcileTouches(event) {
  activeTouches = Array.from(event.touches);
  let released = false;
  for (const [pointerId, pointer] of pointers) {
    if (pointer.pointerType !== 'touch') continue;
    if (pointer.touchId === undefined) {
      const contact = activeTouches.find(t => t.target?.closest?.('.control') === elements.get(pointer.id) &&
        ![...pointers.values()].some(p => p.touchId === t.identifier));
      pointer.touchId = contact?.identifier;
    }
    if (!activeTouches.some(t => t.identifier === pointer.touchId)) {
      releasePointer(pointerId, false); released = true;
    }
  }
  if (released) send();
}
// Touch identifiers are independent of pointer IDs. The actual remaining contacts
// provide a second release signal on phone browsers that also expose Touch Events.
for (const type of ['touchstart','touchmove','touchend','touchcancel'])
  document.addEventListener(type, reconcileTouches, {capture:true,passive:true});
// Game controls use pointer events, so suppressing their synthetic click does not
// suppress controller input. Keep normal clicks on Join/Edit/Done and text fields.
document.addEventListener('touchend', event => {
  if (event.target?.closest?.('.control')) event.preventDefault();
}, {passive:false});
document.addEventListener('dblclick', event => event.preventDefault(), {capture:true});
// Safari's pinch events supplement touch-action:none without rejecting multiple
// fingers: both sticks and buttons must continue to work at the same time.
for (const type of ['gesturestart','gesturechange','gestureend'])
  document.addEventListener(type, event => event.preventDefault(), {passive:false});
function reconcileCaptures() {
  for (const [pointerId, pointer] of pointers)
    if (pointer.captured && !elements.get(pointer.id).hasPointerCapture(pointerId)) releasePointer(pointerId, false);
}
function state() {
  const s = {buttons:[],lx:0,ly:0,rx:0,ry:0,zl:0,zr:0};
  if (editing || document.hidden) return s;
  pointers.forEach(p => {
    if (p.id === 'LS') {s.lx=p.x;s.ly=p.y;}
    else if (p.id === 'RS') {s.rx=p.x;s.ry=p.y;}
    else if (p.id === 'ZL') s.zl=1;
    else if (p.id === 'ZR') s.zr=1;
    else s.buttons.push(p.id);
  });
  return s;
}
function send() {
  if (!connected || ws?.readyState !== WebSocket.OPEN) return;
  if (ws.bufferedAmount > 4096) {clearInputs(false); connected=false; ws.close(); return;}
  reconcileCaptures();
  try {
    ws.send(JSON.stringify({type:'input',epoch:inputEpoch,state:state()})); dirty=false;lastSent=performance.now();
  } catch { clearInputs(false); connected=false; ws.close(); }
}
setInterval(() => {
  const now = performance.now();
  if (now-lastTick > 750) clearInputs(false); // Resume after a suspended/frozen page from neutral.
  lastTick = now;
  reconcileCaptures();
  if (!document.hidden && (dirty || now-lastSent>200)) send();
}, 1000/30);
setInterval(() => {if(connected && ws?.readyState===WebSocket.OPEN) ws.send(JSON.stringify({type:'ping',time:performance.now()}));}, 2000);
function showOverlay(message) {
  $('join-overlay').hidden=false; $('join-message').textContent=message; $('join').disabled=false; $('join').textContent='Try again →';
}
async function keepAwake() {
  try { if (navigator.wakeLock && !document.hidden && connected) wakeLock = await navigator.wakeLock.request('screen'); } catch {}
}
function connect() {
  clearTimeout(reconnectTimer); fatal=false;
  if (!key) {showOverlay('Scan the QR code on the laptop to open your paired controller.'); return;}
  if (ws && ws.readyState < WebSocket.CLOSING) return;
  $('join').disabled=true; $('connection').textContent='Connecting…';
  const socket = new WebSocket(`${location.protocol==='https:'?'wss:':'ws:'}//${location.host}/ws`); ws=socket;
  socket.onopen=() => {
    if (socket === ws && socket.readyState === WebSocket.OPEN)
      socket.send(JSON.stringify({type:'join',key,client,name:$('name').value.trim() || 'Phone'}));
  };
  socket.onmessage=event => {
    if (socket !== ws) return;
    const message = JSON.parse(event.data);
    if (message.type==='joined') {
      inputEpoch = message.epoch ?? 0;
      connected=true;retryDelay=800;
      $('join-overlay').hidden=true; $('join').disabled=false;
      $('connection').textContent=message.mode==='preview' ? `P${message.player} · Preview only` : `Player ${message.player} · Connected`;
      $('connection-dot').className='status-dot'; $('player-label').textContent=`PLAYER ${String(message.player).padStart(2,'0')}`;
      document.documentElement.style.setProperty('--player',colors[message.player-1]);
      storage.set('icontrol-name',$('name').value.trim());clearInputs();keepAwake();
    } else if (message.type==='reset') {
      inputEpoch = message.epoch;
      clearInputs();
    } else if (message.type==='pong') $('latency').textContent=`${Math.max(1,Math.round(performance.now()-message.time))} ms`;
    else if (message.type==='error') {fatal=Boolean(message.fatal);showOverlay(message.message);}
  };
  socket.onclose=event => {
    if (socket !== ws) return;
    connected=false;clearInputs();$('latency').textContent=''; $('connection-dot').className='status-dot off';
    $('connection').textContent='Disconnected';
    if(event.code===4003) {fatal=true;showOverlay('Your player slot was released on the laptop. Tap below to join again.');}
    if(!fatal) {
      $('connection').textContent='Reconnecting…';
      showOverlay('Connection lost. Keep the server running and check that both devices are on the same Wi-Fi. Reconnecting automatically…');
      reconnectTimer=setTimeout(connect,retryDelay);retryDelay=Math.min(retryDelay*1.5,5000);
    }
  };
  socket.onerror=() => { if (socket === ws) {clearInputs(false); $('connection').textContent='Connection unavailable';} };
}
$('join-form').onsubmit=event => {event.preventDefault();connect();};
function setEditing(value) {
  clearInputs(); editing=value; document.body.classList.toggle('editing',value);
  $('editor').hidden=!value;$('edit').textContent=value?'Editing…':'Edit layout';
  if (!value) {saveLayout();select(null);} render();
}
$('edit').onclick=() => setEditing(!editing);
$('done').onclick=() => setEditing(false);
surface.addEventListener('pointerdown',event => {if (editing && event.target===surface) select(null);});
$('size').oninput=() => {
  const scale=Number($('size').value)/100;
  if(selected) layout[selected].scale=scale; else Object.values(layout).forEach(p=>p.scale=scale);
  $('size-value').textContent=`${Math.round(scale*100)}%`;render();saveLayout();
};
$('reset').onclick=() => {layout=defaults();select(null);render();saveLayout();};
$('fullscreen').onclick=async () => {
  try {
    if(document.fullscreenElement) await document.exitFullscreen();
    else if(document.documentElement.requestFullscreen) {await document.documentElement.requestFullscreen();try{await screen.orientation.lock('landscape');}catch{}}
    else $('play-hint').textContent='Full screen unavailable in this browser';
    keepAwake();
  } catch {$('play-hint').textContent='Turn your phone sideways to play';}
};
window.addEventListener('blur',clearInputs);
window.addEventListener('pagehide',() => {clearInputs();ws?.close();});
window.addEventListener('pageshow',() => {clearInputs();lastTick=performance.now();});
document.addEventListener('freeze',() => clearInputs());
document.addEventListener('visibilitychange',() => {clearInputs();if(!document.hidden)keepAwake();else wakeLock?.release().catch(()=>{});});
new ResizeObserver(resize).observe(surface);
resize();
if (!key) $('join-message').textContent='Scan the QR code on the laptop to pair this phone first.';
