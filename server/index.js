'use strict';

const express  = require('express');
const webpush  = require('web-push');
const schedule = require('node-schedule');

// ── VAPID ──────────────────────────────────────────────────────────────────
webpush.setVapidDetails(
  'mailto:alexicoo@gmail.com',
  process.env.VAPID_PUBLIC_KEY,
  process.env.VAPID_PRIVATE_KEY,
);

// ── Subscriptions (in-memory, refreshed each morning when app opens) ───────
const subs = new Map(); // endpoint → PushSubscription

// ── Molloy bell schedule ───────────────────────────────────────────────────
const PERIODS = [
  { label: 'Period 1',  h: 8,  m: 0  },
  { label: 'Homeroom',  h: 8,  m: 45 },
  { label: 'Period 2',  h: 8,  m: 59 },
  { label: 'Period 3',  h: 9,  m: 44 },
  { label: 'Period 4',  h: 10, m: 29 },
  { label: 'Period 5',  h: 11, m: 14 },
  { label: 'Period 6',  h: 11, m: 59 },
  { label: 'Period 7',  h: 12, m: 44 },
  { label: 'Period 8',  h: 13, m: 29 },
];

const ALERT_BEFORE = 3;

function fmt12(h, m) {
  const hr = h === 0 ? 12 : h > 12 ? h - 12 : h;
  return `${hr}:${String(m).padStart(2, '0')} ${h >= 12 ? 'PM' : 'AM'}`;
}

async function broadcast(payload) {
  const msg  = JSON.stringify(payload);
  const dead = [];
  for (const [endpoint, sub] of subs) {
    try {
      await webpush.sendNotification(sub, msg);
    } catch (err) {
      if (err.statusCode === 404 || err.statusCode === 410) dead.push(endpoint);
    }
  }
  dead.forEach(e => subs.delete(e));
  console.log(`[push] "${payload.title}" → ${subs.size} subs`);
}

// Schedule Mon–Fri alerts in Eastern Time
for (const p of PERIODS) {
  const total  = p.h * 60 + p.m - ALERT_BEFORE;
  const alertH = Math.floor(total / 60);
  const alertM = total % 60;

  schedule.scheduleJob(
    { hour: alertH, minute: alertM, dayOfWeek: [1, 2, 3, 4, 5], tz: 'America/New_York' },
    () => broadcast({
      title: `${p.label} in ${ALERT_BEFORE} min`,
      body:  `Starts at ${fmt12(p.h, p.m)}`,
    }),
  );
}

// ── Express ────────────────────────────────────────────────────────────────
const app = express();
app.use(express.json());

app.use((_req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin',  'https://alexico1969.github.io');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  next();
});
app.options('*', (_req, res) => res.sendStatus(204));

// VAPID public key (safe to expose)
app.get('/vapid-public-key', (_req, res) => {
  res.json({ key: process.env.VAPID_PUBLIC_KEY });
});

// Register / refresh a push subscription
app.post('/subscribe', (req, res) => {
  const sub = req.body;
  if (!sub?.endpoint) return res.status(400).json({ error: 'missing endpoint' });
  subs.set(sub.endpoint, sub);
  console.log(`[sub] registered, total: ${subs.size}`);
  res.json({ ok: true });
});

// Keep-alive endpoint (pinged by the PWA every 4 min)
app.get('/ping', (_req, res) => res.send('pong'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`SchoolBell server listening on :${PORT}`));
