#!/usr/bin/env python3
"""APKB auto-fix helper for aapt2/aapt link errors.

  autores.py fix <errlog> <auto_res_dir> <app_label> <attrs_out>

Creates stub resources for missing references (strings, colors, dimens,
icons, styles, ids ...) and writes manifest attributes that the android.jar
does not know into <attrs_out>.
Exit code: 0 = something was fixed, 1 = nothing fixable found.
Prints one line per fix, and 'UNFIXABLE type/name' for the rest.
"""
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icon  # noqa: E402

MISSING = re.compile(r'resource\s+(\w+)/([\w.$]+)(?:\s+\(aka [^)]*\))?\s+not found')
ATTR_MISSING = re.compile(r"attribute\s+'?(android:\w+)'?(?:\s+\(aka [^)]*\))?\s+not found")
ATTR_MISSING2 = re.compile(r"error: attribute (android:\w+) .*not found")

SIMPLE = {
    'string': lambda n, lbl: ('string', '<string name="%s">%s</string>' % (n, esc(lbl if n == 'app_name' else n.replace('_', ' ')))),
    'color': lambda n, lbl: ('color', '<color name="%s">#FF888888</color>' % n),
    'dimen': lambda n, lbl: ('dimen', '<dimen name="%s">16dp</dimen>' % n),
    'integer': lambda n, lbl: ('integer', '<integer name="%s">0</integer>' % n),
    'bool': lambda n, lbl: ('bool', '<bool name="%s">false</bool>' % n),
    'id': lambda n, lbl: ('id', '<item name="%s" type="id"/>' % n),
    'style': lambda n, lbl: ('style', '<style name="%s" parent="@android:style/Theme.Material.Light.NoActionBar"/>' % n),
}


def esc(s):
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"')
    s = s.replace('&', '&amp;').replace('<', '&lt;')
    if s[:1] in '@?':
        s = '\\' + s
    return s


def main(errlog, auto_dir, label, attrs_out):
    try:
        text = open(errlog, 'r', encoding='utf-8', errors='replace').read()
    except Exception:
        return 1
    fixed = []
    unfixable = []
    seen = set()
    stub_file = os.path.join(auto_dir, 'values', 'apkb_stubs.xml')
    existing = ''
    if os.path.isfile(stub_file):
        existing = open(stub_file, encoding='utf-8').read()
    lines = []
    for m in MISSING.finditer(text):
        kind, name = m.group(1), m.group(2)
        key = (kind, name)
        if key in seen:
            continue
        seen.add(key)
        if kind in SIMPLE:
            k, line = SIMPLE[kind](name, label)
            if 'name="%s"' % name in existing:
                continue
            lines.append(line)
            fixed.append('stub %s/%s' % (kind, name))
        elif kind in ('mipmap', 'drawable'):
            d = os.path.join(auto_dir, kind + '-xxhdpi')
            p = os.path.join(d, name + '.png')
            if not os.path.exists(p):
                icon.write_default(p, 144)
                fixed.append('default image %s/%s' % (kind, name))
        else:
            unfixable.append('%s/%s' % (kind, name))
    if lines:
        os.makedirs(os.path.dirname(stub_file), exist_ok=True)
        body = existing
        if not body:
            body = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'
        body = body.replace('</resources>', '    ' + '\n    '.join(lines) + '\n</resources>')
        with open(stub_file, 'w', encoding='utf-8') as f:
            f.write(body)
    attrs = []
    for rx in (ATTR_MISSING, ATTR_MISSING2):
        for m in rx.finditer(text):
            if m.group(1) not in attrs:
                attrs.append(m.group(1))
    if attrs:
        with open(attrs_out, 'w') as f:
            f.write('\n'.join(attrs) + '\n')
        for a in attrs:
            fixed.append('drop unsupported manifest attribute %s' % a)
    for f in fixed:
        print('FIXED ' + f)
    for u in unfixable:
        print('UNFIXABLE ' + u)
    return 0 if fixed else 1


if __name__ == '__main__':
    if len(sys.argv) < 5:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(*sys.argv[2:6]))
