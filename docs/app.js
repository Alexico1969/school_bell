'use strict';

// ── Constants ──────────────────────────────────────────────────────────────

// Set this after deploying the server to Render.com (Settings → Push Server URL)
const PUSH_SERVER_DEFAULT = '';

const ALERT_MINUTES_BEFORE = 3;

const MOLLOY_DEFAULTS = [
  { label: 'Period 1',  startHour: 8,  startMinute: 0  },
  { label: 'Homeroom',  startHour: 8,  startMinute: 45 },
  { label: 'Period 2',  startHour: 8,  startMinute: 59 },
  { label: 'Period 3',  startHour: 9,  startMinute: 44 },
  { label: 'Period 4',  startHour: 10, startMinute: 29 },
  { label: 'Period 5',  startHour: 11, startMinute: 14 },
  { label: 'Period 6',  startHour: 11, startMinute: 59 },
  { label: 'Period 7',  startHour: 12, startMinute: 44 },
  { label: 'Period 8',  startHour: 13, startMinute: 29 },
];

const DEFAULT_SETTINGS = {
  enabled: true,
  schoolLat: 40.7282,
  schoolLng: -73.7949,
  schoolRadius: 300,
  checkLocation: true,
  pushServer: PUSH_SERVER_DEFAULT,
};

// ── State ──────────────────────────────────────────────────────────────────

let schedule = [];
let settings = { ...DEFAULT_SETTINGS };
let notifiedToday = {};        // key: "Label_DateString" → true
let editingIndex = null;       // null = add mode, number = edit mode
let deferredInstallPrompt = null;

// ── Boot ───────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', async () => {
  loadState();
  bindEvents();
  registerSW();
  await requestNotificationPermission();
  setupPush();
  renderHome();
  startPoller();
  watchInstallPrompt();
});

// ── Persistence ────────────────────────────────────────────────────────────

function loadState() {
  try {
    const s = localStorage.getItem('schedule');
    schedule = s ? JSON.parse(s) : [...MOLLOY_DEFAULTS];

    const cfg = localStorage.getItem('settings');
    settings = cfg ? { ...DEFAULT_SETTINGS, ...JSON.parse(cfg) } : { ...DEFAULT_SETTINGS };

    const n = localStorage.getItem('notifiedToday');
    if (n) {
      const obj = JSON.parse(n);
      notifiedToday = obj.date === new Date().toDateString() ? (obj.data || {}) : {};
    }
  } catch {
    schedule = [...MOLLOY_DEFAULTS];
    settings = { ...DEFAULT_SETTINGS };
    notifiedToday = {};
  }
}

function saveSchedule()  { localStorage.setItem('schedule', JSON.stringify(schedule)); }
function saveSettings()  { localStorage.setItem('settings', JSON.stringify(settings)); }
function saveNotified()  {
  localStorage.setItem('notifiedToday', JSON.stringify({
    date: new Date().toDateString(),
    data: notifiedToday,
  }));
}

// ── Service Worker ─────────────────────────────────────────────────────────

function registerSW() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  }
}

// ── Notifications ──────────────────────────────────────────────────────────

async function requestNotificationPermission() {
  if ('Notification' in window && Notification.permission === 'default') {
    await Notification.requestPermission();
  }
}

// ── Web Push subscription ──────────────────────────────────────────────────

function urlBase64ToUint8Array(b64) {
  const pad = '='.repeat((4 - (b64.length % 4)) % 4);
  const raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return new Uint8Array([...raw].map(c => c.charCodeAt(0)));
}

async function setupPush() {
  const server = settings.pushServer;
  if (!server) return;
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    updatePushStatus('error', 'Browser does not support push notifications');
    return;
  }
  if (Notification.permission === 'denied') {
    updatePushStatus('error', 'Notifications blocked — enable in browser settings');
    return;
  }
  if (Notification.permission !== 'granted') {
    updatePushStatus('error', 'Notification permission not granted — tap Allow when prompted');
    return;
  }

  try {
    updatePushStatus('info', 'Connecting…');
    const reg = await navigator.serviceWorker.ready;

    const resp = await fetch(`${server}/vapid-public-key`);
    if (!resp.ok) { updatePushStatus('error', `Server error ${resp.status}`); return; }
    const { key } = await resp.json();

    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(key),
      });
    }

    await fetch(`${server}/subscribe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(sub.toJSON()),
    });

    // Ping every 4 min to keep the free-tier server awake
    setInterval(() => fetch(`${server}/ping`).catch(() => {}), 4 * 60 * 1000);

    updatePushStatus('connected');
  } catch (err) {
    console.warn('Push setup failed:', err);
    updatePushStatus('error', err.message || 'Could not reach server — check URL');
  }
}

function updatePushStatus(state, msg) {
  const el = document.getElementById('push-status');
  if (!el) return;
  if (state === 'connected') {
    el.textContent = '✓ Connected — watch notifications enabled';
    el.style.color = '#15803d';
  } else if (state === 'info') {
    el.textContent = msg || '…';
    el.style.color = '#6b7280';
  } else {
    el.textContent = `⚠ ${msg || 'Could not reach server — check URL'}`;
    el.style.color = '#dc2626';
  }
}

async function fireNotification(title, body) {
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'granted') {
    const p = await Notification.requestPermission();
    if (p !== 'granted') return;
  }
  try {
    // Use SW notification so it works when tab is backgrounded
    const reg = await navigator.serviceWorker.ready;
    await reg.showNotification(title, {
      body,
      icon: './icon.svg',
      badge: './icon.svg',
      vibrate: [200, 100, 200, 100, 200],
      tag: title,
      renotify: false,
    });
  } catch {
    // Fallback: direct Notification API
    new Notification(title, { body });
  }
}

// ── Geolocation ────────────────────────────────────────────────────────────

function haversine(lat1, lng1, lat2, lng2) {
  const R = 6_371_000;
  const toRad = x => x * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
          + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function isAtSchool() {
  if (!settings.checkLocation) return Promise.resolve(true);
  if (!('geolocation' in navigator)) return Promise.resolve(true);
  return new Promise(resolve => {
    navigator.geolocation.getCurrentPosition(
      pos => resolve(haversine(pos.coords.latitude, pos.coords.longitude,
                               settings.schoolLat, settings.schoolLng) <= settings.schoolRadius),
      ()  => resolve(true),  // if location fails, allow notification
      { timeout: 5000, maximumAge: 60_000 },
    );
  });
}

// ── Scheduler / Poller ─────────────────────────────────────────────────────

function startPoller() {
  checkSchedule();
  setInterval(checkSchedule, 30_000);
  updateCountdown();
  setInterval(updateCountdown, 1000);
}

async function checkSchedule() {
  if (!settings.enabled) return;

  const now = new Date();
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const todayKey = now.toDateString();

  for (const p of schedule) {
    const alertMin = p.startHour * 60 + p.startMinute - ALERT_MINUTES_BEFORE;
    const key = `${p.label}_${todayKey}`;
    if (notifiedToday[key]) continue;

    // Fire if we're within a 5-minute window past the alert time.
    // Wide window compensates for Chrome's background timer throttling.
    const delta = nowMin - alertMin;
    if (delta < 0 || delta >= 5) continue;

    const atSchool = await isAtSchool();
    if (!atSchool) continue;

    await fireNotification(
      `${p.label} in ${ALERT_MINUTES_BEFORE} min`,
      `Starts at ${fmt12(p.startHour, p.startMinute)}`,
    );
    notifiedToday[key] = true;
    saveNotified();
  }
}

// ── Schedule state helpers ─────────────────────────────────────────────────

function getScheduleState() {
  const nowMin = new Date().getHours() * 60 + new Date().getMinutes();
  let current = null;
  let next = null;

  for (const p of schedule) {
    const s = p.startHour * 60 + p.startMinute;
    if (s <= nowMin) current = p;          // last period that has started
    else if (!next)  next = p;             // first period not yet started
  }
  return { current, next };
}

// ── Time utilities ─────────────────────────────────────────────────────────

function fmt12(hour, minute) {
  const h = hour === 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  const m = String(minute).padStart(2, '0');
  return `${h}:${m} ${hour >= 12 ? 'PM' : 'AM'}`;
}

function alertLabel(startHour, startMinute) {
  const total = startHour * 60 + startMinute - ALERT_MINUTES_BEFORE;
  return fmt12(Math.floor(total / 60), total % 60);
}

function fmtDuration(secs) {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  return `${m}:${String(s).padStart(2,'0')}`;
}

function secondsUntil(hour, minute) {
  const now = new Date();
  const target = new Date();
  target.setHours(hour, minute, 0, 0);
  return Math.max(0, Math.floor((target - now) / 1000));
}

// ── Rendering ──────────────────────────────────────────────────────────────

function renderHome() {
  renderStatusCard();
  renderPeriodList();
}

let _lastStateKey = '';

function renderStatusCard() {
  const { current, next } = getScheduleState();
  const active = settings.enabled;

  const card = document.getElementById('status-card');
  card.className = `status-card ${active ? 'active' : 'inactive'}`;

  let infoHtml = '';
  if (next) {
    infoHtml = `
      <div class="status-info">
        <div class="status-in">${current ? `In: ${current.label}` : 'Before school'}</div>
        <div class="status-next">Next: <strong>${next.label}</strong> · ${fmt12(next.startHour, next.startMinute)}</div>
        <div class="status-alert">Alert at ${alertLabel(next.startHour, next.startMinute)}</div>
        <div class="status-countdown" id="countdown">–</div>
      </div>`;
  } else if (current) {
    infoHtml = `
      <div class="status-info">
        <div class="status-in">In: <strong>${current.label}</strong></div>
        <div class="status-next">Last period of the day</div>
      </div>`;
  } else {
    infoHtml = `
      <div class="status-info">
        <div class="status-next">School day complete</div>
      </div>`;
  }

  card.innerHTML = `
    <div class="status-icon">${active ? '🔔' : '🔕'}</div>
    <div class="status-state">${active ? 'Active' : 'Inactive'}</div>
    ${infoHtml}
    <div class="status-actions">
      <button id="btn-toggle" class="btn-toggle ${active ? 'btn-stop' : 'btn-start'}">
        ${active ? 'Disable' : 'Enable'}
      </button>
      <button id="btn-test" class="btn-test">Test alert</button>
    </div>`;

  document.getElementById('btn-toggle').addEventListener('click', () => {
    settings.enabled = !settings.enabled;
    saveSettings();
    renderStatusCard();
  });

  document.getElementById('btn-test').addEventListener('click', () => {
    fireNotification('SchoolBell', 'Notifications are working!');
  });

  _lastStateKey = `${current?.label}|${next?.label}|${active}`;
}

function updateCountdown() {
  // Re-render card if schedule state or toggle changed
  const { current, next } = getScheduleState();
  const key = `${current?.label}|${next?.label}|${settings.enabled}`;
  if (key !== _lastStateKey) {
    renderStatusCard();
    return;
  }

  const el = document.getElementById('countdown');
  if (!el || !next) return;

  const total = next.startHour * 60 + next.startMinute - ALERT_MINUTES_BEFORE;
  const secs = secondsUntil(Math.floor(total / 60), total % 60);
  el.textContent = secs <= 0 ? 'Alert firing soon…' : `Alert in ${fmtDuration(secs)}`;
}

function renderPeriodList() {
  const { current } = getScheduleState();
  const list = document.getElementById('period-list');
  list.innerHTML = schedule.map((p, i) => `
    <li class="period-item${p.label === current?.label ? ' current-period' : ''}">
      <span class="period-num">${i + 1}</span>
      <span class="period-label">${escHtml(p.label)}</span>
      <span class="period-time">${fmt12(p.startHour, p.startMinute)}</span>
      <span class="period-alert-chip">${alertLabel(p.startHour, p.startMinute)}</span>
    </li>`).join('');
}

// ── Settings rendering ─────────────────────────────────────────────────────

function renderSettings() {
  document.getElementById('input-lat').value         = settings.schoolLat;
  document.getElementById('input-lng').value         = settings.schoolLng;
  document.getElementById('input-radius').value      = settings.schoolRadius;
  document.getElementById('toggle-location').checked = settings.checkLocation;
  document.getElementById('input-push-server').value = settings.pushServer || '';
  renderSettingsPeriods();
}

function renderSettingsPeriods() {
  document.getElementById('period-count').textContent = `(${schedule.length})`;
  const list = document.getElementById('settings-period-list');
  list.innerHTML = schedule.map((p, i) => `
    <li class="spi">
      <div class="spi-info">
        <span class="spi-label">${escHtml(p.label)}</span>
        <span class="spi-time">${fmt12(p.startHour, p.startMinute)} · alert ${alertLabel(p.startHour, p.startMinute)}</span>
      </div>
      <div class="spi-actions">
        <button class="icon-btn" data-action="edit" data-index="${i}" aria-label="Edit">✏️</button>
        <button class="icon-btn" data-action="delete" data-index="${i}" aria-label="Delete">🗑️</button>
      </div>
    </li>`).join('');

  list.querySelectorAll('[data-action="edit"]').forEach(btn =>
    btn.addEventListener('click', () => openModal(parseInt(btn.dataset.index, 10)))
  );
  list.querySelectorAll('[data-action="delete"]').forEach(btn =>
    btn.addEventListener('click', () => deletePeriod(parseInt(btn.dataset.index, 10)))
  );
}

// ── Modal ──────────────────────────────────────────────────────────────────

function openModal(index = null) {
  editingIndex = index;
  const p = index !== null ? schedule[index] : null;
  document.getElementById('modal-title').textContent = p ? 'Edit Period' : 'Add Period';
  document.getElementById('modal-label').value = p ? p.label : '';
  const hh = p ? String(p.startHour).padStart(2, '0')   : '08';
  const mm = p ? String(p.startMinute).padStart(2, '0') : '00';
  document.getElementById('modal-time').value = `${hh}:${mm}`;
  document.getElementById('modal-overlay').classList.remove('hidden');
  document.getElementById('modal-label').focus();
}

function closeModal() {
  document.getElementById('modal-overlay').classList.add('hidden');
}

function saveModal() {
  const label = document.getElementById('modal-label').value.trim();
  const timeVal = document.getElementById('modal-time').value;
  if (!label || !timeVal) return;

  const [hStr, mStr] = timeVal.split(':');
  const period = { label, startHour: parseInt(hStr, 10), startMinute: parseInt(mStr, 10) };

  if (editingIndex !== null) {
    schedule[editingIndex] = period;
  } else {
    schedule.push(period);
    schedule.sort((a, b) => (a.startHour * 60 + a.startMinute) - (b.startHour * 60 + b.startMinute));
  }

  saveSchedule();
  renderSettingsPeriods();
  renderPeriodList();
  closeModal();
}

function deletePeriod(index) {
  if (!confirm(`Delete "${schedule[index].label}"?`)) return;
  schedule.splice(index, 1);
  saveSchedule();
  renderSettingsPeriods();
  renderPeriodList();
}

// ── View switching ─────────────────────────────────────────────────────────

function showView(name) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  document.getElementById(`view-${name}`).classList.add('active');
  if (name === 'home') renderHome();
  if (name === 'settings') renderSettings();
}

// ── Install prompt ─────────────────────────────────────────────────────────

function watchInstallPrompt() {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    document.getElementById('install-banner').classList.remove('hidden');
  });

  window.addEventListener('appinstalled', () => {
    document.getElementById('install-banner').classList.add('hidden');
    deferredInstallPrompt = null;
  });
}

// ── Event bindings ─────────────────────────────────────────────────────────

function bindEvents() {
  // View navigation
  document.getElementById('btn-settings').addEventListener('click', () => showView('settings'));
  document.getElementById('btn-back').addEventListener('click', () => showView('home'));

  // Reset schedule
  document.getElementById('btn-reset').addEventListener('click', () => {
    if (!confirm('Reset to the default Molloy schedule?')) return;
    schedule = [...MOLLOY_DEFAULTS];
    saveSchedule();
    renderSettingsPeriods();
    renderPeriodList();
  });

  // Save location
  document.getElementById('btn-save-location').addEventListener('click', () => {
    const lat    = parseFloat(document.getElementById('input-lat').value);
    const lng    = parseFloat(document.getElementById('input-lng').value);
    const radius = parseFloat(document.getElementById('input-radius').value);
    if (isNaN(lat) || isNaN(lng) || isNaN(radius)) {
      alert('Please enter valid numbers for all location fields.');
      return;
    }
    settings.schoolLat     = lat;
    settings.schoolLng     = lng;
    settings.schoolRadius  = radius;
    settings.checkLocation = document.getElementById('toggle-location').checked;
    saveSettings();
    alert('Location saved!');
  });

  // Save push server URL
  document.getElementById('btn-save-push').addEventListener('click', async () => {
    const url = document.getElementById('input-push-server').value.trim().replace(/\/$/, '');
    settings.pushServer = url;
    saveSettings();
    await setupPush();
  });

  // Add period
  document.getElementById('btn-add-period').addEventListener('click', () => openModal(null));

  // Modal
  document.getElementById('modal-cancel').addEventListener('click', closeModal);
  document.getElementById('modal-save').addEventListener('click', saveModal);
  document.getElementById('modal-label').addEventListener('keydown', e => { if (e.key === 'Enter') saveModal(); });
  document.getElementById('modal-overlay').addEventListener('click', e => {
    if (e.target === e.currentTarget) closeModal();
  });

  // Install banner
  document.getElementById('btn-install').addEventListener('click', async () => {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    const { outcome } = await deferredInstallPrompt.userChoice;
    if (outcome === 'accepted') {
      document.getElementById('install-banner').classList.add('hidden');
    }
    deferredInstallPrompt = null;
  });
  document.getElementById('btn-install-dismiss').addEventListener('click', () => {
    document.getElementById('install-banner').classList.add('hidden');
  });
}

// ── Utility ────────────────────────────────────────────────────────────────

function escHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
