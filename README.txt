APKB 2.0.0 - Android Package Kit Builder (Lab Edition)
======================================================
Termux / Linux tool. Builds raw-Java Android projects (no Gradle, no Flutter) and
HTML -> APK WebView apps. Output is UNSIGNED (you sign it).

Terminal:      bash apkb.sh            (menu)      |  bash apkb.sh --help
Browser lab:   bash apkb.sh broadcast  (or menu [B] "Broadcast Into Browser")
               options: --lan (other devices on your Wi-Fi) --port N --no-open

BROADCAST INTO BROWSER
  Termux/Linux does ALL the work; the browser only shows the graphical lab:
  Build APK, HTML -> APK, Try Before Build, Analyze, APK Inspector, New project,
  Lab Doctor, History & Logs, Settings. Progress, steps and the full console are live.
  The final APK is downloaded from the page. Every FAILED build downloads a log
  file automatically (also saved in <output folder>/logs/*-FAILED.log).
  The link contains a private token; the server listens on 127.0.0.1 by default.

TRY BEFORE BUILD
  Runs your app in a phone frame BEFORE building, using your real layouts, drawables
  (shape/selector/layer-list/vector), values, assets and Java code (a Java interpreter).
  Touch, dialogs, toasts, multi-activity, lifecycle, rotation, dark mode, WebView
  (assets + JS bridge), custom Canvas views, SharedPreferences, Handler/Thread/AsyncTask.
  Permission requests (camera, mic, location, notifications) use the browser's own prompt.
  Problems are shown with the exact file:line, with a built-in editor to fix and reload.
  Not possible in a browser: native .so code, OpenGL ES, Kotlin, third-party libraries
  (their classes are stubbed and listed under "Not supported in the preview").

Failed-build logs, history and settings live in ~/.apkb (shared with the terminal UI).
