#!/usr/bin/env python3
"""APKB manifest helper.

  manifest.py info <manifest> [pkg_hint]        -> tab separated key/value lines
  manifest.py fix  <in> <out> [options]         -> repaired / adjusted manifest
  manifest.py drop <manifest> attr [attr...]    -> remove attributes in place
  manifest.py gen  <out> <package> <activity> <label>
"""
import sys, re, os
import xml.etree.ElementTree as ET

A = 'http://schemas.android.com/apk/res/android'
T = 'http://schemas.android.com/tools'
ET.register_namespace('android', A)
ET.register_namespace('tools', T)

COMPONENTS = ('activity', 'activity-alias', 'service', 'receiver', 'provider')

# attributes that need a newer android.jar than their API level
ATTR_API = {
    'roundIcon': 25, 'dataExtractionRules': 31, 'fullBackupContent': 23,
    'localeConfig': 33, 'enableOnBackInvokedCallback': 33, 'foregroundServiceType': 29,
    'requestLegacyExternalStorage': 29, 'resizeableActivity': 24,
    'supportsPictureInPicture': 24, 'usesPermissionFlags': 31,
    'networkSecurityConfig': 24, 'appCategory': 26, 'preserveLegacyExternalStorage': 30,
    'hasFragileUserData': 29, 'showWhenLocked': 27, 'turnScreenOn': 27,
    'allowNativeHeapPointerTagging': 30, 'autoRevokePermissions': 30,
    'usesCleartextTraffic': 23, 'maxAspectRatio': 26,
}


def a(n):
    return '{%s}%s' % (A, n)


def load(path, pkg_hint=''):
    text = open(path, 'r', encoding='utf-8', errors='replace').read()
    m = re.search(r'<manifest[^>]*\spackage\s*=\s*"([^"]+)"', text)
    pkg = m.group(1) if m else pkg_hint
    # Gradle placeholders
    text = text.replace('${applicationId}', pkg).replace('${packageName}', pkg)
    text = re.sub(r'\$\{([\w.]+)\}', lambda mm: mm.group(1), text)
    root = ET.fromstring(text.encode('utf-8'))
    return root


def fq(name, pkg):
    if not name:
        return ''
    if name.startswith('.'):
        return pkg + name
    if '.' not in name:
        return pkg + '.' + name
    return name


def launcher_of(app, pkg):
    for el in list(app.iter('activity')) + list(app.iter('activity-alias')):
        for flt in el.findall('intent-filter'):
            acts = [x.get(a('name')) for x in flt.findall('action')]
            cats = [x.get(a('name')) for x in flt.findall('category')]
            if 'android.intent.action.MAIN' in acts and 'android.intent.category.LAUNCHER' in cats:
                if el.tag == 'activity-alias':
                    return fq(el.get(a('targetActivity')), pkg)
                return fq(el.get(a('name')), pkg)
    return ''


def cmd_info(path, hint=''):
    try:
        root = load(path, hint)
    except Exception as e:
        print('error\t%s' % e)
        return 2
    pkg = root.get('package') or hint
    out = []
    out.append(('package', root.get('package') or ''))
    out.append(('versionCode', root.get(a('versionCode')) or ''))
    out.append(('versionName', root.get(a('versionName')) or ''))
    sdk = root.find('uses-sdk')
    out.append(('minSdk', (sdk.get(a('minSdkVersion')) if sdk is not None else '') or ''))
    out.append(('targetSdk', (sdk.get(a('targetSdkVersion')) if sdk is not None else '') or ''))
    app = root.find('application')
    out.append(('hasApplication', '1' if app is not None else '0'))
    if app is not None:
        out.append(('label', app.get(a('label')) or ''))
        out.append(('icon', app.get(a('icon')) or ''))
        out.append(('application', fq(app.get(a('name')), pkg) if app.get(a('name')) else ''))
        out.append(('launcher', launcher_of(app, pkg)))
        missing = 0
        for tag in COMPONENTS:
            for el in app.iter(tag):
                nm = el.get(a('name')) if tag != 'activity-alias' else el.get(a('targetActivity'))
                if tag != 'activity-alias':
                    out.append((tag, fq(nm, pkg)))
                if el.findall('intent-filter') and el.get(a('exported')) is None:
                    missing += 1
        out.append(('exportedMissing', str(missing)))
    for p in root.findall('uses-permission'):
        out.append(('permission', p.get(a('name')) or ''))
    for k, v in out:
        print('%s\t%s' % (k, v))
    return 0


def strip_by_api(root, api):
    n = 0
    for el in root.iter():
        for k in list(el.attrib):
            if k.startswith('{%s}' % A):
                name = k.split('}', 1)[1]
                need = ATTR_API.get(name)
                if need and api < need:
                    del el.attrib[k]
                    n += 1
    return n


def write(root, out):
    tree = ET.ElementTree(root)
    if hasattr(ET, 'indent'):
        ET.indent(tree, space='    ')
    tree.write(out, encoding='utf-8', xml_declaration=True)


def cmd_fix(src, dst, argv):
    o = {'perm': [], 'drop': []}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k in ('--exported', '--default-version', '--cleartext'):
            o[k[2:]] = True
            i += 1
        elif k == '--perm':
            o['perm'].append(argv[i + 1]); i += 2
        elif k == '--drop-attr':
            o['drop'].append(argv[i + 1]); i += 2
        elif k.startswith('--'):
            o[k[2:]] = argv[i + 1]; i += 2
        else:
            i += 1
    root = load(src, o.get('package', ''))
    if o.get('package'):
        root.set('package', o['package'])
    elif not root.get('package'):
        root.set('package', 'com.apkb.app')
    if o.get('version-code'):
        root.set(a('versionCode'), o['version-code'])
    elif o.get('default-version') and not root.get(a('versionCode')):
        root.set(a('versionCode'), '1')
    if o.get('version-name'):
        root.set(a('versionName'), o['version-name'])
    elif o.get('default-version') and not root.get(a('versionName')):
        root.set(a('versionName'), '1.0')

    sdk = root.find('uses-sdk')
    if sdk is None and (o.get('min') or o.get('target')):
        sdk = ET.Element('uses-sdk')
        root.insert(0, sdk)
    if sdk is not None:
        if o.get('min'):
            sdk.set(a('minSdkVersion'), o['min'])
        if o.get('target'):
            sdk.set(a('targetSdkVersion'), o['target'])
        if sdk.get(a('maxSdkVersion')) is not None and o.get('target'):
            del sdk.attrib[a('maxSdkVersion')]

    have = {p.get(a('name')) for p in root.findall('uses-permission')}
    for p in o['perm']:
        if p and p not in have:
            el = ET.Element('uses-permission')
            el.set(a('name'), p)
            root.insert(1 if root.find('uses-sdk') is not None else 0, el)
            have.add(p)

    app = root.find('application')
    if app is not None:
        if o.get('label'):
            app.set(a('label'), o['label'])
        if o.get('debuggable') == '1':
            app.set(a('debuggable'), 'true')
        elif o.get('debuggable') == '0' and a('debuggable') in app.attrib:
            del app.attrib[a('debuggable')]
        if o.get('cleartext'):
            app.set(a('usesCleartextTraffic'), 'true')
        if o.get('exported'):
            for tag in COMPONENTS:
                for el in app.iter(tag):
                    if el.findall('intent-filter') and el.get(a('exported')) is None:
                        el.set(a('exported'), 'true')
    if o.get('api'):
        try:
            strip_by_api(root, int(o['api']))
        except ValueError:
            pass
    for d in o['drop']:
        name = d.split(':', 1)[-1]
        for el in root.iter():
            k = a(name)
            if k in el.attrib:
                del el.attrib[k]
    write(root, dst)
    return 0


def cmd_drop(path, attrs):
    root = load(path)
    for d in attrs:
        name = d.split(':', 1)[-1]
        for el in root.iter():
            k = a(name)
            if k in el.attrib:
                del el.attrib[k]
    write(root, path)
    return 0


def cmd_gen(out, pkg, activity, label):
    name = activity if activity.startswith(pkg) else activity
    if name.startswith(pkg + '.'):
        name = name[len(pkg):]
    root = ET.Element('manifest')
    root.set('package', pkg)
    root.set(a('versionCode'), '1')
    root.set(a('versionName'), '1.0')
    perm = ET.SubElement(root, 'uses-permission')
    perm.set(a('name'), 'android.permission.INTERNET')
    app = ET.SubElement(root, 'application')
    app.set(a('label'), label)
    act = ET.SubElement(app, 'activity')
    act.set(a('name'), name)
    act.set(a('exported'), 'true')
    flt = ET.SubElement(act, 'intent-filter')
    ET.SubElement(flt, 'action').set(a('name'), 'android.intent.action.MAIN')
    ET.SubElement(flt, 'category').set(a('name'), 'android.intent.category.LAUNCHER')
    write(root, out)
    return 0


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    c = sys.argv[1]
    try:
        if c == 'info':
            sys.exit(cmd_info(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ''))
        if c == 'fix':
            sys.exit(cmd_fix(sys.argv[2], sys.argv[3], sys.argv[4:]))
        if c == 'drop':
            sys.exit(cmd_drop(sys.argv[2], sys.argv[3:]))
        if c == 'gen':
            sys.exit(cmd_gen(*sys.argv[2:6]))
    except ET.ParseError as e:
        print('error\tmanifest is not valid XML: %s' % e)
        sys.exit(2)
    print(__doc__)
    sys.exit(2)
