<div align="center">

<img src="docs/icon.svg" width="96" alt="APKB logo">

# APKB · Android Package Kit Builder

**Build real Android APKs from a terminal. No Gradle, no Flutter, no PC.**

[![Version](https://img.shields.io/badge/version-2.0.0-3DDC84?style=flat-square)](https://github.com/imademodsgg-hub/APKB/releases/tag/v2.0)
[![Platform](https://img.shields.io/badge/platform-Termux%20%C2%B7%20Linux-073042?style=flat-square)](https://github.com/imademodsgg-hub/APKB)
[![Stack](https://img.shields.io/badge/stack-bash%20%C2%B7%20python%20stdlib-4DD0E1?style=flat-square)](https://github.com/imademodsgg-hub/APKB)
[![Output](https://img.shields.io/badge/output-unsigned%20APK%20(you%20sign%20it)-FFCA28?style=flat-square)](#you-sign-it)

[Website](https://imademodsgg-hub.github.io/APKB/) · [Download v2.0](https://github.com/imademodsgg-hub/APKB/releases/tag/v2.0) · [Report an issue](https://github.com/imademodsgg-hub/APKB/issues)

</div>

---

APKB compiles raw Java into installable Android APKs on **Termux or Linux**, with no build system in the middle. It can also turn any HTML project into a WebView app, broadcast a full graphical lab into your browser, and run your app in a phone simulator **before** you build it.

## Highlights

- **Raw Java → APK.** Point APKB at any Android source tree, whatever its folder layout. The scanner finds the manifest, resources, Java sources and libraries, then the pipeline builds a release or debug APK.
- **HTML → APK wizard.** Turn a website or local HTML project into a real WebView app: splash screen, icon, theme colors, orientation, JS bridge, offline page and permissions, from one guided flow.
- **Broadcast Into Browser.** `bash apkb.sh broadcast` opens a graphical lab in your browser. Termux/Linux still does all the processing; the page streams live progress, steps and the full console, and the finished APK downloads from the page.
- **Try Before Build.** Run your app in a phone frame before compiling. Your real layouts, drawables, values, assets and Java code are interpreted live in the browser, with touch, dialogs, toasts, multi-activity navigation, lifecycle, rotation, dark mode, WebView, Canvas views, SharedPreferences, Handler/Thread/AsyncTask and browser-native permission prompts.
- **Project Checker.** Broken resource references, missing permissions and bad imports are caught before any build starts, reported with the exact file and line, a hint, and a built-in editor to fix and reload.
- **APK Inspector, Analyzer and Lab Doctor.** Inspect any APK's manifest, permissions and contents, analyze a project, and diagnose your toolchain. Every failed build saves a full log automatically.

## The pipeline

No Gradle daemon, no wrapper, no magic. APKB drives the real Android toolchain step by step:

```
source (Java + res + manifest)
        │
        ▼
 aapt2 / aapt   compile resources
        │
        ▼
 ecj / javac    compile Java
        │
        ▼
 d8 / dx        dex bytecode
        │
        ▼
 zipalign       align & package
        │
        ▼
    app.apk     unsigned, ready to sign
```

## Get started

Requirements: **Termux** on Android, or any **Linux** with bash, Java and Python 3. Missing Android build tools are installed for you on first run.

```bash
git clone https://github.com/imademodsgg-hub/APKB.git
cd APKB

# terminal menu
bash apkb.sh

# or open the graphical lab in your browser
bash apkb.sh broadcast          # add --lan to reach it from other devices on your Wi-Fi
```

The browser lab listens on `127.0.0.1` behind a one-time token by default. Progress, history, failed-build logs and settings live in `~/.apkb`, shared between the terminal UI and the browser lab.

## You sign it

APKB produces an **unsigned APK** by design. Sign it with `apksigner` and your own key before installing or publishing:

```bash
apksigner sign --ks my-key.jks app-release.apk
```

## Honest limits of the browser preview

Native `.so` code, OpenGL ES, Kotlin and third-party libraries can't run inside a browser. Their classes are stubbed and listed under "Not supported in the preview".

## Project layout

```
apkb.sh        entry point (menu, --help, broadcast)
lib/           bash pipeline: build, html2apk, scan, deps, tools, broadcast, ui
py/            python helpers: scanner, checker, manifest, html2apk, scaffolding
server/        Broadcast Into Browser server (Python stdlib only)
web/           the browser lab UI, including the Try Before Build simulator
```

---

<div align="center">
APKB v2.0.0 · Lab Edition · Made for people who like to see what their tools are doing.
</div>
