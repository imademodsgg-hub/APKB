"""APKB :: project workspace, analysis and the Try Before Build bundle."""
import hashlib, json, os, re, shlex, shutil, sys, zipfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'py'))
import scan as scanmod  # noqa: E402
import checker  # noqa: E402

A_NS = '{http://schemas.android.com/apk/res/android}'
IGNORE = {'.git', 'node_modules', 'build', '.gradle', '.idea', '__macosx', 'bin', 'obj', 'out'}


class UserError(Exception):
    pass


def _extract(zpath, dest):
    os.makedirs(dest, exist_ok=True)
    try:
        with zipfile.ZipFile(zpath) as z:
            for m in z.infolist():
                tgt = os.path.realpath(os.path.join(dest, m.filename))
                if not tgt.startswith(os.path.realpath(dest) + os.sep) and tgt != os.path.realpath(dest):
                    continue  # zip-slip guard
                z.extract(m, dest)
    except zipfile.BadZipFile:
        raise UserError('That file is not a valid .zip archive')


def materialize(path, trydir, copy=False):
    if not path or not os.path.exists(path):
        raise UserError('Path not found: %s' % (path or '<empty>'))
    if os.path.isdir(path):
        return os.path.realpath(path)
    if path.lower().endswith('.zip'):
        key = hashlib.md5((path + str(os.path.getmtime(path))).encode()).hexdigest()[:10]
        d = os.path.join(trydir, '_an_' + key)
        if not os.path.isdir(d):
            _extract(path, d)
        return d
    raise UserError('Give a project folder or a .zip file')


def workspace(path, trydir, tid=None):
    """Editable copy of the project. Re-using an id keeps the user's edits."""
    if tid and re.match(r'^[\w-]+$', tid) and os.path.isdir(os.path.join(trydir, tid, 'src')):
        return tid, os.path.join(trydir, tid, 'src')
    if not path or not os.path.exists(path):
        raise UserError('Path not found: %s' % (path or '<empty>'))
    tid = hashlib.md5((path + str(os.urandom(4))).encode()).hexdigest()[:10]
    dst = os.path.join(trydir, tid, 'src')
    if os.path.isdir(path):
        shutil.copytree(path, dst, ignore=lambda d, n: [x for x in n if x.lower() in IGNORE], symlinks=False)
    elif path.lower().endswith('.zip'):
        _extract(path, dst)
    else:
        raise UserError('Give a project folder or a .zip file')
    return tid, dst


def _scan(root):
    if os.path.basename(root.rstrip('/')) == 'src':
        out = os.path.join(os.path.dirname(root.rstrip('/')), '.scan_' + hashlib.md5(root.encode()).hexdigest()[:6])
    else:  # a user's own folder: never write beside it
        import tempfile
        out = tempfile.mkdtemp(prefix='apkb_scan_')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    scanmod.scan(root, out)
    env = {}
    for ln in open(os.path.join(out, 'scan.env'), encoding='utf-8'):
        k, _, v = ln.rstrip('\n').partition('=')
        try:
            p = shlex.split(v)
            env[k] = p[0] if p else ''
        except ValueError:
            env[k] = v

    def lst(n):
        p = os.path.join(out, n)
        return [x for x in open(p, encoding='utf-8').read().splitlines() if x] if os.path.exists(p) else []
    return {'env': env, 'java': lst('java.list'), 'res': lst('res.list'), 'assets': lst('assets.list'),
            'jars': lst('jar.list'), 'aars': lst('aar.list'), 'so': lst('so.list'), 'kt': lst('kt.list'), 'dir': out}


def rel(root, p):
    return os.path.relpath(p, root).replace(os.sep, '/')


def parse_manifest(path):
    info = {'package': '', 'permissions': [], 'activities': [], 'services': [], 'receivers': [], 'launcher': '',
            'minSdk': 21, 'targetSdk': 34, 'label': '', 'theme': '', 'appClass': '', 'features': [], 'error': ''}
    if not path or not os.path.isfile(path):
        return info
    try:
        r = ET.parse(path).getroot()
    except ET.ParseError as e:
        info['error'] = 'AndroidManifest.xml is not valid XML: %s' % e
        return info
    info['package'] = r.get('package', '')
    for e in r.iter('uses-permission'):
        info['permissions'].append(e.get(A_NS + 'name', ''))
    for e in r.iter('uses-feature'):
        info['features'].append(e.get(A_NS + 'name', ''))
    sdk = r.find('uses-sdk')
    if sdk is not None:
        for k, f in (('minSdk', 'minSdkVersion'), ('targetSdk', 'targetSdkVersion')):
            v = sdk.get(A_NS + f, '')
            if v.isdigit():
                info[k] = int(v)
    app = r.find('application')
    if app is None:
        return info
    info['label'] = app.get(A_NS + 'label', '')
    info['theme'] = app.get(A_NS + 'theme', '')
    info['appClass'] = app.get(A_NS + 'name', '')

    def fq(n):
        if not n:
            return n
        if n.startswith('.'):
            return info['package'] + n
        return info['package'] + '.' + n if '.' not in n else n
    for tag, key in (('activity', 'activities'), ('activity-alias', 'activities'), ('service', 'services'), ('receiver', 'receivers')):
        for e in app.iter(tag):
            nm = fq(e.get(A_NS + 'name', ''))
            d = {'name': nm, 'label': e.get(A_NS + 'label', ''), 'theme': e.get(A_NS + 'theme', ''),
                 'orientation': e.get(A_NS + 'screenOrientation', ''), 'configChanges': e.get(A_NS + 'configChanges', ''),
                 'launcher': False, 'actions': [], 'categories': []}
            for f in e.iter('intent-filter'):
                acts = [a.get(A_NS + 'name', '') for a in f.findall('action')]
                cats = [c.get(A_NS + 'name', '') for c in f.findall('category')]
                d['actions'] += acts; d['categories'] += cats
                if 'android.intent.action.MAIN' in acts and 'android.intent.category.LAUNCHER' in cats:
                    d['launcher'] = True
            info[key].append(d)
            if d['launcher'] and tag == 'activity' and not info['launcher']:
                info['launcher'] = nm
    if info['appClass']:
        info['appClass'] = fq(info['appClass'])
    return info


# -------------------------------------------------------------- resources
def unescape(s):
    s = (s or '').strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    s = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), s)
    return s.replace('\\n', '\n').replace("\\'", "'").replace('\\"', '"').replace('\\@', '@').replace('\\?', '?').replace('\\t', '\t')


def itxt(e):
    return unescape(''.join(e.itertext()))


def qual_ok(q):
    """default / density / version qualifiers only"""
    if not q:
        return True
    return all(re.match(r'^(ldpi|mdpi|hdpi|xhdpi|xxhdpi|xxxhdpi|nodpi|anydpi|tvdpi|v\d+|port)$', p) for p in q.split('-'))


DENS = ['', 'anydpi', 'v21', 'v23', 'v24', 'v26', 'xxhdpi', 'xhdpi', 'hdpi', 'mdpi', 'nodpi', 'xxxhdpi', 'ldpi']


def build_resources(root, resdirs):
    R = {'string': {}, 'color': {}, 'dimen': {}, 'integer': {}, 'bool': {}, 'style': {}, 'array': {}, 'id': [],
         'layout': {}, 'drawable': {}, 'menu': {}, 'raw': {}, 'font': {}, 'anim': {}}
    drawable_best = {}
    for rd in resdirs:
        if not os.path.isdir(rd):
            continue
        for d in sorted(os.listdir(rd)):
            dp = os.path.join(rd, d)
            if not os.path.isdir(dp):
                continue
            kind, _, q = d.partition('-')
            if not qual_ok(q):
                continue
            for fn in sorted(os.listdir(dp)):
                fp = os.path.join(dp, fn)
                if not os.path.isfile(fp):
                    continue
                name, ext = os.path.splitext(fn)
                url = rel(root, fp)
                if kind == 'values' and ext == '.xml':
                    try:
                        parse_values(fp, R)
                    except ET.ParseError:
                        pass
                elif kind == 'layout' and ext == '.xml':
                    if name not in R['layout'] or not q:
                        R['layout'][name] = {'file': url, 'text': open(fp, encoding='utf-8', errors='replace').read()}
                elif kind == 'menu' and ext == '.xml':
                    R['menu'].setdefault(name, {'file': url, 'text': open(fp, encoding='utf-8', errors='replace').read()})
                elif kind in ('drawable', 'mipmap'):
                    pr = DENS.index(q) if q in DENS else 99
                    if ext == '.xml':
                        pr -= 0.5
                    if name not in drawable_best or pr < drawable_best[name][0]:
                        drawable_best[name] = (pr, ext, url, fp)
                elif kind == 'raw':
                    R['raw'].setdefault(name, url)
                elif kind == 'font':
                    R['font'].setdefault(name, url)
                elif kind == 'anim' and ext == '.xml':
                    R['anim'].setdefault(name, open(fp, encoding='utf-8', errors='replace').read())
    for n, (pr, ext, url, fp) in drawable_best.items():
        if ext == '.xml':
            R['drawable'][n] = {'xml': open(fp, encoding='utf-8', errors='replace').read(), 'file': url}
        else:
            R['drawable'][n] = {'img': url}
    # ids declared in layouts
    ids = set(R['id'])
    for lay in R['layout'].values():
        for m in re.finditer(r'@\+id/([\w.]+)', lay['text']):
            ids.add(m.group(1))
    for mn in R['menu'].values():
        for m in re.finditer(r'@\+id/([\w.]+)', mn['text']):
            ids.add(m.group(1))
    R['id'] = sorted(ids)
    return R


def parse_values(fp, R):
    for e in ET.parse(fp).getroot():
        n = e.get('name', '')
        t = e.tag
        if t == 'string':
            R['string'].setdefault(n, itxt(e))
        elif t in ('string-array', 'integer-array', 'array'):
            R['array'].setdefault(n, [itxt(i) for i in e.findall('item')])
        elif t == 'plurals':
            it = {i.get('quantity'): itxt(i) for i in e.findall('item')}
            R['string'].setdefault(n, it.get('other') or it.get('one') or '')
        elif t == 'color':
            R['color'].setdefault(n, itxt(e))
        elif t == 'dimen':
            R['dimen'].setdefault(n, itxt(e))
        elif t == 'integer':
            R['integer'].setdefault(n, itxt(e))
        elif t == 'bool':
            R['bool'].setdefault(n, itxt(e))
        elif t == 'item' and e.get('type') == 'id':
            R['id'].append(n)
        elif t == 'style':
            items = {i.get('name', '').replace('android:', ''): itxt(i) for i in e.findall('item')}
            R['style'].setdefault(n, {'parent': e.get('parent', ''), 'items': items})


def find_asset(root, relpath):
    sc = os.path.join(os.path.dirname(root.rstrip('/')), '.scan_' + hashlib.md5(root.encode()).hexdigest()[:6], 'assets.list')
    dirs = open(sc, encoding='utf-8').read().splitlines() if os.path.exists(sc) else []
    for d in dirs:
        fp = os.path.normpath(os.path.join(d, relpath))
        if fp.startswith(os.path.normpath(d)) and os.path.isfile(fp):
            return fp
    return None


def tree(root):
    out = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d.lower() not in IGNORE]
        for f in sorted(fn):
            fp = os.path.join(dp, f)
            out.append({'path': rel(root, fp), 'size': os.path.getsize(fp)})
    out.sort(key=lambda x: x['path'].lower())
    return out[:3000]


def analysis(apkb_root, root):
    sc = _scan(root)
    env = sc['env']
    mf = env.get('MANIFEST', '')
    mi = parse_manifest(mf)
    R = build_resources(root, sc['res'])
    diags = checker.check(root, sc, mi, R)
    return {'layout': env.get('LAYOUT', ''), 'manifest': rel(root, mf) if mf else '', 'package': mi['package'],
            'launcher': mi['launcher'], 'permissions': mi['permissions'], 'activities': [a['name'] for a in mi['activities']],
            'counts': {'java': len(sc['java']), 'res': len(sc['res']), 'assets': len(sc['assets']), 'jar': len(sc['jars']),
                       'aar': len(sc['aars']), 'so': len(sc['so']), 'kotlin': len(sc['kt'])},
            'minSdk': mi['minSdk'], 'targetSdk': mi['targetSdk'], 'diagnostics': diags,
            'env': {k: env.get(k, '') for k in ('GUESS_ACTIVITY', 'GUESS_PACKAGE', 'GRADLE_APPID', 'DUP_COUNT', 'EXCL_COUNT', 'APKTOOL')}}


def make_bundle(apkb_root, root):
    sc = _scan(root)
    env = sc['env']
    mf = env.get('MANIFEST', '')
    mi = parse_manifest(mf)
    if not mf and env.get('GUESS_ACTIVITY'):
        mi['package'] = env.get('GUESS_PACKAGE', '')
        mi['launcher'] = env.get('GUESS_ACTIVITY', '')
        mi['activities'] = [{'name': mi['launcher'], 'launcher': True, 'label': '', 'theme': '', 'orientation': '', 'configChanges': '', 'actions': [], 'categories': []}]
    java = {}
    total = 0
    for jp in sc['java']:
        try:
            t = open(jp, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        total += len(t)
        if total > 12_000_000:
            break
        java[rel(root, jp)] = t
    R = build_resources(root, sc['res'])
    diags = checker.check(root, sc, mi, R)
    return {'manifest': mi, 'manifestFile': rel(root, mf) if mf else '', 'resources': R, 'java': java,
            'libs': {'jars': [os.path.basename(j) for j in sc['jars']], 'aars': [os.path.basename(j) for j in sc['aars']],
                     'so': [os.path.basename(x.split('\t')[-1]) for x in sc['so']], 'kotlin': [rel(root, k) for k in sc['kt']]},
            'diagnostics': diags, 'projectName': os.path.basename(os.path.dirname(root.rstrip('/'))) or 'App'}


# ---------------------------------------------------------------- HTML → APK
HTML_DEFAULTS = {
    'APP_NAME': 'My Web App', 'PKG': '', 'VERSION_NAME': '1.0', 'VERSION_CODE': '1', 'MIN_SDK': '21', 'TARGET_SDK': '34',
    'ORIENTATION': 'auto', 'DISPLAY': 'normal', 'THEME': 'light', 'ACTIONBAR': '0', 'BG_COLOR': '', 'STATUS_COLOR': '',
    'NAV_COLOR': '', 'ICON': '', 'SPLASH': 'none', 'SPLASH_IMAGE': '', 'SPLASH_BG': '', 'SPLASH_FG': '', 'SPLASH_MS': '1500',
    'SPLASH_TAGLINE': '', 'SPLASH_VERSION': '1', 'SPLASH_SPINNER': '1', 'EXTERNAL': 'browser', 'UA': 'default', 'UA_CUSTOM': '',
    'CACHE': 'default', 'ORIGIN': 'file', 'BRIDGE_NAME': 'Android', 'JS': '1', 'DOM': '1', 'FILE_ACCESS': '1', 'MIXED': '1',
    'ZOOM': '0', 'LONGPRESS': '1', 'SELECT': '1', 'AUTOPLAY': '1', 'UPLOAD': '1', 'DOWNLOADS': '1', 'JS_DIALOGS': '1',
    'FS_VIDEO': '1', 'BACK_NAV': '1', 'DOUBLE_BACK': '0', 'KEEP_ON': '0', 'PROGRESS': '0', 'SCROLLBARS': '0', 'BRIDGE': '1',
    'OFFLINE_PAGE': '1', 'CLEAR_CACHE': '0', 'DEBUG': '0', 'CLEARTEXT': '1', 'BACKUP': '0',
    'P_INTERNET': '1', 'P_CAMERA': '0', 'P_MIC': '0', 'P_LOCATION': '0', 'P_STORAGE': '0', 'P_VIBRATE': '0', 'P_WAKE': '0',
    'P_NOTIFY': '0', 'P_BLUETOOTH': '0'}
PERM_KEYS = ['INTERNET', 'CAMERA', 'MIC', 'LOCATION', 'STORAGE', 'VIBRATE', 'WAKE', 'NOTIFY', 'BLUETOOTH']


def html_conf(b, home):
    form = dict(HTML_DEFAULTS)
    form.update({k: str(v) for k, v in (b.get('form') or {}).items() if k in HTML_DEFAULTS})
    b['form'] = form
    src = b.get('source') or {}
    mode, www, entry, url = 'local', '', 'index.html', ''
    if src.get('mode') == 'url':
        url = (src.get('url') or '').strip()
        if not re.match(r'^https?://', url):
            return None, 'Enter a full website address starting with http:// or https://'
        mode = 'url'
    else:
        p = os.path.expanduser(src.get('path') or '')
        if not os.path.exists(p):
            return None, 'Path not found: %s' % (p or '<empty>')
        d = p
        if os.path.isfile(p):
            low = p.lower()
            if low.endswith('.zip'):
                d = os.path.join(home, 'work', 'websrc-' + hashlib.md5(p.encode()).hexdigest()[:8])
                shutil.rmtree(d, ignore_errors=True)
                try:
                    _extract(p, d)
                except UserError as e:
                    return None, str(e)
            elif low.endswith(('.html', '.htm')):
                if src.get('siblings', True):
                    www, entry = os.path.dirname(p), os.path.basename(p)
                else:
                    www = os.path.join(home, 'work', 'www1-' + hashlib.md5(p.encode()).hexdigest()[:8])
                    shutil.rmtree(www, ignore_errors=True); os.makedirs(www)
                    shutil.copy(p, www); entry = os.path.basename(p)
            else:
                return None, 'Give an .html file, a folder, or a .zip'
        if not www:
            best = None
            for dp, dn, fn in os.walk(d):
                dn[:] = [x for x in dn if x != 'node_modules']
                if dp[len(d):].count(os.sep) > 5:
                    dn[:] = []
                for f in fn:
                    if f.lower() == 'index.html':
                        c = dp[len(d):].count(os.sep)
                        if best is None or c < best[0]:
                            best = (c, dp, f)
            if not best:
                if src.get('entry'):
                    ep = os.path.join(d, src['entry'])
                    if os.path.isfile(ep):
                        best = (0, os.path.dirname(ep), os.path.basename(ep))
                if not best:
                    pages = []
                    for dp, dn, fn in os.walk(d):
                        if dp[len(d):].count(os.sep) > 3:
                            dn[:] = []
                        pages += [os.path.relpath(os.path.join(dp, f), d) for f in fn if f.lower().endswith(('.html', '.htm'))]
                    if not pages:
                        return None, 'No HTML files found in that project'
                    return None, 'No index.html found. Set "Start page" to one of: ' + ', '.join(pages[:12])
            www, entry = best[1], best[2]
    if not form['PKG'] or not re.match(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$', form['PKG']):
        slug = re.sub(r'[^a-z0-9]', '', form['APP_NAME'].lower().encode('ascii', 'ignore').decode()) or 'app%d' % (os.getpid() % 1000)
        form['PKG'] = 'com.apkb.' + slug
    perms = ','.join(k for k in PERM_KEYS if form.get('P_' + k) == '1')
    os.makedirs(os.path.join(home, 'work'), exist_ok=True)
    conf = os.path.join(home, 'work', 'html-job-%s.kv' % os.urandom(3).hex())
    with open(conf, 'w', encoding='utf-8') as f:
        for k, v in form.items():
            f.write('%s=%s\n' % (k, v.replace('\n', ' ').replace('\r', ' ')))
        f.write('PERMS=%s\nMODE=%s\nWWW_DIR=%s\nENTRY=%s\nURL=%s\n' % (perms, mode, www, entry, url))
    return conf, None
