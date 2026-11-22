"""APKB project checker: finds the exact file / line of problems before any build.

check(root, scan, manifest_info, R) -> [ {sev, file, line, col, msg, hint} ]
"""
import os, re
import xml.etree.ElementTree as ET

REF = re.compile(r'@(?!android:)(?:\+)?(string|color|dimen|drawable|mipmap|layout|style|menu|raw|array|integer|bool|id|anim|font)/([\w.]+)')
RREF = re.compile(r'(?<![\w.])R\.(string|color|dimen|drawable|mipmap|layout|style|menu|raw|array|integer|bool|id|anim|font)\.(\w+)')
IMPORT = re.compile(r'^\s*import\s+(static\s+)?([\w.]+)\s*;', re.M)
PLATFORM = ('android.', 'java.', 'javax.', 'org.json', 'org.xml', 'org.w3c', 'org.apache.http', 'dalvik.', 'junit.', 'org.junit',
            'com.google.android.gms.', 'org.xmlpull')
PERM_RULES = [
    (r'\bCamera\.open\b|\bCameraManager\b|\bopenCamera\s*\(', 'android.permission.CAMERA', 'camera'),
    (r'\bLocationManager\b|requestLocationUpdates|getLastKnownLocation', 'android.permission.ACCESS_FINE_LOCATION', 'location'),
    (r'\bMediaRecorder\b|\bAudioRecord\b', 'android.permission.RECORD_AUDIO', 'microphone'),
    (r'\bVibrator\b|\.vibrate\s*\(', 'android.permission.VIBRATE', 'vibration'),
    (r'\bHttpURLConnection\b|\.openConnection\s*\(|loadUrl\s*\(\s*"https?:', 'android.permission.INTERNET', 'the network'),
    (r'getExternalStorageDirectory|getExternalStoragePublicDirectory', 'android.permission.WRITE_EXTERNAL_STORAGE', 'shared storage'),
    (r'\bBluetoothAdapter\b', 'android.permission.BLUETOOTH', 'Bluetooth'),
    (r'\bWifiManager\b', 'android.permission.ACCESS_WIFI_STATE', 'Wi-Fi state'),
]


def lineof(text, idx):
    return text.count('\n', 0, idx) + 1


def read(p):
    try:
        return open(p, encoding='utf-8', errors='replace').read()
    except OSError:
        return ''


def check(root, sc, mi, R=None):
    out = []
    rl = lambda p: os.path.relpath(p, root).replace(os.sep, '/')

    def add(sev, file, line, msg, hint='', col=0):
        out.append({'sev': sev, 'file': file, 'line': line, 'col': col, 'msg': msg, 'hint': hint})

    env = sc['env']
    mf = env.get('MANIFEST', '')
    mtxt = read(mf) if mf else ''
    mrel = rl(mf) if mf else ''
    if not mf:
        if env.get('GUESS_ACTIVITY'):
            add('warning', '', 0, 'No AndroidManifest.xml - APKB would generate one for %s' % env['GUESS_ACTIVITY'])
        else:
            add('error', '', 0, 'No AndroidManifest.xml and no Activity class were found', 'Add an AndroidManifest.xml at the project root.')
    if mi.get('error'):
        add('error', mrel, 1, mi['error'])

    # ---- XML well-formedness (manifest + every res xml)
    xmls = [mf] if mf else []
    for rd in sc['res']:
        for dp, dn, fn in os.walk(rd):
            xmls += [os.path.join(dp, f) for f in fn if f.endswith('.xml')]
    for p in xmls:
        try:
            ET.parse(p)
        except ET.ParseError as e:
            ln, col = getattr(e, 'position', (1, 0))
            add('error', rl(p), ln, 'XML is not well-formed: %s' % re.sub(r'\s*\(.*', '', str(e)), 'Fix the tag near this line.', col)
        except Exception:
            pass

    # ---- classes
    java_text = {jp: read(jp) for jp in sc['java']}
    declared = set()
    for jp, t in java_text.items():
        pk = re.search(r'^\s*package\s+([\w.]+)\s*;', t, re.M)
        for m in re.finditer(r'\b(?:class|interface|enum)\s+(\w+)', t):
            declared.add((pk.group(1) + '.' if pk else '') + m.group(1))
            declared.add(m.group(1))
    simple = {d.rsplit('.', 1)[-1] for d in declared}
    for kind in ('activities', 'services', 'receivers'):
        for c in mi.get(kind, []):
            n = c['name']
            if not n or n.startswith('android.') or n.startswith('com.google.'):
                continue
            if n not in declared and n.rsplit('.', 1)[-1] not in simple and not (sc['jars'] or sc['aars']):
                m = re.search(r'android:name\s*=\s*"[^"]*%s"' % re.escape(n.rsplit('.', 1)[-1]), mtxt)
                add('error', mrel, lineof(mtxt, m.start()) if m else 1,
                    '%s "%s" is declared in the manifest but no such class exists' % (kind[:-3].title() if kind != 'activities' else 'Activity', n),
                    'Create the class or fix android:name (package + class name must match the Java file).')
    if mf and not mi.get('launcher'):
        add('warning', mrel, 1, 'No launcher activity (MAIN + LAUNCHER intent-filter): the app would have no icon',
            'Try Before Build will open the first activity instead.')

    # ---- resource references
    if R is not None:
        have = {
            'string': set(R['string']), 'color': set(R['color']), 'dimen': set(R['dimen']), 'integer': set(R['integer']),
            'bool': set(R['bool']), 'style': set(R['style']), 'array': set(R['array']), 'id': set(R['id']),
            'layout': set(R['layout']), 'drawable': set(R['drawable']), 'mipmap': set(R['drawable']),
            'menu': set(R['menu']), 'raw': set(R['raw']), 'font': set(R['font']), 'anim': set(R['anim'])}
        # android:text="@string/x" etc.
        for p in xmls:
            t = read(p)
            for m in REF.finditer(t):
                k, n = m.group(1), m.group(2)
                if m.group(0).startswith('@+'):
                    continue
                if n not in have.get(k, ()) and not (k == 'id' and n in have['id']):
                    if k in ('anim',):
                        continue
                    add('error', rl(p), lineof(t, m.start()), 'Resource not found: @%s/%s' % (k, n),
                        'Define it in res/%s or fix the name.' % ('values' if k in ('string', 'color', 'dimen', 'style', 'integer', 'bool', 'array') else k))
        # R.x.y in Java
        for jp, t in java_text.items():
            for m in RREF.finditer(t):
                k, n = m.group(1), m.group(2)
                if k == 'anim' or n in have.get(k, ()):
                    continue
                if t[max(0, m.start() - 8):m.start()].endswith('android.'):
                    continue
                add('error', rl(jp), lineof(t, m.start()), 'cannot find symbol: R.%s.%s' % (k, n),
                    'No resource called "%s" exists (checked all res folders and layouts).' % n)

    # ---- imports / libraries
    libnames = ' '.join(os.path.basename(x).lower() for x in sc['jars'] + sc['aars'])
    seen = set()
    for jp, t in java_text.items():
        for m in IMPORT.finditer(t):
            imp = m.group(2)
            if imp.startswith(PLATFORM) or imp in seen:
                continue
            top = '.'.join(imp.split('.')[:-1]) if not m.group(1) else '.'.join(imp.split('.')[:-2])
            cls = imp.rsplit('.', 1)[-1]
            if imp in declared or cls in simple or imp.endswith('*') and any(d.startswith(top) for d in declared):
                continue
            if imp.startswith(('androidx.', 'android.support.')):
                if not sc['jars'] and not sc['aars']:
                    seen.add(imp)
                    add('error', rl(jp), lineof(t, m.start()), 'package %s is not available (AndroidX / support library)' % top,
                        'Put the library .jar/.aar files inside the project (e.g. libs/) - APKB has no Gradle to download them.')
                continue
            if not sc['jars'] and not sc['aars']:
                seen.add(imp)
                add('error', rl(jp), lineof(t, m.start()), 'cannot resolve import %s' % imp,
                    'Third-party library: add its .jar/.aar to the project (libs/).')
            else:
                add('info', rl(jp), lineof(t, m.start()), 'Uses library class %s (not runnable in Try Before Build)' % imp)

    # ---- permission hints
    perms = set(mi.get('permissions', []))
    for pattern, perm, what in PERM_RULES:
        if perm in perms or (perm.endswith('FINE_LOCATION') and 'android.permission.ACCESS_COARSE_LOCATION' in perms) \
                or (perm.endswith('WRITE_EXTERNAL_STORAGE') and 'android.permission.MANAGE_EXTERNAL_STORAGE' in perms):
            continue
        for jp, t in java_text.items():
            m = re.search(pattern, t)
            if m:
                add('warning', rl(jp), lineof(t, m.start()), 'The code uses %s but %s is not declared in AndroidManifest.xml' % (what, perm),
                    'Add <uses-permission android:name="%s"/> to the manifest.' % perm)
                break

    # ---- kotlin / native
    for k in sc['kt']:
        add('warning', rl(k), 1, 'Kotlin file: APKB compiles Java only, so this file is skipped (and cannot run in Try Before Build)')
    if sc['so']:
        add('info', '', 0, '%d native .so librar%s: they ship in the APK, but cannot execute in the browser preview' % (len(sc['so']), 'y' if len(sc['so']) == 1 else 'ies'))
    for jp, t in java_text.items():
        m = re.search(r'System\.loadLibrary\(\s*"(\w+)"', t)
        if m and not any(('lib%s.so' % m.group(1)) in x for x in sc['so']):
            add('warning', rl(jp), lineof(t, m.start()), 'System.loadLibrary("%s") but no lib%s.so was found in the project' % (m.group(1), m.group(1)),
                'The app would crash at start with UnsatisfiedLinkError.')
    if env.get('APKTOOL') == '1':
        add('warning', '', 0, 'apktool.yml found: this looks like a decoded APK (smali), not Java source')
    order = {'error': 0, 'warning': 1, 'info': 2}
    out.sort(key=lambda d: (order[d['sev']], d['file'], d['line']))
    return out[:400]
