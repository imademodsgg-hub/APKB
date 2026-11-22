#!/usr/bin/env python3
"""APKB HTML -> WebView app project generator.

  html2apk.py <config.kv> <out_project_dir> <apkb_root>

Creates a complete raw-Java Android project (manifest, MainActivity, res,
assets/www) that the normal APKB build pipeline then compiles.
"""
import os, sys, shutil, subprocess, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon  # noqa: E402


def load_conf(path):
    c = {}
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        c[k.strip()] = v
    return c


def jstr(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif o < 32 or o > 126:
            if o > 0xFFFF:
                o -= 0x10000
                out.append('\\u%04x\\u%04x' % (0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF)))
            else:
                out.append('\\u%04x' % o)
        else:
            out.append(ch)
    return ''.join(out)


def xml_res(s):
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"')
    s = s.replace('&', '&amp;').replace('<', '&lt;').replace('\n', '\\n')
    if s[:1] in ('@', '?'):
        s = '\\' + s
    return s


def b(c, k, d='0'):
    return 'true' if c.get(k, d) in ('1', 'true', 'yes', 'on') else 'false'


def lum(hexcolor):
    h = hexcolor.lstrip('#')
    if len(h) == 8:
        h = h[2:]
    try:
        r, g, bl = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    except Exception:
        return 0
    return (0.299 * r + 0.587 * g + 0.114 * bl) / 255.0


PERM_MAP = {
    'INTERNET': [('android.permission.INTERNET', None), ('android.permission.ACCESS_NETWORK_STATE', None)],
    'CAMERA': [('android.permission.CAMERA', None)],
    'MIC': [('android.permission.RECORD_AUDIO', None), ('android.permission.MODIFY_AUDIO_SETTINGS', None)],
    'LOCATION': [('android.permission.ACCESS_FINE_LOCATION', None), ('android.permission.ACCESS_COARSE_LOCATION', None)],
    'STORAGE': [('android.permission.READ_EXTERNAL_STORAGE', 32), ('android.permission.READ_MEDIA_IMAGES', None),
                ('android.permission.READ_MEDIA_VIDEO', None), ('android.permission.READ_MEDIA_AUDIO', None)],
    'VIBRATE': [('android.permission.VIBRATE', None)],
    'WAKE': [('android.permission.WAKE_LOCK', None)],
    'NOTIFY': [('android.permission.POST_NOTIFICATIONS', None)],
    'BLUETOOTH': [('android.permission.BLUETOOTH', 30), ('android.permission.BLUETOOTH_CONNECT', None)],
}
# permissions the app asks for at runtime: (perm, minSdk, maxSdk)
RUNTIME = {
    'CAMERA': [('android.permission.CAMERA', 23, 99)],
    'MIC': [('android.permission.RECORD_AUDIO', 23, 99)],
    'LOCATION': [('android.permission.ACCESS_FINE_LOCATION', 23, 99)],
    'STORAGE': [('android.permission.READ_EXTERNAL_STORAGE', 23, 32),
                ('android.permission.READ_MEDIA_IMAGES', 33, 99),
                ('android.permission.READ_MEDIA_VIDEO', 33, 99),
                ('android.permission.READ_MEDIA_AUDIO', 33, 99)],
    'NOTIFY': [('android.permission.POST_NOTIFICATIONS', 33, 99)],
}

SAVE_NEW = '''    private void saveBytes(byte[] data, String mime, String name) {
        try {
            if (mime == null || mime.length() == 0) mime = "application/octet-stream";
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues v = new ContentValues();
                v.put(MediaStore.Downloads.DISPLAY_NAME, name);
                v.put(MediaStore.Downloads.MIME_TYPE, mime);
                v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                Uri u = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                OutputStream o = getContentResolver().openOutputStream(u);
                o.write(data);
                o.close();
            } else {
                File d = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
                d.mkdirs();
                FileOutputStream o = new FileOutputStream(new File(d, name));
                o.write(data);
                o.close();
            }
            showToast("Saved to Downloads: " + name);
        } catch (Exception e) {
            showToast("Save failed: " + e.getMessage());
        }
    }'''

SAVE_OLD = '''    private void saveBytes(byte[] data, String mime, String name) {
        try {
            File d = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            d.mkdirs();
            FileOutputStream o = new FileOutputStream(new File(d, name));
            o.write(data);
            o.close();
            showToast("Saved to Downloads: " + name);
        } catch (Exception e) {
            showToast("Save failed: " + e.getMessage());
        }
    }'''


def main(conf_path, out, root):
    c = load_conf(conf_path)
    name = c.get('APP_NAME') or 'My App'
    pkg = c.get('PKG') or 'com.apkb.app'
    vname = c.get('VERSION_NAME') or '1.0'
    vcode = c.get('VERSION_CODE') or '1'
    minsdk = c.get('MIN_SDK') or '21'
    target = c.get('TARGET_SDK') or '34'
    jar_api = int(c.get('JAR_API') or '0')
    mode = c.get('MODE', 'local')
    entry = c.get('ENTRY') or 'index.html'
    origin = c.get('ORIGIN', 'file')

    if os.path.exists(out):
        shutil.rmtree(out)
    pkg_dir = os.path.join(out, 'src', *pkg.split('.'))
    res = os.path.join(out, 'res')
    os.makedirs(pkg_dir)
    os.makedirs(os.path.join(res, 'values'))

    # ---- assets ---------------------------------------------------------------
    if mode == 'url':
        start = c.get('URL', 'https://example.com')
    else:
        www = c.get('WWW_DIR', '')
        dst = os.path.join(out, 'assets', 'www')
        shutil.copytree(www, dst, ignore=shutil.ignore_patterns('.git', '__MACOSX', '.DS_Store', 'node_modules'))
        q = urllib.parse.quote(entry.replace('\\', '/'))
        start = ('https://apkb.local/' + q) if origin == 'https' else ('file:///android_asset/www/' + q)

    # ---- orientation / theme --------------------------------------------------
    orient = {'auto': 'unspecified', 'portrait': 'portrait', 'landscape': 'landscape',
              'sensorPortrait': 'sensorPortrait', 'sensorLandscape': 'sensorLandscape',
              'fullSensor': 'fullSensor'}.get(c.get('ORIENTATION', 'auto'), 'unspecified')
    theme = c.get('THEME', 'light')
    actionbar = c.get('ACTIONBAR', '0') == '1'
    if actionbar:
        style = '@android:style/Theme.Material.Light.DarkActionBar' if theme == 'light' else '@android:style/Theme.Material'
    else:
        style = '@android:style/Theme.Material.Light.NoActionBar' if theme == 'light' else '@android:style/Theme.Material.NoActionBar'
    bg = c.get('BG_COLOR') or ('#FFFFFF' if theme == 'light' else '#121212')
    status = c.get('STATUS_COLOR', '')
    nav = c.get('NAV_COLOR', '')
    status_light = (lum(status) > 0.6) if status else (theme == 'light' and not actionbar)

    # ---- permissions ----------------------------------------------------------
    perms = [p for p in c.get('PERMS', 'INTERNET').split(',') if p]
    if mode == 'url' and 'INTERNET' not in perms:
        perms.append('INTERNET')
    if c.get('DOWNLOADS', '1') == '1' and 'STORAGE' not in perms:
        pass  # downloads use MediaStore / DownloadManager; legacy write permission added below
    manifest_perms = []
    runtime_calls = []
    for p in perms:
        for perm, maxsdk in PERM_MAP.get(p, []):
            manifest_perms.append((perm, maxsdk))
        for perm, mn, mx in RUNTIME.get(p, []):
            runtime_calls.append('        addPerm(need, "%s", %d, %d);' % (perm, mn, mx))
    if c.get('DOWNLOADS', '1') == '1':
        manifest_perms.append(('android.permission.WRITE_EXTERNAL_STORAGE', 28))
        runtime_calls.append('        addPerm(need, "android.permission.WRITE_EXTERNAL_STORAGE", 23, 28);')
    seen, plines = set(), []
    for perm, maxsdk in manifest_perms:
        key = (perm, maxsdk)
        if key in seen:
            continue
        seen.add(key)
        if maxsdk:
            plines.append('    <uses-permission android:name="%s" android:maxSdkVersion="%d"/>' % (perm, maxsdk))
        else:
            plines.append('    <uses-permission android:name="%s"/>' % perm)
    feats = []
    if 'CAMERA' in perms:
        feats += ['android.hardware.camera', 'android.hardware.camera.autofocus']
    if 'MIC' in perms:
        feats.append('android.hardware.microphone')
    if 'LOCATION' in perms:
        feats.append('android.hardware.location')
    for f in feats:
        plines.append('    <uses-feature android:name="%s" android:required="false"/>' % f)

    cfg_changes = 'orientation|screenSize|screenLayout|smallestScreenSize|keyboard|keyboardHidden|navigation|uiMode|layoutDirection|fontScale|locale'
    if jar_api == 0 or jar_api >= 24:
        cfg_changes += '|density'

    manifest = '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="%(pkg)s"
    android:versionCode="%(vcode)s"
    android:versionName="%(vname)s">

    <uses-sdk android:minSdkVersion="%(min)s" android:targetSdkVersion="%(target)s"/>
%(perms)s

    <application
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:theme="%(style)s"
        android:allowBackup="%(backup)s"
        android:hardwareAccelerated="true"
        android:supportsRtl="true"
        android:usesCleartextTraffic="%(clear)s">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="%(orient)s"
            android:configChanges="%(cfg)s"
            android:windowSoftInputMode="adjustResize"
            android:launchMode="singleTask">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''' % dict(pkg=pkg, vcode=vcode, vname=vname.replace('&', '&amp;').replace('"', '&quot;').replace('<', '&lt;'),
           min=minsdk, target=target, perms='\n'.join(plines), style=style,
           backup=b(c, 'BACKUP', '0'), clear=b(c, 'CLEARTEXT', '1'), orient=orient, cfg=cfg_changes)
    with open(os.path.join(out, 'AndroidManifest.xml'), 'w', encoding='utf-8') as f:
        f.write(manifest)

    with open(os.path.join(res, 'values', 'strings.xml'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name">%s</string>\n</resources>\n'
                % xml_res(name))

    # ---- icon -----------------------------------------------------------------
    how = icon.install_icon(c.get('ICON', ''), res, 'ic_launcher')
    print('icon: ' + how)

    # ---- splash ---------------------------------------------------------------
    smode = {'none': 0, 'auto': 1, 'image': 2}.get(c.get('SPLASH', 'none'), 0)
    if smode == 2:
        sp = c.get('SPLASH_IMAGE', '')
        outp = ''
        if sp and os.path.isfile(sp):
            os.makedirs(os.path.join(res, 'drawable-nodpi'), exist_ok=True)
            outp = icon.make_splash(sp, os.path.join(res, 'drawable-nodpi', 'apkb_splash'), 720, 1280)
        if not outp:
            print('splash image unusable -> falling back to the auto splash')
            smode = 1

    # ---- java -----------------------------------------------------------------
    tpl = open(os.path.join(HERE, 'MainActivity.java.tpl'), encoding='utf-8').read()
    ua_mode = {'default': 0, 'desktop': 1, 'custom': 2}.get(c.get('UA', 'default'), 0)
    cache = {'default': 0, 'none': 1, 'prefer': 2}.get(c.get('CACHE', 'default'), 0)
    imm = c.get('DISPLAY', 'normal')
    sbg = c.get('SPLASH_BG') or bg
    sfg = c.get('SPLASH_FG') or ('#FFFFFF' if lum(sbg) < 0.5 else '#222222')
    repl = {
        'PKG': pkg,
        'APP_NAME': jstr(name), 'VERSION_NAME': jstr(vname), 'START_URL': jstr(start),
        'BG_COLOR': bg, 'STATUS_COLOR': status, 'NAV_COLOR': nav,
        'STATUS_LIGHT': 'true' if status_light else 'false',
        'FULLSCREEN': 'true' if imm in ('fullscreen', 'immersive') else 'false',
        'IMMERSIVE': 'true' if imm == 'immersive' else 'false',
        'KEEP_ON': b(c, 'KEEP_ON', '0'),
        'JS': b(c, 'JS', '1'), 'DOM': b(c, 'DOM', '1'), 'FILE_ACCESS': b(c, 'FILE_ACCESS', '1'),
        'MIXED': b(c, 'MIXED', '1'), 'ZOOM': b(c, 'ZOOM', '0'), 'LONGPRESS': b(c, 'LONGPRESS', '1'),
        'SELECT': b(c, 'SELECT', '1'), 'AUTOPLAY': b(c, 'AUTOPLAY', '1'), 'UPLOAD': b(c, 'UPLOAD', '1'),
        'DOWNLOADS': b(c, 'DOWNLOADS', '1'), 'JS_DIALOGS': b(c, 'JS_DIALOGS', '1'),
        'FS_VIDEO': b(c, 'FS_VIDEO', '1'), 'BACK_NAV': b(c, 'BACK_NAV', '1'),
        'DOUBLE_BACK': b(c, 'DOUBLE_BACK', '0'), 'PROGRESS': b(c, 'PROGRESS', '0'),
        'SCROLLBARS': b(c, 'SCROLLBARS', '0'), 'DEBUG': b(c, 'DEBUG', '0'),
        'BRIDGE': b(c, 'BRIDGE', '1'), 'BRIDGE_NAME': jstr(c.get('BRIDGE_NAME') or 'Android'),
        'CLEAR_CACHE': b(c, 'CLEAR_CACHE', '0'), 'OFFLINE_PAGE': b(c, 'OFFLINE_PAGE', '1'),
        'EXTERNAL_BROWSER': 'true' if c.get('EXTERNAL', 'browser') == 'browser' else 'false',
        'GEO': 'true' if 'LOCATION' in perms else 'false',
        'CACHE_MODE': str(cache), 'UA_MODE': str(ua_mode), 'CUSTOM_UA': jstr(c.get('UA_CUSTOM', '')),
        'SPLASH_MODE': str(smode), 'SPLASH_MS': str(int(c.get('SPLASH_MS') or 1500)),
        'SPLASH_BG': sbg, 'SPLASH_FG': sfg, 'SPLASH_TAGLINE': jstr(c.get('SPLASH_TAGLINE', '')),
        'SPLASH_VERSION': b(c, 'SPLASH_VERSION', '1'), 'SPLASH_SPINNER': b(c, 'SPLASH_SPINNER', '1'),
        'SPLASH_IMAGE_CODE': 'iv.setImageResource(R.drawable.apkb_splash);' if smode == 2 else '',
        'PERM_CALLS': '\n'.join(runtime_calls),
        'SAVE_IMPL': SAVE_NEW if (jar_api == 0 or jar_api >= 29) else SAVE_OLD,
    }
    for k, v in repl.items():
        tpl = tpl.replace('@@%s@@' % k, v)
    with open(os.path.join(pkg_dir, 'MainActivity.java'), 'w', encoding='utf-8') as f:
        f.write(tpl)

    with open(os.path.join(out, 'project.info'), 'w', encoding='utf-8') as f:
        f.write('name=%s\npackage=%s\nstart=%s\n' % (name, pkg, start))
    print('generated: ' + out)
    return 0


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
