#!/usr/bin/env python3
"""APKB :: Broadcast Into Browser server (Python stdlib only).

Termux/Linux does every piece of processing (the real APKB bash pipeline runs as
"jobs"); this server only streams progress/results to the browser UI in ../web.
"""
import argparse, json, mimetypes, os, re, shlex, shutil, signal, subprocess, sys, threading, time, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'py'))
sys.path.insert(0, HERE)
import trybundle  # noqa: E402

A = None          # parsed args
JOBS = {}         # id -> Job
JOB_LOCK = threading.Lock()
TRY = {}          # try workspace id -> dict
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')


def home(*p):
    return os.path.join(A.home, *p)


# --------------------------------------------------------------------- jobs
class Job:
    def __init__(self, kind, title):
        self.id = '%d-%s' % (int(time.time()), os.urandom(3).hex())
        self.kind, self.title = kind, title
        self.events, self.meta = [], {}
        self.status, self.rc = 'running', None
        self.proc = None
        self.cond = threading.Condition()
        self.logfile = home('jobs', self.id + '.log')
        self.started = time.time()

    def push(self, ev):
        with self.cond:
            self.events.append(ev)
            self.cond.notify_all()

    def finish(self, status, rc):
        self.status, self.rc = status, rc
        self.push({'t': 'done', 'status': status, 'rc': rc, 'meta': self.meta})

    def info(self):
        return {'id': self.id, 'kind': self.kind, 'title': self.title, 'status': self.status,
                'rc': self.rc, 'meta': self.meta, 'started': self.started}


def run_job(job, argv, env_extra=None, cwd=None):
    os.makedirs(home('jobs'), exist_ok=True)
    env = dict(os.environ)
    env['APKB_HOME'] = A.home
    env['PYTHONUNBUFFERED'] = '1'
    env['NO_COLOR'] = '1'
    env.update(env_extra or {})
    cmd = ['bash', os.path.join(A.root, 'apkb.sh'), '__job'] + argv
    try:
        job.proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, env=env, cwd=cwd or A.root,
                                    start_new_session=True, text=True, errors='replace', bufsize=1)
    except Exception as e:
        job.push({'t': 'log', 'line': 'Cannot start the job: %s' % e})
        job.finish('failed', -1)
        return
    log = open(job.logfile, 'w', encoding='utf-8')
    for raw in job.proc.stdout:
        line = ANSI.sub('', raw.rstrip('\n'))
        log.write(line + '\n'); log.flush()
        if line.startswith('@@APKB '):
            k, _, v = line[7:].partition('=')
            if k == 'step':
                job.push({'t': 'step', 'label': v})
            else:
                job.meta[k] = v
                job.push({'t': 'meta', 'k': k, 'v': v})
            continue
        job.push({'t': 'log', 'line': line})
        sys.stdout.write('  [%s] %s\n' % (job.kind, line[:140])) if line.strip() else None
        sys.stdout.flush()
    job.proc.wait()
    log.close()
    rc = job.proc.returncode
    if job.status == 'cancelled':
        return
    job.finish('ok' if rc == 0 else 'failed', rc)
    print('  [%s] finished: %s' % (job.kind, job.status)); sys.stdout.flush()


def start_job(kind, title, argv, env_extra=None):
    job = Job(kind, title)
    with JOB_LOCK:
        JOBS[job.id] = job
    threading.Thread(target=run_job, args=(job, argv, env_extra), daemon=True).start()
    print('  [%s] started: %s' % (kind, title)); sys.stdout.flush()
    return job


# ------------------------------------------------------------------ settings
CFG_KEYS = ['ANDROID_JAR', 'OUT_DIR', 'JAVA_COMPILER', 'RES_ENGINE', 'DO_ZIPALIGN', 'KEEP_WORK', 'VERBOSE']


def read_cfg():
    d = {}
    p = home('config')
    if os.path.exists(p):
        for ln in open(p, encoding='utf-8', errors='replace'):
            if '=' in ln:
                k, v = ln.rstrip('\n').split('=', 1)
                try:
                    parts = shlex.split(v)
                    d[k] = parts[0] if parts else ''
                except ValueError:
                    d[k] = v
    return d


def write_cfg(upd):
    d = read_cfg()
    d.update({k: str(v) for k, v in upd.items() if k in CFG_KEYS})
    with open(home('config'), 'w', encoding='utf-8') as f:
        for k, v in d.items():
            f.write('%s=%s\n' % (k, shlex.quote(v)))
    return d


def valid_jar(p):
    try:
        with zipfile.ZipFile(p) as z:
            return 'android/app/Activity.class' in z.namelist()
    except Exception:
        return False


def find_jar(p):
    if os.path.isfile(p):
        return p
    best = ''
    for dp, dn, fn in os.walk(p):
        if dp[len(p):].count(os.sep) > 5:
            dn[:] = []
        if 'android.jar' in fn:
            best = os.path.join(dp, 'android.jar')
    return best


def history():
    out = []
    p = home('history.log')
    if os.path.exists(p):
        for ln in open(p, encoding='utf-8', errors='replace').read().splitlines()[-60:]:
            f = ln.split('\t')
            if len(f) >= 3:
                out.append({'time': f[0], 'project': f[1], 'result': f[2], 'size': f[3] if len(f) > 3 else ''})
    return out[::-1]


def list_logs():
    res = []
    for d in (home('logs'), os.path.join(read_cfg().get('OUT_DIR') or '', 'logs')):
        if d and os.path.isdir(d):
            for n in os.listdir(d):
                if n.endswith('.log'):
                    fp = os.path.join(d, n)
                    res.append({'name': n, 'path': fp, 'size': os.path.getsize(fp), 'mtime': os.path.getmtime(fp),
                                'failed': n.endswith('-FAILED.log')})
    res.sort(key=lambda x: -x['mtime'])
    return res[:80]


# ---------------------------------------------------------------------- http
class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'APKB'

    def log_message(self, *a):
        pass

    # --- helpers
    def json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(b)

    def err(self, code, msg):
        self.json({'error': msg}, code)

    def body(self):
        n = int(self.headers.get('Content-Length') or 0)
        return json.loads(self.rfile.read(n) or b'{}') if n else {}

    def authed(self):
        ck = self.headers.get('Cookie') or ''
        return ('apkb_token=' + A.token) in ck or self.headers.get('X-APKB-Token') == A.token

    def host_ok(self):
        h = (self.headers.get('Host') or '').split(':')[0]
        if A.host == '0.0.0.0':
            return True
        return h in ('127.0.0.1', 'localhost', '[::1]')

    def file(self, path, download=None, ctype=None, inline_text=False):
        if not os.path.isfile(path):
            return self.err(404, 'File not found')
        size = os.path.getsize(path)
        ct = ctype or mimetypes.guess_type(path)[0] or 'application/octet-stream'
        if ct.startswith('text/') or ct in ('application/javascript', 'application/json'):
            ct += '; charset=utf-8'
        rng = self.headers.get('Range')
        start, end, code = 0, size - 1, 200
        if rng and rng.startswith('bytes='):
            a, _, b = rng[6:].partition('-')
            try:
                start = int(a) if a else 0
                end = int(b) if b else size - 1
                code = 206
            except ValueError:
                pass
        self.send_response(code)
        self.send_header('Content-Type', ct)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1))
        if code == 206:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
        if download:
            self.send_header('Content-Disposition', 'attachment; filename="%s"' % download.replace('"', ''))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        with open(path, 'rb') as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(65536, left))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except Exception:
                    break
                left -= len(chunk)

    # --- routing
    def do_GET(self):
        self.route('GET')

    def do_POST(self):
        self.route('POST')

    def do_PUT(self):
        self.route('PUT')

    def do_DELETE(self):
        self.route('DELETE')

    def route(self, method):
        try:
            if not self.host_ok():
                return self.err(403, 'Bad host')
            u = urlparse(self.path)
            q = parse_qs(u.query)
            path = unquote(u.path)
            if path == '/' and q.get('t', [''])[0] == A.token:
                self.send_response(302)
                self.send_header('Set-Cookie', 'apkb_token=%s; Path=/; HttpOnly; SameSite=Strict' % A.token)
                self.send_header('Location', '/')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if not self.authed():
                b = b'<h3 style="font-family:sans-serif">APKB: open the full link printed in Termux (it contains ?t=...)</h3>'
                self.send_response(401)
                self.send_header('Content-Type', 'text/html')
                self.send_header('Content-Length', str(len(b)))
                self.end_headers()
                self.wfile.write(b)
                return
            if path.startswith('/api/'):
                return self.api(method, path[5:], q)
            if path.startswith('/try/'):
                return self.try_files(path[5:], q)
            if path == '/':
                path = '/index.html'
            fp = os.path.normpath(os.path.join(A.root, 'web', path.lstrip('/')))
            if not fp.startswith(os.path.join(A.root, 'web')):
                return self.err(403, 'Forbidden')
            return self.file(fp)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:  # never kill the server
            try:
                self.err(500, '%s: %s' % (type(e).__name__, e))
            except Exception:
                pass

    # --- API
    def api(self, method, p, q):
        if p == 'info':
            cfg = read_cfg()
            return self.json({'version': A.version, 'home': A.home, 'cfg': cfg, 'history': history(),
                              'cwd': os.path.expanduser('~'), 'lan': A.host == '0.0.0.0'})
        if p == 'settings' and method == 'POST':
            b = self.body()
            if b.get('ANDROID_JAR'):
                j = find_jar(os.path.expanduser(b['ANDROID_JAR']))
                if not j or not valid_jar(j):
                    return self.err(400, 'That is not a valid android.jar (android/app/Activity.class not found)')
                b['ANDROID_JAR'] = os.path.realpath(j)
            if b.get('OUT_DIR'):
                try:
                    os.makedirs(os.path.expanduser(b['OUT_DIR']), exist_ok=True)
                except Exception as e:
                    return self.err(400, 'Cannot create that folder: %s' % e)
                b['OUT_DIR'] = os.path.expanduser(b['OUT_DIR'])
            return self.json({'cfg': write_cfg(b)})
        if p == 'settings/reset' and method == 'POST':
            try:
                os.remove(home('config'))
            except OSError:
                pass
            return self.json({'ok': True})
        if p == 'fs':
            return self.fs(q)
        if p == 'upload' and method == 'POST':
            return self.upload(q)
        if p == 'jobs' and method == 'POST':
            return self.new_job(self.body())
        m = re.match(r'jobs/([\w-]+)(?:/(\w+))?$', p)
        if m:
            return self.job_route(method, m.group(1), m.group(2))
        if p == 'history':
            return self.json({'history': history(), 'logs': list_logs()})
        if p == 'logfile':
            fp = (q.get('path') or [''])[0]
            ok = [os.path.realpath(home('logs')), os.path.realpath(os.path.join(read_cfg().get('OUT_DIR') or '/nonexistent', 'logs'))]
            if not any(os.path.realpath(fp).startswith(o + os.sep) for o in ok):
                return self.err(403, 'Not a log file')
            return self.file(fp, download=os.path.basename(fp), ctype='text/plain')
        if p == 'clean' and method == 'POST':
            b = self.body()
            if b.get('work'):
                shutil.rmtree(home('work'), ignore_errors=True); os.makedirs(home('work'), exist_ok=True)
                shutil.rmtree(home('try'), ignore_errors=True); TRY.clear()
                shutil.rmtree(home('uploads'), ignore_errors=True)
            if b.get('logs'):
                shutil.rmtree(home('logs'), ignore_errors=True); os.makedirs(home('logs'), exist_ok=True)
            return self.json({'ok': True})
        if p == 'analyze' and method == 'POST':
            return self.analyze(self.body())
        if p == 'try/prepare' and method == 'POST':
            return self.try_prepare(self.body())
        m = re.match(r'ws/([\w-]+)/(tree|file|zip|build)$', p)
        if m:
            return self.workspace(method, m.group(1), m.group(2), q)
        return self.err(404, 'Unknown API: ' + p)

    # --- filesystem browser for the graphical file picker
    def fs(self, q):
        path = os.path.expanduser((q.get('path') or [''])[0] or '~')
        exts = [e for e in (q.get('ext') or [''])[0].lower().split(',') if e]
        try:
            path = os.path.realpath(path)
            if os.path.isfile(path):
                path = os.path.dirname(path)
            ents = []
            for n in sorted(os.listdir(path), key=str.lower):
                if n.startswith('.') and n not in ('.apkb',):
                    continue
                fp = os.path.join(path, n)
                try:
                    isd = os.path.isdir(fp)
                    if not isd and exts and os.path.splitext(n)[1].lower().lstrip('.') not in exts:
                        continue
                    ents.append({'name': n, 'dir': isd, 'size': 0 if isd else os.path.getsize(fp)})
                except OSError:
                    pass
            ents.sort(key=lambda e: (not e['dir'], e['name'].lower()))
            roots = [r for r in ('/storage/emulated/0', os.path.expanduser('~'), '/sdcard', '/') if os.path.isdir(r)]
            return self.json({'path': path, 'parent': os.path.dirname(path), 'entries': ents[:1500], 'roots': roots})
        except Exception as e:
            return self.err(400, 'Cannot open %s: %s' % (path, e))

    def upload(self, q):
        name = re.sub(r'[^\w.\- ]', '_', (q.get('name') or ['upload.bin'])[0])[:80] or 'upload.bin'
        d = home('uploads', time.strftime('%Y%m%d-%H%M%S') + '-' + os.urandom(2).hex())
        os.makedirs(d, exist_ok=True)
        fp = os.path.join(d, name)
        n = int(self.headers.get('Content-Length') or 0)
        with open(fp, 'wb') as f:
            left = n
            while left > 0:
                c = self.rfile.read(min(1 << 16, left))
                if not c:
                    break
                f.write(c); left -= len(c)
        return self.json({'path': fp, 'name': name, 'size': n})

    # --- jobs
    def new_job(self, b):
        kind = b.get('kind')
        o = b.get('opts') or {}
        env = {}
        for k, v in o.items():
            if re.match(r'^[A-Z_]+$', k):
                env['APKB_O_' + k] = str(v)
        if kind == 'build':
            pth = os.path.expanduser(b.get('path', ''))
            if not os.path.exists(pth):
                return self.err(400, 'Path not found: ' + pth)
            job = start_job('build', 'Build · ' + os.path.basename(pth.rstrip('/')), ['build', pth], env)
        elif kind == 'test':
            job = start_job('build', 'Build · Test APK (Example app)', ['test'], env)
        elif kind == 'html':
            conf, err = trybundle.html_conf(b, A.home)
            if err:
                return self.err(400, err)
            env['APKB_O_TYPE'] = o.get('TYPE', 'release')
            env['APKB_O_SAVESRC'] = '1' if b.get('saveSrc') else '0'
            job = start_job('build', 'HTML → APK · ' + b['form'].get('APP_NAME', 'Web App'), ['html', conf], env)
        elif kind == 'inspect':
            pth = os.path.expanduser(b.get('path', ''))
            if not os.path.isfile(pth):
                return self.err(400, 'APK not found: ' + pth)
            job = start_job('inspect', 'Inspect · ' + os.path.basename(pth), ['inspect', pth])
        elif kind == 'doctor':
            job = start_job('doctor', 'Lab doctor', ['doctor'])
        elif kind == 'install':
            job = start_job('install', 'Install / repair packages', ['install'])
        elif kind == 'scaffold':
            style = b.get('style', 'flat'); name = b.get('name', 'My App'); pkg = b.get('pkg', 'com.apkb.app')
            if style not in ('flat', 'gradle', 'eclipse') or not re.match(r'^[A-Za-z][\w]*(\.[A-Za-z][\w]*)+$', pkg):
                return self.err(400, 'Invalid style or package id')
            dest = home('projects', re.sub(r'\W+', '', name)[:24] or 'app')
            shutil.rmtree(dest, ignore_errors=True)
            job = start_job('scaffold', 'New project · ' + name, ['scaffold', style, dest, name, pkg])
            job.meta['dest'] = dest
        else:
            return self.err(400, 'Unknown job kind')
        return self.json(job.info())

    def job_route(self, method, jid, sub):
        job = JOBS.get(jid)
        if not job:
            return self.err(404, 'Unknown job')
        if sub is None:
            return self.json(job.info())
        if sub == 'cancel' and method == 'POST':
            job.status = 'cancelled'
            try:
                os.killpg(os.getpgid(job.proc.pid), signal.SIGTERM)
            except Exception:
                pass
            job.finish('cancelled', -15)
            return self.json({'ok': True})
        if sub == 'events':
            return self.sse(job)
        if sub == 'apk':
            ap = job.meta.get('apk')
            if not ap or not os.path.isfile(ap):
                return self.err(404, 'No APK for this job')
            return self.file(ap, download=os.path.basename(ap), ctype='application/vnd.android.package-archive')
        if sub == 'log':
            fp = job.meta.get('failed_log')
            if not fp or not os.path.isfile(fp):
                fp = job.logfile
            return self.file(fp, download=os.path.basename(fp) if fp != job.logfile else 'APKB-%s.log' % job.id, ctype='text/plain')
        if sub == 'zip':
            d = job.meta.get('dest')
            if not d or not os.path.isdir(d):
                return self.err(404, 'Nothing to download')
            z = shutil.make_archive(os.path.join(home('uploads'), os.path.basename(d)), 'zip', d)
            return self.file(z, download=os.path.basename(z), ctype='application/zip')
        return self.err(404, 'Unknown job action')

    def sse(self, job):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        self.end_headers()
        i = int(self.headers.get('Last-Event-ID') or 0)
        try:
            while True:
                with job.cond:
                    while i >= len(job.events):
                        if job.status != 'running' and i >= len(job.events):
                            return
                        job.cond.wait(timeout=15)
                        if i >= len(job.events):
                            self.wfile.write(b': ping\n\n'); self.wfile.flush()
                    evs = job.events[i:]
                for ev in evs:
                    i += 1
                    self.wfile.write(('id: %d\ndata: %s\n\n' % (i, json.dumps(ev))).encode())
                self.wfile.flush()
                if evs and evs[-1].get('t') == 'done':
                    return
        except (BrokenPipeError, ConnectionResetError):
            return

    # --- analyze & Try Before Build
    def analyze(self, b):
        try:
            src = trybundle.materialize(os.path.expanduser(b.get('path', '')), home('try'), copy=False)
            return self.json(trybundle.analysis(A.root, src))
        except trybundle.UserError as e:
            return self.err(400, str(e))

    def try_prepare(self, b):
        try:
            tid, root = trybundle.workspace(os.path.expanduser(b.get('path', '')), home('try'), b.get('id'))
            TRY[tid] = {'root': root}
            bundle = trybundle.make_bundle(A.root, root)
            bundle['id'] = tid
            return self.json(bundle)
        except trybundle.UserError as e:
            return self.err(400, str(e))

    def try_files(self, p, q):
        tid, _, rest = p.partition('/')
        ws = TRY.get(tid) or ({'root': home('try', tid, 'src')} if os.path.isdir(home('try', tid, 'src')) else None)
        if not ws:
            return self.err(404, 'Unknown Try Before Build session')
        root = ws['root']
        kind, _, rel = rest.partition('/')
        if kind == 'asset':   # WebView content; inject the JS bridge before any page script runs
            fp = trybundle.find_asset(root, rel)
            if not fp:
                return self.err(404, 'Asset not found: ' + rel)
            if fp.lower().endswith(('.html', '.htm')) and not q.get('raw'):
                bridges = (q.get('b') or [''])[0]
                txt = open(fp, encoding='utf-8', errors='replace').read()
                inj = '<script src="/webview-bridge.js" data-b="%s"></script>' % bridges.replace('"', '')
                mm = re.search(r'<head[^>]*>', txt, re.I)
                txt = (txt[:mm.end()] + inj + txt[mm.end():]) if mm else inj + txt
                bb = txt.encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(bb)))
                self.end_headers()
                self.wfile.write(bb)
                return
            return self.file(fp)
        if kind == 'raw':
            fp = os.path.normpath(os.path.join(root, rel))
            if not fp.startswith(os.path.realpath(root)) and not fp.startswith(root):
                return self.err(403, 'Forbidden')
            return self.file(fp)
        return self.err(404, 'Unknown try resource')

    def workspace(self, method, tid, what, q):
        ws = TRY.get(tid)
        if not ws:
            return self.err(404, 'Unknown workspace (prepare it first)')
        root = ws['root']
        if what == 'tree':
            return self.json({'files': trybundle.tree(root)})
        if what == 'file':
            rel = (q.get('path') or [''])[0]
            fp = os.path.realpath(os.path.join(root, rel))
            if not fp.startswith(os.path.realpath(root) + os.sep):
                return self.err(403, 'Forbidden')
            if method == 'GET':
                if os.path.getsize(fp) > 2_000_000:
                    return self.err(400, 'File too large to edit here')
                return self.json({'path': rel, 'text': open(fp, encoding='utf-8', errors='replace').read()})
            b = self.body()
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, 'w', encoding='utf-8') as f:
                f.write(b.get('text', ''))
            return self.json({'ok': True})
        if what == 'zip':
            z = shutil.make_archive(home('uploads', 'workspace-' + tid), 'zip', root)
            return self.file(z, download='workspace.zip', ctype='application/zip')
        if what == 'build':
            job = start_job('build', 'Build · workspace', ['build', root], {})
            return self.json(job.info())
        return self.err(404, 'Unknown workspace action')


def main():
    global A
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True); ap.add_argument('--home', required=True)
    ap.add_argument('--host', default='127.0.0.1'); ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--token', required=True); ap.add_argument('--version', default='2.0.0')
    A = ap.parse_args()
    for d in ('jobs', 'logs', 'work', 'try', 'uploads', 'projects'):
        os.makedirs(home(d), exist_ok=True)
    mimetypes.add_type('application/javascript', '.js')
    srv = ThreadingHTTPServer((A.host, A.port), H)
    srv.daemon_threads = True
    print('  ● APKB broadcast server on %s:%d  (Ctrl+C to stop)\n' % (A.host, A.port)); sys.stdout.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        for j in list(JOBS.values()):
            if j.status == 'running' and j.proc:
                try:
                    os.killpg(os.getpgid(j.proc.pid), signal.SIGTERM)
                except Exception:
                    pass
        srv.server_close()


if __name__ == '__main__':
    main()
