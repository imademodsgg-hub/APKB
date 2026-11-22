/* APKB — Broadcast Into Browser · graphical lab (English UI). Termux/Linux does all processing. */
(() => {
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const hsize = b => { b = +b || 0; const u = ['B', 'KB', 'MB', 'GB']; let i = 0; while (b >= 1024 && i < 3) { b /= 1024; i++; } return (i ? b.toFixed(1) : b) + ' ' + u[i]; };
const ls = { get: (k, d) => { try { return JSON.parse(localStorage.getItem('apkb.' + k)) ?? d; } catch { return d; } }, set: (k, v) => { try { localStorage.setItem('apkb.' + k, JSON.stringify(v)); } catch {} } };
function toast(m) { const t = document.createElement('div'); t.className = 'toast'; t.textContent = m; $('#toasts').append(t); setTimeout(() => t.remove(), 3200); }
async function api(p, o = {}) {
  const r = await fetch('/api/' + p, { method: o.body !== undefined ? (o.method || 'POST') : (o.method || 'GET'), headers: { 'Content-Type': 'application/json' }, body: o.body !== undefined ? JSON.stringify(o.body) : undefined });
  let j = {}; try { j = await r.json(); } catch {}
  if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
  return j;
}
const IC = {
  home: 'M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10', build: 'M14 6l4 4-9 9H5v-4zM13 7l4 4', html: 'M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16', try: 'M7 3h10a2 2 0 012 2v14a2 2 0 01-2 2H7a2 2 0 01-2-2V5a2 2 0 012-2zM10 18h4',
  analyze: 'M4 20V10M10 20V4M16 20v-8M22 20H2', inspect: 'M11 4a7 7 0 100 14 7 7 0 000-14zM21 21l-5-5', new: 'M12 5v14M5 12h14', doctor: 'M12 21s-8-5-8-11a4.5 4.5 0 018-2.7A4.5 4.5 0 0120 10c0 6-8 11-8 11z',
  settings: 'M12 15a3 3 0 100-6 3 3 0 000 6zM19 12l2 1-2 3-2-.5-1.5 1V19h-3l-.5-2-2-1-2 .5-2-3 1.5-1.5v-2L5 9l2-3 2 .5 1.5-1V3h3l.5 2 2 1 2-.5 2 3z', history: 'M4 5v5h5M5 10a8 8 0 110 4M12 8v5l3 2', folder: 'M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z', file: 'M6 3h8l5 5v13H6zM14 3v5h5', up: 'M12 19V5M5 12l7-7 7 7', dl: 'M12 4v12M6 11l6 6 6-6M5 20h14'
};
const ico = n => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="${IC[n] || ''}"/></svg>`;
const NAV = [['home', 'Home'], ['build', 'Build APK'], ['html', 'HTML → APK'], ['try', 'Try Before Build', 1], ['analyze', 'Analyze'], ['inspect', 'APK Inspector'], ['new', 'New project'], ['doctor', 'Lab Doctor'], ['history', 'History & Logs'], ['settings', 'Settings']];
const LOGO = `<svg width="40" height="40" viewBox="0 0 32 32"><rect width="32" height="32" rx="10" fill="#073042"/><path d="M8.5 21.5a7.5 7.5 0 0115 0z" fill="#3DDC84"/><circle cx="13" cy="17.8" r="1" fill="#073042"/><circle cx="19" cy="17.8" r="1" fill="#073042"/><path d="M11.5 11l1.6 2.4M20.5 11l-1.6 2.4" stroke="#3DDC84" stroke-width="1.5" stroke-linecap="round"/></svg>`;
let INFO = null, DOC = null, CUR = null;

/* ------------------------------------------------------------- file picker + upload */
function upload(file, prog) {
  return new Promise((res, rej) => {
    const x = new XMLHttpRequest(); x.open('POST', '/api/upload?name=' + encodeURIComponent(file.name));
    x.upload.onprogress = e => prog && prog(e.loaded / (e.total || 1));
    x.onload = () => { try { const j = JSON.parse(x.responseText); x.status < 300 ? res(j) : rej(new Error(j.error)); } catch (e) { rej(e); } };
    x.onerror = () => rej(new Error('Upload failed')); x.send(file);
  });
}
function pickPath({ ext = '', dir = true } = {}) {
  return new Promise(resolve => {
    const m = document.createElement('div'); m.className = 'modal';
    m.innerHTML = `<div><header><h3>Choose ${dir ? 'a file or folder' : 'a file'}</h3><span class="sp"></span><button class="btn o sm" data-x>Close</button></header><div class="crumbs"></div><div class="bd"></div><footer><label class="btn o sm" style="cursor:pointer">Upload from this device<input type="file" hidden ${ext ? 'accept=".' + ext.split(',').join(',.') + '"' : ''}></label><span class="sp"></span>${dir ? '<button class="btn sm" data-use>Use this folder</button>' : ''}</footer></div>`;
    document.body.append(m);
    let cur = ls.get('lastdir', '');
    const done = v => { m.remove(); resolve(v); };
    $('[data-x]', m).onclick = () => done(null);
    $('input[type=file]', m).onchange = async e => { const f = e.target.files[0]; if (!f) return; toast('Uploading ' + f.name + '…'); try { const r = await upload(f); done(r.path); } catch (er) { toast(er.message); } };
    const use = $('[data-use]', m); if (use) use.onclick = () => done(cur);
    async function load(p) {
      try {
        const r = await api('fs?path=' + encodeURIComponent(p) + '&ext=' + encodeURIComponent(ext)); cur = r.path; ls.set('lastdir', cur);
        const parts = cur.split('/').filter(Boolean);
        $('.crumbs', m).innerHTML = r.roots.map(x => `<a href="#" data-p="${esc(x)}">${x === '/' ? '/' : esc(x.split('/').pop() || x)}</a>`).join(' · ') + '<br>' + esc(cur);
        $('.bd', m).innerHTML = (cur !== '/' ? `<div class="fe" data-p="${esc(r.parent)}">${ico('up')} <b>..</b></div>` : '') + r.entries.map(e => `<div class="fe" data-${e.dir ? 'p' : 'f'}="${esc(cur.replace(/\/$/, '') + '/' + e.name)}">${ico(e.dir ? 'folder' : 'file')}<span>${esc(e.name)}</span><small>${e.dir ? '' : hsize(e.size)}</small></div>`).join('') || '<div class="empty">Empty folder</div>';
        $$('[data-p]', m).forEach(a => a.onclick = ev => { ev.preventDefault(); load(a.dataset.p); });
        $$('[data-f]', m).forEach(a => a.onclick = () => done(a.dataset.f));
      } catch (e) { toast(e.message); if (p) load(''); }
    }
    load(cur);
  });
}
const pathField = (id, label, o = {}) => `<div data-pf="${id}" data-ext="${o.ext || ''}" data-dir="${o.dir === false ? 0 : 1}"><label class="f">${label}</label><div class="pathbox"><input type="text" id="${id}" placeholder="${esc(o.ph || '/storage/emulated/0/…')}" value="${esc(o.val || '')}"><button type="button" class="btn o sm" data-browse>Browse</button></div>${o.hint ? `<div class="hint">${o.hint}</div>` : ''}</div>`;
function bindPaths(root) {
  $$('[data-pf]', root).forEach(w => { $('[data-browse]', w).onclick = async () => { const p = await pickPath({ ext: w.dataset.ext, dir: w.dataset.dir === '1' }); if (p) { $('input', w).value = p; $('input', w).dispatchEvent(new Event('change')); } }; });
}

/* ------------------------------------------------------------------- job runner */
const STAGES = ['Prepare', 'Manifest', 'Resources', 'Java', 'Dex', 'Package', 'Verify'];
const STAGE_RX = [[/Extract|Scanning|PROJECT ANALYSIS|Creating the Example|Generating the WebView/, 0, 8], [/Manifest ready|BUILD ·/, 1, 22], [/Compile resources|Link resources|auto-generated/, 2, 38], [/Compile Java/, 3, 55], [/Dex/, 4, 72], [/Zipalign|native librar/, 5, 84], [/VERIFICATION|Archive integrity/, 6, 93], [/BUILD COMPLETE/, 6, 100]];
function lineClass(l) { const t = l.trim(); if (t.startsWith('✔')) return 'ok'; if (t.startsWith('✘') || /FAILED/.test(t)) return 'er'; if (t.startsWith('▲')) return 'wn'; if (t.startsWith('•')) return 'in'; if (/^[┌╔╚║]/.test(t)) return 'sec'; if (/^[│└─]/.test(t)) return 'dm'; return ''; }
async function runJob(box, body, opt = {}) {
  const isBuild = body.kind === 'build' || body.kind === 'test' || body.kind === 'html';
  box.innerHTML = `<div class="card"><div class="row"><b class="jt">Starting…</b><span class="sp"></span><span class="hint jtime">0s</span><button class="btn o sm jcancel">Cancel</button></div>
  ${isBuild ? `<div class="stages">${STAGES.map(s => `<span>${s}</span>`).join('')}</div><div class="bar"><i></i></div>` : ''}
  <div class="hint jstep" style="margin:10px 0">Waiting for Termux…</div><div class="console"></div><div class="jres"></div></div>`;
  const con = $('.console', box), t0 = Date.now(); let stage = -1, pct = 0, job, es, metaSeen = {};
  const tick = setInterval(() => { const t = $('.jtime', box); if (t) t.textContent = Math.round((Date.now() - t0) / 1000) + 's'; }, 500);
  const log = l => { const d = document.createElement('div'); d.className = lineClass(l); d.textContent = l || ' '; const nb = con.scrollTop + con.clientHeight >= con.scrollHeight - 30; con.append(d); if (nb) con.scrollTop = con.scrollHeight; };
  const setStage = txt => { for (const [rx, i, p] of STAGE_RX) if (rx.test(txt) && p >= pct) { pct = p; stage = Math.max(stage, i); } if (isBuild) { $('.bar>i', box).style.width = pct + '%'; $$('.stages span', box).forEach((s, i) => s.className = i < stage ? 'done' : i === stage ? 'on' : ''); } };
  try { job = body.__existing || await api('jobs', { body }); } catch (e) { $('.jt', box).textContent = 'Could not start'; log('✘ ' + e.message); clearInterval(tick); return; }
  $('.jt', box).textContent = job.title; $('.jcancel', box).onclick = () => api('jobs/' + job.id + '/cancel', { body: {} });
  return new Promise(resolve => {
    es = new EventSource('/api/jobs/' + job.id + '/events');
    es.onmessage = m => {
      const e = JSON.parse(m.data);
      if (e.t === 'log') { log(e.line); setStage(e.line); }
      else if (e.t === 'step') { $('.jstep', box).textContent = '⏳ ' + e.label; setStage(e.label); }
      else if (e.t === 'meta') { metaSeen[e.k] = e.v; }
      else if (e.t === 'done') {
        es.close(); clearInterval(tick); $('.jcancel', box).remove(); $('.jstep', box).textContent = '';
        if (isBuild && e.status === 'ok') { $('.bar>i', box).style.width = '100%'; $$('.stages span', box).forEach(s => s.className = 'done'); }
        finish(e);
      }
    };
    es.onerror = () => { if (es.readyState === 2) { clearInterval(tick); resolve(); } };
    function finish(e) {
      const M = e.meta || metaSeen, r = $('.jres', box), id = job.id;
      if (e.status === 'ok' && M.apk) {
        r.innerHTML = `<div class="res ok"><h3>Build complete ✔</h3><dl class="kv"><dt>APK</dt><dd>${esc(M.apk)}</dd><dt>Size</dt><dd>${hsize(M.size)}</dd><dt>SHA-256</dt><dd>${esc(M.sha)}…</dd><dt>Package</dt><dd>${esc(M.pkg)}</dd>${M.label ? `<dt>Label</dt><dd>${esc(M.label)}</dd>` : ''}<dt>Time</dt><dd>${esc(M.seconds)}s</dd></dl>
        <div class="row"><a class="btn g" href="/api/jobs/${id}/apk">${ico('dl')} Download APK</a><button class="btn o" data-insp>Inspect APK</button></div><div class="hint" style="margin-top:10px">▲ The APK is unsigned — sign it with your own signer before installing. It is also saved on the device at the path above.</div></div>`;
        $('[data-insp]', r).onclick = () => { ls.set('inspectPath', M.apk); location.hash = '#/inspect'; };
      } else if (e.status === 'ok') {
        r.innerHTML = `<div class="res ok"><h3>Finished ✔</h3>${M.dest ? `<div class="row"><a class="btn g" href="/api/jobs/${id}/zip">${ico('dl')} Download project (.zip)</a></div><div class="hint">Saved at ${esc(M.dest)}</div>` : ''}</div>`;
      } else if (e.status === 'cancelled') {
        r.innerHTML = `<div class="res bad"><h3>Cancelled</h3></div>`;
      } else {
        const need = M.need === 'android_jar' ? `<a class="btn" href="#/settings">Open Settings → android.jar</a>` : M.need === 'tools' ? `<a class="btn" href="#/doctor">Open Lab Doctor</a>` : '';
        r.innerHTML = `<div class="res bad"><h3>${body.kind === 'inspect' || body.kind === 'doctor' ? 'Task failed' : 'Build failed'} ✘</h3><p>${esc(M.failed_reason || 'See the log for the exact error.')}</p><div class="row"><a class="btn red" href="/api/jobs/${id}/log" download>${ico('dl')} Download log file</a>${need}</div><div class="hint" style="margin-top:8px">${M.failed_log ? 'Also saved on the device: ' + esc(M.failed_log) : 'The full log is downloaded automatically.'}</div></div>`;
        if (isBuild) { const a = document.createElement('a'); a.href = '/api/jobs/' + id + '/log'; a.download = ''; document.body.append(a); a.click(); a.remove(); }
      }
      opt.onDone && opt.onDone(e, M); resolve(e);
    }
  });
}

/* -------------------------------------------------------------------- page helpers */
const head = (t, p) => `<div class="pg-h"><h1>${t}</h1>${p ? `<p>${p}</p>` : ''}</div>`;
const field = (id, label, o = {}) => `<div><label class="f" for="${id}">${label}</label>${o.opts ? `<select id="${id}">${o.opts.map(([l, v]) => `<option value="${v}" ${String(o.val) === String(v) ? 'selected' : ''}>${l}</option>`).join('')}</select>` : `<input type="${o.type || 'text'}" id="${id}" value="${esc(o.val ?? '')}" placeholder="${esc(o.ph || '')}">`}${o.hint ? `<div class="hint">${o.hint}</div>` : ''}</div>`;
const sw = (id, label, on) => `<label class="sw"><input type="checkbox" id="${id}" ${on ? 'checked' : ''}><i></i><span>${label}</span></label>`;
const val = id => { const e = $('#' + id); return e ? (e.type === 'checkbox' ? (e.checked ? '1' : '0') : e.value.trim()) : ''; };
function needJar(box) { if (INFO && !INFO.cfg.ANDROID_JAR) { const d = document.createElement('div'); d.className = 'card'; d.style.cssText = 'background:var(--warnbg);margin-bottom:16px'; d.innerHTML = `<b>android.jar is not set.</b> APKB needs one file from an Android SDK platform to build. <a href="#/settings">Set it in Settings</a> (once, saved).`; box.prepend(d); } }

/* ----------------------------------------------------------------------- pages */
const P = {};
P.home = el => {
  el.innerHTML = `<div class="hero"><span class="chip">Lab Edition · v${esc(INFO.version)}</span><h1 style="margin-top:14px">Build Android apps right from your pocket.</h1><p>APKB turns raw Java projects and web pages into real APKs — no Gradle, no Flutter. This page is a live window into your Termux / Linux session: it does all the work, the browser just shows it.</p><div class="row"><a class="btn g" href="#/try">Try Before Build</a><a class="btn" href="#/build">Build an APK</a><a class="btn o" href="#/html">HTML → APK</a></div></div>
  <div class="grid">${[['try', 'Try Before Build', 'Run your app in a phone frame before it is built, with touch, resources and browser permission prompts.'], ['build', 'Build APK', 'Zip or folder in, unsigned APK out, with automatic fixes and verification.'], ['html', 'HTML → APK', 'Wrap a page, HTML5 project or website into a WebView app with dozens of options.'], ['analyze', 'Analyze', 'See the project layout and every problem with its exact file and line.'], ['inspect', 'APK Inspector', 'Package, SDK, permissions, signature and the heaviest files of any APK.'], ['new', 'New project', 'Start from a flat, Gradle-like or Eclipse-like raw Java template.'], ['doctor', 'Lab Doctor', 'Check and auto-install every tool the lab needs.'], ['history', 'History & Logs', 'Past builds, logs of failures, and workspace cleanup.']].map(([k, t, d]) => `<a class="card" href="#/${k}"><div class="ico">${ico(k)}</div><h3>${t}</h3><p>${d}</p></a>`).join('')}</div>
  <div class="card" style="margin-top:20px"><h3 style="margin-top:0">Lab status</h3><div class="row" id="st" style="margin-top:12px"><span class="hint">Checking tools…</span></div></div>`;
  needJar($('.hero').parentNode); loadDoctor().then(() => { const st = $('#st'); if (st) st.innerHTML = doctorChips(); });
};
let docPromise;
function loadDoctor(force) { if (!docPromise || force) docPromise = new Promise(async res => { const d = { tools: {}, meta: {} }; try { const j = await api('jobs', { body: { kind: 'doctor' } }); const es = new EventSource('/api/jobs/' + j.id + '/events'); es.onmessage = m => { const e = JSON.parse(m.data); if (e.t === 'meta') { if (e.k.startsWith('tool.')) d.tools[e.k.slice(5)] = e.v; else d.meta[e.k] = e.v; } if (e.t === 'done') { es.close(); DOC = d; res(d); } }; } catch { res(d); } }); return docPromise; }
const doctorChips = () => !DOC ? '' : ['java', 'aapt2', 'aapt', 'd8', 'dx', 'ecj', 'javac', 'zipalign', 'zip', 'unzip', 'python3'].map(t => `<span class="chip ${DOC.tools[t] ? 'ok' : 'no'}">${t}</span>`).join('') + `<span class="chip ${DOC.meta.android_jar ? 'ok' : 'no'}">android.jar${DOC.meta.jar_api ? ' · API ' + DOC.meta.jar_api : ''}</span>`;

P.build = el => {
  const last = ls.get('build', {});
  el.innerHTML = head('Build APK', 'Give a project as a .zip or folder — any layout works. APKB finds the manifest, resources, Java files and libraries, fixes what it can, and builds an unsigned APK.') + `<div class="col">
  <div class="seg" id="bm"><button class="on" data-m="proj">My project</button><button data-m="test">Test APK (Example app)</button></div>
  <div class="card" id="bproj">${pathField('bp', 'Project (.zip or folder)', { val: last.path, hint: 'A zip with a folder inside, files directly inside, or a project folder.' })}</div>
  <details class="acc"><summary>Build options</summary><div><div class="fields">
  ${field('o_TYPE', 'Build type', { opts: [['Release', 'release'], ['Debuggable', 'debug']], val: 'release' })}${field('o_MIN', 'Min SDK', { type: 'number', ph: 'auto' })}${field('o_TARGET', 'Target SDK', { type: 'number', ph: 'auto' })}${field('o_VNAME', 'Version name', { ph: 'auto' })}${field('o_VCODE', 'Version code', { type: 'number', ph: 'auto' })}${field('o_PKG', 'Package id', { ph: 'keep' })}${field('o_NAME', 'App name', { ph: 'keep' })}
  ${field('o_LEVEL', 'Java level', { opts: [['Auto (1.8 → 11 → 17)', 'auto'], ['Java 8', '1.8'], ['Java 11', '11'], ['Java 17', '17']] })}${field('o_COMPILER', 'Java compiler', { opts: [['Auto', 'auto'], ['ecj', 'ecj'], ['javac', 'javac']] })}${field('o_RESENG', 'Resource engine', { opts: [['Auto', 'auto'], ['aapt2', 'aapt2'], ['aapt (classic)', 'aapt']] })}
  ${field('o_ABI', 'ABI filter', { val: 'all', hint: 'all, or e.g. arm64-v8a,armeabi-v7a' })}${field('o_OUTNAME', 'Output file name', { ph: 'auto' })}</div>
  <div class="switches" style="margin-top:8px">${sw('o_ZIPALIGN', 'Zipalign', 1)}${sw('o_KEEP', 'Keep work folder', 0)}${sw('o_VERBOSE', 'Verbose output', 0)}</div></div></details>
  <div class="row"><button class="btn g" id="go">Build APK</button><button class="btn o" id="tryit">Try Before Build first</button></div><div id="job"></div></div>`;
  needJar(el); bindPaths(el); let mode = 'proj';
  $$('#bm button').forEach(b => b.onclick = () => { mode = b.dataset.m; $$('#bm button').forEach(x => x.classList.toggle('on', x === b)); $('#bproj').style.display = mode === 'proj' ? '' : 'none'; $('#tryit').style.display = mode === 'proj' ? '' : 'none'; });
  $('#tryit').onclick = () => { ls.set('tryPath', val('bp')); location.hash = '#/try'; };
  $('#go').onclick = async () => {
    const opts = {}; for (const k of ['TYPE', 'MIN', 'TARGET', 'VNAME', 'VCODE', 'PKG', 'NAME', 'LEVEL', 'COMPILER', 'RESENG', 'ABI', 'OUTNAME', 'ZIPALIGN', 'KEEP', 'VERBOSE']) { const v = val('o_' + k); if (v && v !== 'auto') opts[k] = v; }
    const path = val('bp'); if (mode === 'proj') { if (!path) return toast('Choose a project first'); ls.set('build', { path }); }
    $('#go').disabled = true; await runJob($('#job'), mode === 'proj' ? { kind: 'build', path, opts } : { kind: 'test', opts }); $('#go').disabled = false;
  };
};

const HTML_D = { APP_NAME: 'My Web App', PKG: '', VERSION_NAME: '1.0', VERSION_CODE: '1', MIN_SDK: '21', TARGET_SDK: '34', ORIENTATION: 'auto', DISPLAY: 'normal', THEME: 'light', ACTIONBAR: '0', BG_COLOR: '', STATUS_COLOR: '', NAV_COLOR: '', ICON: '', SPLASH: 'none', SPLASH_IMAGE: '', SPLASH_BG: '', SPLASH_FG: '', SPLASH_MS: '1500', SPLASH_TAGLINE: '', SPLASH_VERSION: '1', SPLASH_SPINNER: '1', EXTERNAL: 'browser', UA: 'default', UA_CUSTOM: '', CACHE: 'default', ORIGIN: 'file', BRIDGE_NAME: 'Android', JS: '1', DOM: '1', FILE_ACCESS: '1', MIXED: '1', ZOOM: '0', LONGPRESS: '1', SELECT: '1', AUTOPLAY: '1', UPLOAD: '1', DOWNLOADS: '1', JS_DIALOGS: '1', FS_VIDEO: '1', BACK_NAV: '1', DOUBLE_BACK: '0', KEEP_ON: '0', PROGRESS: '0', SCROLLBARS: '0', BRIDGE: '1', OFFLINE_PAGE: '1', CLEAR_CACHE: '0', DEBUG: '0', CLEARTEXT: '1', BACKUP: '0', P_INTERNET: '1', P_CAMERA: '0', P_MIC: '0', P_LOCATION: '0', P_STORAGE: '0', P_VIBRATE: '0', P_WAKE: '0', P_NOTIFY: '0', P_BLUETOOTH: '0' };
const PERMS = [['P_INTERNET', 'Internet'], ['P_CAMERA', 'Camera'], ['P_MIC', 'Microphone'], ['P_LOCATION', 'Location (GPS)'], ['P_STORAGE', 'Files / media read'], ['P_VIBRATE', 'Vibrate'], ['P_WAKE', 'Keep CPU awake (wake lock)'], ['P_NOTIFY', 'Notifications (Android 13+)'], ['P_BLUETOOTH', 'Bluetooth']];
const FEATS = [['JS', 'JavaScript'], ['DOM', 'DOM storage (localStorage, IndexedDB)'], ['FILE_ACCESS', 'Allow file:// pages to read other local files'], ['MIXED', 'Allow mixed http/https content'], ['ZOOM', 'Pinch to zoom'], ['LONGPRESS', 'Allow long-press'], ['SELECT', 'Allow text selection'], ['AUTOPLAY', 'Media autoplay (no tap needed)'], ['UPLOAD', 'File upload (<input type=file>)'], ['DOWNLOADS', 'Downloads incl. blob:/data: (save to Downloads)'], ['JS_DIALOGS', 'JS alert / confirm / prompt dialogs'], ['FS_VIDEO', 'Fullscreen video'], ['BACK_NAV', 'Back button goes to previous page'], ['DOUBLE_BACK', 'Double back to exit'], ['KEEP_ON', 'Keep screen on'], ['PROGRESS', 'Top loading bar'], ['SCROLLBARS', 'Show scrollbars'], ['BRIDGE', 'Native JS bridge (window.Android.toast/vibrate/share/copy/exit)'], ['OFFLINE_PAGE', 'Friendly offline/error page'], ['CLEAR_CACHE', 'Clear cache on every start'], ['CLEARTEXT', 'Allow http:// (cleartext) traffic'], ['DEBUG', 'WebView remote debugging (chrome://inspect)'], ['BACKUP', 'Allow Android backup']];
P.html = el => {
  const F = Object.assign({}, HTML_D, ls.get('htmlLast', {})); const col = id => `<div><label class="f">${id.label}</label><div class="pathbox"><input type="text" id="h_${id.k}" value="${esc(F[id.k])}" placeholder="auto  (#RRGGBB)"><input type="color" value="${/^#[0-9a-f]{6}$/i.test(F[id.k]) ? F[id.k] : '#ffffff'}" style="width:46px;height:44px;border:0;background:none;padding:0" data-cp="h_${id.k}"></div></div>`;
  el.innerHTML = head('HTML → APK', 'Turn a web page, HTML5 project, .zip or website into a real WebView app. Every option of the terminal wizard is here.') + `<div class="col">
  <div class="card col"><div class="seg" id="hm"><button class="on" data-m="local">Local files</button><button data-m="url">Website URL</button></div>
  <div id="hl">${pathField('h_src', 'HTML file, HTML5 project folder, or .zip', { ext: 'html,htm,zip', val: ls.get('htmlSrc', '') })}<div class="fields" style="margin-top:12px">${field('h_entry', 'Start page (only if there is no index.html)', { ph: 'e.g. app.html' })}</div>${sw('h_sib', 'Include the other files next to a single .html (css / js / images)', 1)}</div>
  <div id="hu" style="display:none">${field('h_url', 'Website address', { ph: 'https://example.com' })}</div></div>
  <details class="acc" open><summary>Identity</summary><div><div class="fields">${field('h_APP_NAME', 'App name (any language)', { val: F.APP_NAME })}${field('h_PKG', 'Package id', { val: F.PKG, ph: 'auto: com.apkb.<name>' })}${field('h_VERSION_NAME', 'Version name', { val: F.VERSION_NAME })}${field('h_VERSION_CODE', 'Version code', { val: F.VERSION_CODE, type: 'number' })}${field('h_MIN_SDK', 'Minimum Android API', { val: F.MIN_SDK, type: 'number', hint: '21 = Android 5.0, 24 = 7.0, 26 = 8.0' })}${field('h_TARGET_SDK', 'Target Android API', { val: F.TARGET_SDK, type: 'number' })}</div><div style="margin-top:14px">${pathField('h_ICON', 'App icon (PNG recommended)', { ext: 'png,jpg,jpeg,webp,gif,bmp', dir: false, val: F.ICON, hint: 'Empty = built-in lab icon.' })}</div></div></details>
  <details class="acc"><summary>Display</summary><div><div class="fields">${field('h_ORIENTATION', 'Screen orientation', { val: F.ORIENTATION, opts: [['Auto (follow system)', 'auto'], ['Portrait only', 'portrait'], ['Landscape only', 'landscape'], ['Portrait (sensor)', 'sensorPortrait'], ['Landscape (sensor)', 'sensorLandscape'], ['Free rotation', 'fullSensor']] })}${field('h_DISPLAY', 'Screen mode', { val: F.DISPLAY, opts: [['Normal (status + navigation bars)', 'normal'], ['Fullscreen', 'fullscreen'], ['Immersive', 'immersive']] })}${field('h_THEME', 'Theme', { val: F.THEME, opts: [['Light', 'light'], ['Dark', 'dark']] })}${col({ k: 'BG_COLOR', label: 'Page background color' })}${col({ k: 'STATUS_COLOR', label: 'Status bar color' })}${col({ k: 'NAV_COLOR', label: 'Navigation bar color' })}</div>${sw('h_ACTIONBAR', 'Show the native title bar (action bar)', F.ACTIONBAR === '1')}</div></details>
  <details class="acc"><summary>Splash screen</summary><div><div class="fields">${field('h_SPLASH', 'Splash screen', { val: F.SPLASH, opts: [['No splash', 'none'], ['Auto info (icon + name + version)', 'auto'], ['My image (9:16)', 'image']] })}${field('h_SPLASH_TAGLINE', 'Tagline', { val: F.SPLASH_TAGLINE })}${col({ k: 'SPLASH_BG', label: 'Splash background' })}${col({ k: 'SPLASH_FG', label: 'Splash text color' })}${field('h_SPLASH_MS', 'Minimum splash time (ms)', { val: F.SPLASH_MS, type: 'number' })}</div><div class="switches">${sw('h_SPLASH_VERSION', 'Show version number', F.SPLASH_VERSION === '1')}${sw('h_SPLASH_SPINNER', 'Show loading spinner', F.SPLASH_SPINNER === '1')}</div><div style="margin-top:12px">${pathField('h_SPLASH_IMAGE', 'Splash image (portrait 9:16 works best)', { ext: 'png,jpg,jpeg,webp', dir: false, val: F.SPLASH_IMAGE })}</div></div></details>
  <details class="acc"><summary>Permissions</summary><div><div class="switches">${PERMS.map(([k, l]) => sw('h_' + k, l, F[k] === '1')).join('')}</div></div></details>
  <details class="acc"><summary>WebView features</summary><div><div class="switches">${FEATS.map(([k, l]) => sw('h_' + k, esc(l), F[k] === '1')).join('')}</div></div></details>
  <details class="acc"><summary>Advanced</summary><div><div class="fields">${field('h_EXTERNAL', 'Links to other websites', { val: F.EXTERNAL, opts: [['Open in the phone browser', 'browser'], ['Open inside the app', 'inside']] })}${field('h_UA', 'User agent', { val: F.UA, opts: [['Default mobile', 'default'], ['Desktop site', 'desktop'], ['Custom', 'custom']] })}${field('h_UA_CUSTOM', 'Custom user-agent', { val: F.UA_CUSTOM })}${field('h_CACHE', 'Cache mode', { val: F.CACHE, opts: [['Default', 'default'], ['No cache', 'none'], ['Prefer cache (offline friendly)', 'prefer']] })}${field('h_ORIGIN', 'How local pages are loaded', { val: F.ORIGIN, opts: [['file:///android_asset (best for video/audio)', 'file'], ['https://apkb.local virtual origin (modules, fetch)', 'https']] })}${field('h_BRIDGE_NAME', 'JS bridge object name', { val: F.BRIDGE_NAME })}${field('h_TYPE', 'Build type', { opts: [['Release', 'release'], ['Debuggable', 'debug']] })}</div>${sw('h_saveSrc', 'Also save the generated Java project (to edit later)', 0)}</div></details>
  <div class="row"><button class="btn g" id="go">Build this app</button></div><div id="job"></div></div>`;
  needJar(el); bindPaths(el); let mode = 'local';
  $$('#hm button').forEach(b => b.onclick = () => { mode = b.dataset.m; $$('#hm button').forEach(x => x.classList.toggle('on', x === b)); $('#hl').style.display = mode === 'local' ? '' : 'none'; $('#hu').style.display = mode === 'url' ? '' : 'none'; });
  $$('[data-cp]').forEach(c => c.oninput = () => $('#' + c.dataset.cp).value = c.value);
  $('#go').onclick = async () => {
    const form = {}; for (const k in HTML_D) { const v = val('h_' + k); if (v !== '' || $('#h_' + k)) form[k] = v; }
    ls.set('htmlLast', form); ls.set('htmlSrc', val('h_src'));
    const source = mode === 'url' ? { mode: 'url', url: val('h_url') } : { mode: 'local', path: val('h_src'), siblings: val('h_sib') === '1', entry: val('h_entry') };
    if (mode === 'local' && !source.path) return toast('Choose the HTML file or project first');
    $('#go').disabled = true; await runJob($('#job'), { kind: 'html', form, source, opts: { TYPE: val('h_TYPE') || 'release' }, saveSrc: val('h_saveSrc') === '1' }); $('#go').disabled = false;
  };
};

const diagList = (arr, click) => arr.length ? arr.map((d, i) => `<div class="diag ${d.sev}" data-i="${i}"><b>${d.sev}</b><div><div>${esc(d.msg)}</div>${d.file ? `<small>${esc(d.file)}${d.line ? ':' + d.line : ''}</small>` : ''}${d.hint ? `<div class="hint">${esc(d.hint)}</div>` : ''}</div></div>`).join('') : '<div class="empty">No problems found ✔</div>';
P.analyze = el => {
  el.innerHTML = head('Analyze', 'A dry scan of any project layout. Every problem is reported with its exact file and line — before you spend time on a build.') + `<div class="card col">${pathField('ap', 'Project (.zip or folder)', { val: ls.get('build', {}).path })}<div class="row"><button class="btn g" id="go">Analyze</button></div></div><div id="out" style="margin-top:18px"></div>`;
  bindPaths(el);
  $('#go').onclick = async () => {
    const out = $('#out'); out.innerHTML = '<div class="empty">Scanning in Termux…</div>';
    try {
      const r = await api('analyze', { body: { path: val('ap') } }), c = r.counts;
      out.innerHTML = `<div class="grid">${[['Layout', r.layout || 'unknown'], ['Package', r.package || r.env.GUESS_PACKAGE || '—'], ['Launcher', (r.launcher || r.env.GUESS_ACTIVITY || '—').split('.').pop()], ['SDK', 'min ' + r.minSdk + ' · target ' + r.targetSdk], ['Java files', c.java], ['Resource folders', c.res], ['Asset folders', c.assets], ['Libraries', `${c.jar} jar · ${c.aar} aar · ${c.so} .so`]].map(([k, v]) => `<div class="card"><div class="hint">${k}</div><b style="font-size:18px">${esc(v)}</b></div>`).join('')}</div>
      <h3 style="margin:26px 0 12px">Findings</h3>${diagList(r.diagnostics)}<div class="row" style="margin-top:14px"><button class="btn" id="b2">Build it</button><button class="btn g" id="t2">Try Before Build</button></div>`;
      $('#b2').onclick = () => { ls.set('build', { path: val('ap') }); location.hash = '#/build'; }; $('#t2').onclick = () => { ls.set('tryPath', val('ap')); location.hash = '#/try'; };
    } catch (e) { out.innerHTML = `<div class="res bad">${esc(e.message)}</div>`; }
  };
};

P.inspect = el => {
  el.innerHTML = head('APK Inspector', 'Package, SDK, permissions, signature state and the biggest entries of any APK file.') + `<div class="card col">${pathField('ip', 'APK file', { ext: 'apk', dir: false, val: ls.get('inspectPath', '') })}<div class="row"><button class="btn g" id="go">Inspect</button></div></div><div id="job" style="margin-top:16px"></div>`;
  bindPaths(el); $('#go').onclick = () => { ls.set('inspectPath', val('ip')); runJob($('#job'), { kind: 'inspect', path: val('ip') }); };
};
P.new = el => {
  el.innerHTML = head('New project', 'Create a small, complete raw-Java Android project that APKB can build and Try Before Build can run.') + `<div class="card col"><div class="fields">${field('n_style', 'Folder layout', { opts: [['Flat (AndroidManifest.xml, src/, res/, assets/)', 'flat'], ['Gradle-like (app/src/main/…)', 'gradle'], ['Eclipse/ADT-like (+ libs/)', 'eclipse']] })}${field('n_name', 'App name', { val: 'My App' })}${field('n_pkg', 'Package id', { val: 'com.apkb.myapp' })}</div><div class="row"><button class="btn g" id="go">Create project</button></div></div><div id="job" style="margin-top:16px"></div>`;
  $('#n_name').oninput = () => $('#n_pkg').value = 'com.apkb.' + ($('#n_name').value.toLowerCase().replace(/[^a-z0-9]/g, '') || 'app');
  $('#go').onclick = async () => { const r = await runJob($('#job'), { kind: 'scaffold', style: val('n_style'), name: val('n_name'), pkg: val('n_pkg') }); if (r && r.status === 'ok') { const d = r.meta.dest; $('.jres', $('#job')).insertAdjacentHTML('beforeend', `<div class="row" style="margin-top:12px"><button class="btn" id="bb">Build it</button><button class="btn g" id="tt">Try Before Build</button></div>`); $('#bb').onclick = () => { ls.set('build', { path: d }); location.hash = '#/build'; }; $('#tt').onclick = () => { ls.set('tryPath', d); location.hash = '#/try'; }; } };
};
P.doctor = el => {
  el.innerHTML = head('Lab Doctor', 'Checks every tool the lab needs in your Termux / Linux session and can install what is missing.') + `<div class="card"><div class="row" id="st"><span class="hint">Checking…</span></div><dl class="kv" id="dk"></dl><div class="row"><button class="btn g" id="fix">Install / repair missing packages</button><button class="btn o" id="re">Re-check</button></div></div><div id="job" style="margin-top:16px"></div>`;
  const show = async f => { const d = await loadDoctor(f); $('#st').innerHTML = doctorChips(); $('#dk').innerHTML = [['Platform', d.meta.platform + ' · ' + d.meta.pm], ['APKB', d.meta.apkb], ['Java', d.meta.java_version || 'not installed'], ['android.jar', (d.meta.android_jar || 'not set') + (d.meta.jar_api ? ' (API ' + d.meta.jar_api + ')' : '')], ['Output', d.meta.out_dir + (d.meta.out_writable === '0' ? '  ▲ not writable (Termux: termux-setup-storage)' : '')], ['Free RAM', (d.meta.ram_mb || '?') + ' MB'], ['Pillow', d.meta.pillow === '1' ? 'available (icon resizing)' : 'missing']].map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join(''); };
  show(); $('#re').onclick = () => show(true); $('#fix').onclick = async () => { await runJob($('#job'), { kind: 'install' }); show(true); };
};
P.settings = async el => {
  const c = INFO.cfg;
  el.innerHTML = head('Settings', 'Saved in your Termux home (~/.apkb/config) — shared with the terminal version.') + `<div class="card col">${pathField('s_jar', 'android.jar (file, or a folder that contains it)', { val: c.ANDROID_JAR, hint: 'From an Android SDK platform. Asked once, then saved.' })}${pathField('s_out', 'Output folder for APKs', { val: c.OUT_DIR || '' })}<div class="fields">${field('s_comp', 'Java compiler', { val: c.JAVA_COMPILER || 'auto', opts: [['Auto', 'auto'], ['ecj', 'ecj'], ['javac', 'javac']] })}${field('s_res', 'Resource engine', { val: c.RES_ENGINE || 'auto', opts: [['Auto', 'auto'], ['aapt2', 'aapt2'], ['aapt (classic)', 'aapt']] })}</div><div class="switches">${sw('s_zip', 'Zipalign', c.DO_ZIPALIGN !== '0')}${sw('s_keep', 'Keep work folders', c.KEEP_WORK === '1')}${sw('s_ver', 'Verbose output', c.VERBOSE === '1')}</div><div class="row"><button class="btn g" id="save">Save settings</button><button class="btn o" id="reset">Reset all</button></div></div>`;
  bindPaths(el);
  $('#save').onclick = async () => { try { const r = await api('settings', { body: { ANDROID_JAR: val('s_jar'), OUT_DIR: val('s_out'), JAVA_COMPILER: val('s_comp'), RES_ENGINE: val('s_res'), DO_ZIPALIGN: val('s_zip'), KEEP_WORK: val('s_keep'), VERBOSE: val('s_ver') } }); INFO.cfg = r.cfg; $('#s_jar').value = r.cfg.ANDROID_JAR || ''; docPromise = null; toast('Settings saved'); } catch (e) { toast(e.message); } };
  $('#reset').onclick = async () => { if (confirm('Delete all APKB settings?')) { await api('settings/reset', { body: {} }); INFO = await api('info'); toast('Settings reset'); P.settings(el); } };
};
P.history = async el => {
  el.innerHTML = head('History & Logs', 'Every build, and the log of every failed one. Failed builds also leave a log file in your output folder.') + '<div id="hh" class="card"><div class="empty">Loading…</div></div>';
  const load = async () => {
    const r = await api('history');
    $('#hh').innerHTML = `<h3 style="margin:0 0 10px">Builds</h3>${r.history.length ? `<table><tr><th>Time</th><th>Project</th><th>Result</th></tr>${r.history.map(h => `<tr><td>${esc(h.time)}</td><td>${esc(h.project)}</td><td>${h.result === 'FAILED' ? '<span class="chip no">failed</span>' : esc(h.result.split('/').pop())}</td></tr>`).join('')}</table>` : '<div class="empty">No builds yet.</div>'}
    <h3 style="margin:26px 0 10px">Log files</h3>${r.logs.length ? `<table>${r.logs.map(l => `<tr><td>${l.failed ? '<span class="chip no">failed</span> ' : ''}${esc(l.name)}</td><td>${hsize(l.size)}</td><td style="text-align:right"><a class="btn o sm" href="/api/logfile?path=${encodeURIComponent(l.path)}" download>Download</a></td></tr>`).join('')}</table>` : '<div class="empty">No logs.</div>'}
    <h3 style="margin:26px 0 10px">Clean workspace</h3><div class="row"><button class="btn o" id="cw">Delete temporary work folders</button><button class="btn o" id="cl">Delete saved logs</button></div>`;
    $('#cw').onclick = async () => { await api('clean', { body: { work: 1 } }); toast('Work folders cleaned'); }; $('#cl').onclick = async () => { await api('clean', { body: { logs: 1 } }); toast('Logs removed'); load(); };
  };
  load();
};

/* ---------------------------------------------------------------- Try Before Build page */
P.try = el => {
  el.innerHTML = head('Try Before Build', 'Run your app in a phone frame <i>before</i> it is built — with your real layouts, resources, assets and Java code. Camera and other permission requests become the browser’s own permission prompts.') + `<div class="card col" id="tsrc">${pathField('tp', 'Project (.zip or folder)', { val: ls.get('tryPath', ls.get('build', {}).path || '') , hint: 'Works with the projects APKB can build. A safe editable copy is made in the lab workspace.' })}<div class="row"><button class="btn g" id="go">Run in phone frame</button></div></div><div id="tbody" style="margin-top:22px"></div>`;
  bindPaths(el); let tryId = null, ctl = null;
  const stop = () => { if (ctl) { ctl.stop(); ctl = null; } }; CUR = { stop };
  const boot = async (keepId) => {
    stop(); const b = $('#tbody'); b.innerHTML = '<div class="empty">Termux is reading your project…</div>';
    let bundle; try { bundle = await api('try/prepare', { body: { path: val('tp'), id: keepId || undefined } }); } catch (e) { b.innerHTML = `<div class="res bad"><h3>Cannot open this project</h3>${esc(e.message)}</div>`; return; }
    ls.set('tryPath', val('tp')); tryId = bundle.id;
    b.innerHTML = `<div class="try"><div id="phone"></div><div><div class="tabs" id="tt"><button data-t="con" class="on">Console</button><button data-t="prob">Problems <span id="pc"></span></button><button data-t="files">Files & editor</button><button data-t="dev">Device</button></div><div id="tp_con"></div><div id="tp_prob" hidden></div><div id="tp_files" hidden></div><div id="tp_dev" hidden></div></div></div>`;
    const tabs = t => { $$('#tt button').forEach(x => x.classList.toggle('on', x.dataset.t === t)); ['con', 'prob', 'files', 'dev'].forEach(k => $('#tp_' + k).hidden = k !== t); };
    $$('#tt button').forEach(x => x.onclick = () => tabs(x.dataset.t));
    const probs = [...bundle.diagnostics]; const drawProbs = () => { const w = probs.filter(d => d.sev !== 'info'); $('#pc').textContent = w.length ? '(' + w.length + ')' : ''; $('#tp_prob').innerHTML = `<div class="hint" style="margin-bottom:10px">Click a finding to open the exact file and line.</div>` + diagList(probs); $$('#tp_prob .diag').forEach(d => d.onclick = () => { const x = probs[+d.dataset.i]; if (x.file) openFile(x.file, x.line); }); };
    const con = $('#tp_con'); con.innerHTML = '<div class="console" style="min-height:300px"></div><div class="row" style="margin-top:10px"><button class="btn o sm" id="clr">Clear</button></div>'; const cc = $('.console', con); $('#clr').onclick = () => cc.innerHTML = '';
    const clog = (lv, msg, loc) => { const d = document.createElement('div'); d.className = lv === 'error' ? 'er' : lv === 'warn' ? 'wn' : lv === 'info' ? 'in' : ''; d.textContent = (loc ? `[${loc.file}:${loc.line}] ` : '') + msg; cc.append(d); cc.scrollTop = cc.scrollHeight; if (loc && (lv === 'error')) { probs.unshift({ sev: 'error', file: loc.file, line: loc.line, msg, hint: 'Runtime error while the preview was running.' }); drawProbs(); } };
    drawProbs();
    // editor
    const ft = $('#tp_files'); ft.innerHTML = `<div class="editor"><div class="ftree"></div><div><div class="row" style="margin-bottom:8px"><b id="cf" class="hint">Select a file</b><span class="sp"></span><button class="btn g sm" id="sv" disabled>Save & reload</button></div><textarea class="code" id="code" spellcheck="false" disabled></textarea></div></div><div class="row" style="margin-top:14px"><a class="btn o sm" href="/api/ws/${tryId}/zip">${ico('dl')} Export workspace (.zip)</a><button class="btn sm" id="wsb">Build this workspace</button></div><div id="wsjob" style="margin-top:12px"></div>`;
    let curf = null; async function openFile(p, line) { tabs('files'); try { const r = await api(`ws/${tryId}/file?path=${encodeURIComponent(p)}`); curf = p; const ta = $('#code'); ta.disabled = false; ta.value = r.text; $('#cf').textContent = p; $('#sv').disabled = false; $$('.ftree div').forEach(d => d.classList.toggle('on', d.dataset.p === p)); if (line) { const ls_ = r.text.split('\n'); let pos = 0; for (let i = 0; i < line - 1; i++) pos += ls_[i].length + 1; ta.focus(); ta.setSelectionRange(pos, pos + (ls_[line - 1] || '').length); ta.scrollTop = Math.max(0, (line - 4) * 19.4); } } catch (e) { toast(e.message); } }
    api(`ws/${tryId}/tree`).then(r => { $('.ftree').innerHTML = r.files.map(f => `<div data-p="${esc(f.path)}">${esc(f.path)}</div>`).join(''); $$('.ftree div').forEach(d => d.onclick = () => openFile(d.dataset.p)); });
    $('#sv').onclick = async () => { await api(`ws/${tryId}/file?path=${encodeURIComponent(curf)}`, { method: 'PUT', body: { text: $('#code').value } }); toast('Saved — reloading'); boot(tryId); };
    $('#wsb').onclick = async () => { const j = await api(`ws/${tryId}/build`, { body: {} }); runJob($('#wsjob'), { kind: 'build', __existing: j }); };
    // phone
    if (!window.APKB || !APKB.startTry) { clog('error', 'The Try Before Build runtime failed to load'); return; }
    const drawDev = () => { const c = ctl; if (!c || !$('#tp_dev')) return; const i = c.info(); const dev = $('#tp_dev'); if (!dev.dataset.init) { dev.dataset.init = 1; dev.innerHTML = `<div class="fields">${field('dv_dev', 'Device', { opts: c.devices.map(d => [d, d]) })}${field('dv_font', 'Font scale', { opts: [['0.85×', 0.85], ['1×', 1], ['1.15×', 1.15], ['1.3×', 1.3]], val: 1 })}</div><div class="row" style="margin:12px 0"><button class="btn o sm" id="dv_rot">⟳ Rotate</button><button class="btn o sm" id="dv_dark">☾ Dark mode</button></div><div id="dv_info"></div>`; $('#dv_dev').onchange = e => c.setDevice(e.target.value); $('#dv_font').onchange = e => c.setFont(+e.target.value); $('#dv_rot').onclick = () => c.rotate(); $('#dv_dark').onclick = () => c.setDark(!c.info().dark); } $('#dv_info').innerHTML = `<h3 style="font-size:17px;margin:14px 0 6px">Screens</h3>${i.stack.map((s, k) => `<div class="hint">${k + 1}. ${esc(s.name)} — ${s.state}</div>`).join('') || '<div class="hint">none</div>'}<h3 style="font-size:17px;margin:14px 0 6px">Permissions</h3>${i.declared.map(p => `<div class="hint"><span class="chip ${i.granted.includes(p) ? 'ok' : 'no'}">${esc(p.replace('android.permission.', ''))}</span> ${i.granted.includes(p) ? 'granted' : 'not granted yet'}</div>`).join('') || '<div class="hint">No permissions declared in the manifest.</div>'}<h3 style="font-size:17px;margin:14px 0 6px">Not supported in the preview</h3>${i.unsupported.map(u => `<div class="hint">▲ ${esc(u.what)}${u.loc ? ' — ' + esc(u.loc.file) + ':' + u.loc.line : ''}</div>`).join('') || '<div class="hint">Nothing so far ✔</div>'}`; };
    ctl = APKB.startTry({ bundle, tryId, root: $('#phone'), log: clog, onState: () => { setTimeout(drawDev, 0); }, onBlocked: errs => { errs.forEach(e => probs.unshift({ sev: 'error', file: e.file, line: e.line, msg: e.msg, hint: e.hint || '' })); drawProbs(); tabs('prob'); } });
    drawDev();
  };
  $('#go').onclick = () => boot();
  window.__tryReload = boot;
};
/* ------------------------------------------------------------------------- router */
function render() {
  if (CUR) { try { CUR.stop(); } catch {} CUR = null; }
  const k = (location.hash.replace(/^#\//, '') || 'home').split('?')[0], pg = P[k] ? k : 'home';
  $$('.nav a').forEach(a => a.classList.toggle('on', a.dataset.k === pg));
  const m = $('#main'); m.innerHTML = ''; P[pg](m); window.scrollTo(0, 0);
}
async function init() {
  INFO = await api('info');
  const nav = NAV.map(([k, l, s]) => `<a href="#/${k}" data-k="${k}">${ico(k === 'try' ? 'try' : k)}<span>${l}</span>${s ? '<span class="star">NEW</span>' : ''}</a>`).join('');
  $('#app').innerHTML = `<div class="top"><div class="brand">${LOGO}<div><b>APKB</b><small>Android Package Kit Builder · Lab</small></div></div><nav class="nav">${nav}</nav></div><div class="shell"><aside class="side"><div class="brand">${LOGO}<div><b>APKB</b><small>Android Package Kit Builder<br>Lab Edition · v${esc(INFO.version)}</small></div></div><nav class="nav">${nav}</nav><span class="sp"></span><div class="hint" style="padding:10px 14px">Broadcasting from your Termux / Linux session.</div></aside><main class="main" id="main"></main></div>`;
  window.addEventListener('hashchange', render); render();
}
init().catch(e => { document.body.innerHTML = '<p style="padding:30px;font-family:sans-serif">APKB could not reach its server: ' + esc(e.message) + '<br>Open the full link printed in Termux.</p>'; });
})();
