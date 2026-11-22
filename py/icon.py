#!/usr/bin/env python3
"""APKB image helper (works with Pillow, ImageMagick, or neither).

  icon.py default <out.png> <size> [#c1 #c2]
  icon.py install <src|-> <res_dir> <name>      -> mipmap-*/<name>.png
  icon.py splash  <src> <out_base> <w> <h>      -> prints final file path
"""
import os, sys, math, struct, zlib, shutil, subprocess

DENS = [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]


def hex2rgb(h, default):
    h = (h or '').lstrip('#')
    if len(h) >= 6:
        try:
            return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
        except ValueError:
            pass
    return default


def png_bytes(w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def render_default(size, c1=(0, 194, 168), c2=(108, 92, 231)):
    rows = []
    r = size * 0.22
    cx = cy = size / 2.0
    for y in range(size):
        row = bytearray()
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx = max(abs(px - cx) - (size / 2.0 - r), 0)
            dy = max(abs(py - cy) - (size / 2.0 - r), 0)
            alpha = clamp(0.5 - (math.hypot(dx, dy) - r))
            t = (px + py) / (2.0 * size)
            R = c1[0] + (c2[0] - c1[0]) * t
            G = c1[1] + (c2[1] - c1[1]) * t
            B = c1[2] + (c2[2] - c1[2]) * t
            dist = math.hypot(px - cx, py - cy)
            ring = clamp(0.5 - (abs(dist - size * 0.27) - size * 0.045))
            dot = clamp(0.5 - (dist - size * 0.10))
            bar = clamp(0.5 - (max(abs(px - cx) - size * 0.19, abs(py - (cy + size * 0.27)) - size * 0.03)))
            w = max(ring, dot, bar)
            R += (255 - R) * w
            G += (255 - G) * w
            B += (255 - B) * w
            row += bytes((int(R), int(G), int(B), int(alpha * 255)))
        rows.append(row)
    return png_bytes(size, size, rows)


def write_default(path, size, c1=None, c2=None):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(render_default(size, c1 or (0, 194, 168), c2 or (108, 92, 231)))


def lanczos(Image):
    return getattr(Image, 'LANCZOS', None) or Image.Resampling.LANCZOS


def pil_icon(src, dst, size):
    from PIL import Image
    im = Image.open(src).convert('RGBA')
    w, h = im.size
    s = max(w, h)
    canvas = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    canvas.paste(im, ((s - w) // 2, (s - h) // 2))
    canvas.resize((size, size), lanczos(Image)).save(dst, 'PNG')


def magick_icon(src, dst, size):
    exe = shutil.which('magick') or shutil.which('convert')
    if not exe:
        raise RuntimeError('no imagemagick')
    cmd = [exe, src + '[0]', '-background', 'none', '-gravity', 'center',
           '-resize', '%dx%d' % (size, size), '-extent', '%dx%d' % (size, size), dst]
    subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def install_icon(src, res_dir, name):
    used = 'default'
    if src and src != '-' and os.path.isfile(src):
        done = False
        try:
            import PIL  # noqa
            for d, s in DENS:
                p = os.path.join(res_dir, 'mipmap-' + d)
                os.makedirs(p, exist_ok=True)
                pil_icon(src, os.path.join(p, name + '.png'), s)
            done, used = True, 'pillow'
        except Exception:
            pass
        if not done:
            try:
                for d, s in DENS:
                    p = os.path.join(res_dir, 'mipmap-' + d)
                    os.makedirs(p, exist_ok=True)
                    magick_icon(src, os.path.join(p, name + '.png'), s)
                done, used = True, 'imagemagick'
            except Exception:
                pass
        if not done:
            ext = os.path.splitext(src)[1].lower()
            if ext in ('.png', '.jpg', '.jpeg', '.webp'):
                for d, s in DENS:
                    p = os.path.join(res_dir, 'mipmap-' + d)
                    os.makedirs(p, exist_ok=True)
                    shutil.copyfile(src, os.path.join(p, name + ('.jpg' if ext == '.jpeg' else ext)))
                done, used = True, 'copy (no resizer available)'
        if done:
            return used
    for d, s in DENS:
        write_default(os.path.join(res_dir, 'mipmap-' + d, name + '.png'), s)
    return used


def make_splash(src, out_base, w, h):
    ext = os.path.splitext(src)[1].lower()
    try:
        from PIL import Image, ImageOps
        im = Image.open(src)
        im = ImageOps.exif_transpose(im).convert('RGB')
        im = ImageOps.fit(im, (w, h), lanczos(Image))
        if ext in ('.jpg', '.jpeg'):
            out = out_base + '.jpg'
            im.save(out, 'JPEG', quality=88)
        else:
            out = out_base + '.png'
            im.save(out, 'PNG', optimize=True)
        return out
    except Exception:
        pass
    exe = shutil.which('magick') or shutil.which('convert')
    if exe:
        try:
            out = out_base + '.png'
            subprocess.check_call([exe, src + '[0]', '-resize', '%dx%d^' % (w, h), '-gravity', 'center',
                                   '-extent', '%dx%d' % (w, h), out],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return out
        except Exception:
            pass
    if ext in ('.png', '.jpg', '.jpeg', '.webp'):
        out = out_base + ('.jpg' if ext == '.jpeg' else ext)
        shutil.copyfile(src, out)
        return out
    return ''


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    c = sys.argv[1]
    if c == 'default':
        write_default(sys.argv[2], int(sys.argv[3]),
                      hex2rgb(sys.argv[4], None) if len(sys.argv) > 4 else None,
                      hex2rgb(sys.argv[5], None) if len(sys.argv) > 5 else None)
        sys.exit(0)
    if c == 'install':
        print(install_icon(sys.argv[2], sys.argv[3], sys.argv[4]))
        sys.exit(0)
    if c == 'splash':
        out = make_splash(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
        print(out)
        sys.exit(0 if out else 1)
    print(__doc__)
    sys.exit(2)
