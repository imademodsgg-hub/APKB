#!/usr/bin/env python3
"""APKB project scanner.
Finds the manifest, resources, Java sources, libs, assets and native libs of an
Android source project - whatever the folder layout is.

Usage:
  scan.py scan  <project_root> <outdir>
  scan.py prune <java.list> <errlog> <main_root>
  scan.py dupjars <errlog>
"""
import os, re, sys, shlex

SKIP = {'.git', '.gradle', '.idea', 'node_modules', 'build', 'bin', 'obj', 'out',
        '__macosx', 'captures', '.svn', '.hg', '.cxx', '.externalnativebuild',
        'gen', 'generated', '.apkb', '.vscode', '.settings'}
RES_KINDS = {'values', 'layout', 'drawable', 'mipmap', 'xml', 'raw', 'menu', 'anim',
             'animator', 'color', 'font', 'navigation', 'interpolator', 'transition'}
ABIS = {'armeabi', 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64', 'mips', 'mips64'}
BAD_JARS = ('gradle-wrapper.jar', 'android.jar', 'lint.jar')


def read(p, n=None):
    try:
        with open(p, 'r', encoding='utf-8', errors='replace') as f:
            return f.read() if n is None else f.read(n)
    except Exception:
        return ''


def skipped(name, parent):
    n = name.lower()
    if n in SKIP:
        return True
    if n in ('test', 'androidtest', 'unittest') and parent.lower() == 'src':
        return True
    return False


def walk(root, excluded=()):
    for dp, dn, fn in os.walk(root):
        parent = os.path.basename(dp)
        dn[:] = [d for d in dn
                 if not skipped(d, parent) and os.path.join(dp, d) not in excluded]
        dn.sort()
        yield dp, dn, sorted(fn)


def rel_parts(path, root):
    return os.path.relpath(path, root).replace('\\', '/').split('/')


def in_assets(path, root):
    parts = [p.lower() for p in rel_parts(path, root)[:-1]]
    return 'assets' in parts


def within(path, root):
    root = root.rstrip('/')
    return path == root or path.startswith(root + '/')


def module_root(mpath):
    d = os.path.dirname(mpath)
    p = d.replace('\\', '/').split('/')
    if len(p) >= 3 and p[-2] == 'src':
        return os.path.dirname(os.path.dirname(d))
    return d


def score_manifest(path, root):
    t = read(path)
    s = 0
    if '<application' in t:
        s += 10
    if 'android.intent.category.LAUNCHER' in t:
        s += 25
    if re.search(r'package\s*=\s*"', t):
        s += 3
    low = path.lower().replace('\\', '/')
    if '/src/main/' in low:
        s += 4
    if '/src/debug/' in low or '/src/release/' in low or '/src/staging/' in low:
        s -= 8
    s -= len(rel_parts(path, root)) * 0.5
    return s


def is_app_manifest(path):
    t = read(path)
    return '<application' in t and ('<activity' in t or 'LAUNCHER' in t)


def parse_gradle(mroot, root):
    out = {}
    cands = []
    for base in (mroot, root):
        for n in ('build.gradle', 'build.gradle.kts'):
            p = os.path.join(base, n)
            if os.path.isfile(p) and p not in cands:
                cands.append(p)
    pats = {
        'GRADLE_NAMESPACE': r'namespace\s*[= ]\s*["\']([\w.]+)["\']',
        'GRADLE_APPID': r'applicationId\s*[= ]\s*["\']([\w.]+)["\']',
        'GRADLE_MIN': r'minSdk(?:Version)?\s*[= ]?\s*\(?\s*(\d+)',
        'GRADLE_TARGET': r'targetSdk(?:Version)?\s*[= ]?\s*\(?\s*(\d+)',
        'GRADLE_VCODE': r'versionCode\s*[= ]?\s*\(?\s*(\d+)',
        'GRADLE_VNAME': r'versionName\s*[= ]?\s*\(?\s*["\']([^"\']+)["\']',
    }
    for p in cands:
        t = read(p)
        for k, pat in pats.items():
            if k not in out:
                m = re.search(pat, t)
                if m:
                    out[k] = m.group(1)
    return out


PKG_RE = re.compile(r'^\s*package\s+([\w.]+)\s*;', re.M)


def java_key(path):
    t = read(path, 6000)
    m = PKG_RE.search(t)
    pkg = m.group(1) if m else ''
    stem = os.path.splitext(os.path.basename(path))[0]
    return ((pkg + '.' + stem) if pkg else stem), pkg


def scan(root, outdir):
    root = os.path.abspath(root)
    os.makedirs(outdir, exist_ok=True)
    env = {}

    # ---- pass 1: manifests ---------------------------------------------------
    manifests = []
    for dp, dn, fn in walk(root):
        for f in fn:
            if f == 'AndroidManifest.xml':
                p = os.path.join(dp, f)
                if not in_assets(p, root):
                    manifests.append(p)
    manifests.sort(key=lambda p: (-score_manifest(p, root), p))
    main = manifests[0] if manifests else ''
    mroot = module_root(main) if main else root

    excluded = set()
    excl_names = []
    for m in manifests[1:]:
        r = module_root(m)
        if r == mroot or within(mroot, r) or r == root:
            continue
        if is_app_manifest(m):
            excluded.add(r)
            excl_names.append(os.path.relpath(r, root))
    env['MANIFEST'] = main
    env['MAIN_ROOT'] = mroot
    env['MANIFEST_COUNT'] = str(len(manifests))

    # ---- pass 2: everything else ---------------------------------------------
    java, kt, aidl, jars, aars, sos, res_c, assets = [], [], [], [], [], [], [], []
    apktool = False
    native_src = 0
    for dp, dn, fn in walk(root, excluded):
        under_assets = in_assets(os.path.join(dp, 'x'), root)
        if not under_assets:
            kids = [d for d in dn if d.lower().split('-')[0] in RES_KINDS]
            base = os.path.basename(dp).lower()
            if kids:
                has_values = any(k.lower().split('-')[0] == 'values' for k in kids)
                has_vis = any(k.lower().split('-')[0] in ('layout', 'drawable', 'mipmap') for k in kids)
                if base == 'res' or (has_values and len(kids) >= 2) or (len(kids) >= 3 and has_vis):
                    res_c.append(dp)
            if base == 'assets':
                assets.append(dp)
        for f in fn:
            p = os.path.join(dp, f)
            low = f.lower()
            if under_assets:
                continue
            if low.endswith('.java'):
                if f == 'R.java':
                    continue
                java.append(p)
            elif low.endswith('.kt'):
                kt.append(p)
            elif low.endswith('.aidl'):
                aidl.append(p)
            elif low.endswith('.jar'):
                if low in BAD_JARS or low.endswith('-sources.jar') or low.endswith('-javadoc.jar'):
                    continue
                jars.append(p)
            elif low.endswith('.aar'):
                aars.append(p)
            elif low.endswith('.so'):
                parent = os.path.basename(dp)
                if parent in ABIS:
                    sos.append((parent, p))
            elif low == 'apktool.yml':
                apktool = True
            elif low.endswith(('.c', '.cpp', '.cc')):
                native_src += 1

    # nested res candidates are dropped; assets keep top-level only
    res_c = [d for d in res_c if not any(o != d and within(d, o) for o in res_c)]
    assets = [d for d in assets if not any(o != d and within(d, o) for o in assets)]
    java = [p for p in java if not any(within(p, r) for r in res_c if r != root)]

    # ---- de-duplicate java classes (flavors / copies) ------------------------
    def jscore(p):
        s = 0
        if within(p, mroot):
            s += 50
        if '/src/main/' in p.replace('\\', '/'):
            s += 5
        s -= len(rel_parts(p, root))
        return s
    best, dups = {}, []
    for p in java:
        k, _ = java_key(p)
        if k in best:
            a, b = best[k], p
            keep, drop = (a, b) if jscore(a) >= jscore(b) else (b, a)
            best[k] = keep
            dups.append(drop)
        else:
            best[k] = p
    keep_set = set(best.values())
    java = [p for p in java if p in keep_set]

    # ---- order resource dirs: low priority first -----------------------------
    def rkey(d):
        return (1 if within(d, mroot) else 0,
                1 if '/src/main/' in d.replace('\\', '/') else 0, -len(d))
    res_c.sort(key=rkey)
    assets.sort(key=lambda d: (0 if within(d, mroot) else 1, len(d)))

    # ---- guess layout --------------------------------------------------------
    layout = 'custom'
    if main:
        mp = main.replace('\\', '/')
        if mp.endswith('src/main/AndroidManifest.xml'):
            layout = 'Gradle-style (src/main)'
        elif os.path.dirname(main) == mroot and os.path.isdir(os.path.join(mroot, 'src')) \
                and os.path.isdir(os.path.join(mroot, 'res')):
            layout = 'Eclipse/ADT-style (src + res)'
        elif mroot == root:
            layout = 'flat / root-level'
        else:
            layout = 'nested module'
    env['LAYOUT'] = layout
    env.update(parse_gradle(mroot, root))

    # ---- guess activity when the manifest is missing -------------------------
    guess_act = guess_pkg = ''
    if not main:
        cands = []
        for p in java:
            t = read(p)
            if re.search(r'extends\s+(android\.app\.)?(Activity|AppCompatActivity|FragmentActivity)\b', t) \
                    and 'onCreate' in t:
                k, pk = java_key(p)
                pri = 0 if 'main' in os.path.basename(p).lower() else 1
                cands.append((pri, len(k), k, pk))
        cands.sort()
        if cands:
            guess_act, guess_pkg = cands[0][2], cands[0][3]
    env['GUESS_ACTIVITY'] = guess_act
    env['GUESS_PACKAGE'] = guess_pkg

    env['KT_COUNT'] = str(len(kt))
    env['AIDL_COUNT'] = str(len(aidl))
    env['APKTOOL'] = '1' if apktool else '0'
    env['NATIVE_SRC'] = str(native_src)
    env['JAVA_COUNT'] = str(len(java))
    env['RES_COUNT'] = str(len(res_c))
    env['JAR_COUNT'] = str(len(jars))
    env['AAR_COUNT'] = str(len(aars))
    env['SO_COUNT'] = str(len(sos))
    env['ASSET_COUNT'] = str(len(assets))
    env['DUP_COUNT'] = str(len(dups))
    env['EXCL_COUNT'] = str(len(excl_names))

    def wl(name, items):
        with open(os.path.join(outdir, name), 'w', encoding='utf-8') as f:
            for i in items:
                f.write(i + '\n')
    wl('java.list', java)
    wl('res.list', res_c)
    wl('assets.list', assets)
    wl('jar.list', jars)
    wl('aar.list', aars)
    wl('so.list', ['%s\t%s' % (a, p) for a, p in sos])
    wl('kt.list', kt)
    wl('dups.txt', [os.path.relpath(d, root) for d in dups])
    wl('excluded.txt', excl_names)
    with open(os.path.join(outdir, 'scan.env'), 'w', encoding='utf-8') as f:
        for k, v in env.items():
            f.write('%s=%s\n' % (k, shlex.quote(v)))
    return 0


def prune(listfile, errlog, mainroot):
    t = read(errlog)
    bad = set()
    for m in re.finditer(r'ERROR in (/.+?\.java) \(at line', t):
        bad.add(m.group(1))
    for m in re.finditer(r'^(/.+?\.java):\d+: error', t, re.M):
        bad.add(m.group(1))
    items = [l.rstrip('\n') for l in open(listfile, encoding='utf-8') if l.strip()]
    removed = [p for p in items if p in bad and not within(p, mainroot)]
    if not removed:
        return 1
    keep = [p for p in items if p not in removed]
    with open(listfile, 'w', encoding='utf-8') as f:
        for p in keep:
            f.write(p + '\n')
    for p in removed:
        print(p)
    return 0


def dupjars(errlog):
    t = read(errlog)
    out = []
    for m in re.finditer(r'defined multiple times:\s*(.+)', t):
        parts = [x.strip() for x in m.group(1).split(', ') if x.strip()]
        for x in parts[1:]:
            p = x.split(':', 1)[0]
            if p.endswith('.jar') and p not in out:
                out.append(p)
    for p in out:
        print(p)
    return 0 if out else 1


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == 'scan':
        sys.exit(scan(sys.argv[2], sys.argv[3]))
    if cmd == 'prune':
        sys.exit(prune(sys.argv[2], sys.argv[3], sys.argv[4]))
    if cmd == 'dupjars':
        sys.exit(dupjars(sys.argv[2]))
    print(__doc__)
    sys.exit(2)
