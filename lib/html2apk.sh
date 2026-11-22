#!/usr/bin/env bash
# APKB :: HTML -> APK (WebView) wizard

declare -A HV
H_MODE=local; H_WWW=""; H_ENTRY="index.html"; H_URL=""
HTML_LAST="$APKB_HOME/html_last.kv"
HTML_SAVE_KEYS="APP_NAME PKG VERSION_NAME VERSION_CODE MIN_SDK TARGET_SDK ORIENTATION DISPLAY THEME ACTIONBAR BG_COLOR STATUS_COLOR NAV_COLOR ICON SPLASH SPLASH_IMAGE SPLASH_BG SPLASH_FG SPLASH_MS SPLASH_TAGLINE SPLASH_VERSION SPLASH_SPINNER EXTERNAL UA UA_CUSTOM CACHE ORIGIN BRIDGE_NAME JS DOM FILE_ACCESS MIXED ZOOM LONGPRESS SELECT AUTOPLAY UPLOAD DOWNLOADS JS_DIALOGS FS_VIDEO BACK_NAV DOUBLE_BACK KEEP_ON PROGRESS SCROLLBARS BRIDGE OFFLINE_PAGE CLEAR_CACHE DEBUG CLEARTEXT BACKUP P_INTERNET P_CAMERA P_MIC P_LOCATION P_STORAGE P_VIBRATE P_WAKE P_NOTIFY P_BLUETOOTH"

html_defaults() {
  HV=(
    [APP_NAME]="My Web App" [PKG]="" [VERSION_NAME]="1.0" [VERSION_CODE]="1" [MIN_SDK]="21" [TARGET_SDK]=""
    [ORIENTATION]=auto [DISPLAY]=normal [THEME]=light [ACTIONBAR]=0 [BG_COLOR]="" [STATUS_COLOR]="" [NAV_COLOR]=""
    [ICON]="" [SPLASH]=none [SPLASH_IMAGE]="" [SPLASH_BG]="" [SPLASH_FG]="" [SPLASH_MS]=1500
    [SPLASH_TAGLINE]="" [SPLASH_VERSION]=1 [SPLASH_SPINNER]=1
    [EXTERNAL]=browser [UA]=default [UA_CUSTOM]="" [CACHE]=default [ORIGIN]=file [BRIDGE_NAME]=Android
    [JS]=1 [DOM]=1 [FILE_ACCESS]=1 [MIXED]=1 [ZOOM]=0 [LONGPRESS]=1 [SELECT]=1 [AUTOPLAY]=1 [UPLOAD]=1
    [DOWNLOADS]=1 [JS_DIALOGS]=1 [FS_VIDEO]=1 [BACK_NAV]=1 [DOUBLE_BACK]=0 [KEEP_ON]=0 [PROGRESS]=0
    [SCROLLBARS]=0 [BRIDGE]=1 [OFFLINE_PAGE]=1 [CLEAR_CACHE]=0 [DEBUG]=0 [CLEARTEXT]=1 [BACKUP]=0
    [P_INTERNET]=1 [P_CAMERA]=0 [P_MIC]=0 [P_LOCATION]=0 [P_STORAGE]=0 [P_VIBRATE]=0 [P_WAKE]=0 [P_NOTIFY]=0 [P_BLUETOOTH]=0
  )
}

html_load_last() {
  [ -f "$HTML_LAST" ] || return 1
  local k v
  while IFS='=' read -r k v; do
    [ -n "$k" ] && [[ " $HTML_SAVE_KEYS " == *" $k "* ]] && HV[$k]="$v"
  done < "$HTML_LAST"
  return 0
}

html_save_last() {
  local k
  : > "$HTML_LAST"
  for k in $HTML_SAVE_KEYS; do printf '%s=%s\n' "$k" "${HV[$k]}" >> "$HTML_LAST"; done
}

valid_pkg() { [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]; }

norm_color() {  # prints #RRGGBB or returns 1
  local c="${1#\#}"
  [[ "$c" =~ ^[0-9a-fA-F]{3}$ ]] && c="${c:0:1}${c:0:1}${c:1:1}${c:1:1}${c:2:1}${c:2:1}"
  [[ "$c" =~ ^[0-9a-fA-F]{6}$ ]] || return 1
  printf '#%s' "$(printf '%s' "$c" | tr 'a-f' 'A-F')"
}

ask_color() {  # ask_color KEY "Prompt" (empty allowed = auto)
  local key="$1" prompt="$2" a n
  while true; do
    ask a "$prompt" "${HV[$key]:-auto}"
    if [ "$a" = "auto" ] || [ -z "$a" ]; then HV[$key]=""; return 0; fi
    if n="$(norm_color "$a")"; then HV[$key]="$n"; return 0; fi
    warn "Use a hex color like #1E88E5 (or 'auto')"
  done
}

ask_num() {  # ask_num KEY "Prompt" min max
  local key="$1" prompt="$2" lo="$3" hi="$4" a
  while true; do
    ask a "$prompt" "${HV[$key]}"
    if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge "$lo" ] && [ "$a" -le "$hi" ]; then HV[$key]="$a"; return 0; fi
    warn "Enter a number between $lo and $hi"
  done
}

toggle_screen() {  # toggle_screen "Title" ; uses arrays TK / TL
  local a n i
  while true; do
    printf '\n  %s%s%s\n' "$C_B" "$1" "$C_RST"
    for i in "${!TK[@]}"; do
      printf '   %s[%2d]%s [%s] %s\n' "$C_CYN" $((i+1)) "$C_RST" "$([ "${HV[${TK[$i]}]}" = 1 ] && printf '%s' "${C_GRN}x${C_RST}" || printf ' ')" "${TL[$i]}"
    done
    printf '   %stype numbers to flip (e.g. 2 5 9) · Enter = continue%s\n' "$C_DIM" "$C_RST"
    IFS= read -r -p "  ${C_CYN}➜${C_RST} " a || a=""
    [ -z "$a" ] && break
    for n in $a; do
      if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#TK[@]} ]; then
        i=$((n-1))
        [ "${HV[${TK[$i]}]}" = 1 ] && HV[${TK[$i]}]=0 || HV[${TK[$i]}]=1
      fi
    done
  done
}

# ------------------------------------------------------------------- source
html_source() {
  local src dir
  ask_path src "HTML file, HTML5 project folder, .zip, or a website URL"
  case "$src" in
    http://*|https://*) H_MODE=url; H_URL="$src"; return 0 ;;
  esac
  [ -e "$src" ] || { err "Not found: $src"; return 1; }
  H_MODE=local
  dir="$src"
  if [ -f "$src" ]; then
    case "$(printf '%s' "$src" | tr 'A-Z' 'a-z')" in
      *.zip)
        mkdir -p "$WORK/websrc"
        run_step "Extracting zip" unzip -q -o "$src" -d "$WORK/websrc" || { show_tail "$STEP_OUT"; return 1; }
        dir="$WORK/websrc" ;;
      *.html|*.htm)
        if ask_yn "Include the other files in this folder (css/js/images)?" Y; then
          H_WWW="$(cd "$(dirname "$src")" && pwd)"
        else
          mkdir -p "$WORK/www1"; cp "$src" "$WORK/www1/"; H_WWW="$WORK/www1"
        fi
        H_ENTRY="$(basename "$src")"
        return 0 ;;
      *) err "Give an .html file, a folder, or a .zip"; return 1 ;;
    esac
  fi
  # folder (or extracted zip): locate index.html (shallowest)
  local idx
  idx="$(find "$dir" -maxdepth 5 -iname index.html -not -path '*/node_modules/*' 2>/dev/null \
        | awk '{print gsub("/","/") " " $0}' | sort -n | head -n1 | cut -d' ' -f2-)"
  if [ -z "$idx" ]; then
    local pages=() p
    while IFS= read -r p; do pages+=("$p"); done < <(find "$dir" -maxdepth 3 \( -iname '*.html' -o -iname '*.htm' \) 2>/dev/null | head -n 20)
    if [ ${#pages[@]} -eq 0 ]; then err "No HTML files found"; return 1; fi
    menu_pick "No index.html - choose the start page" "${pages[@]#$dir/}" || return 1
    idx="${pages[$((PICK-1))]}"
  fi
  H_WWW="$(dirname "$idx")"; H_ENTRY="$(basename "$idx")"
  ok "Start page: ${idx#$dir/}"
  return 0
}

slugify() { printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9'; }

# ------------------------------------------------------------------- wizard
html_wizard() {
  local a
  section "IDENTITY"
  [ "$H_MODE" = local ] && [ "${HV[APP_NAME]}" = "My Web App" ] && HV[APP_NAME]="$(basename "$(cd "$H_WWW" && pwd)")"
  ask a "App name (any language)" "${HV[APP_NAME]}"; HV[APP_NAME]="$a"
  local slug; slug="$(slugify "${HV[APP_NAME]}")"
  [ -z "$slug" ] && slug="app$RANDOM"
  [ -z "${HV[PKG]}" ] || ! valid_pkg "${HV[PKG]}" && HV[PKG]="com.apkb.$slug"
  while true; do
    ask a "Package id" "${HV[PKG]}"
    if valid_pkg "$a"; then HV[PKG]="$a"; break; fi
    warn "Use letters/digits/underscore with dots, e.g. com.example.myapp"
  done
  ask a "Version name" "${HV[VERSION_NAME]}"; HV[VERSION_NAME]="$a"
  ask_num VERSION_CODE "Version code (integer)" 1 2000000000
  ask_num MIN_SDK "Minimum Android API (21 = Android 5.0, 24 = 7.0, 26 = 8.0)" 21 34
  local dt="${JAR_API:-34}"; [ "$dt" -gt 34 ] && dt=34; [ "$dt" -lt "${HV[MIN_SDK]}" ] && dt="${HV[MIN_SDK]}"
  [ -z "${HV[TARGET_SDK]}" ] && HV[TARGET_SDK]="$dt"
  ask_num TARGET_SDK "Target Android API" "${HV[MIN_SDK]}" 35

  section "ICON"
  dim "PNG recommended (JPG/WEBP/others work if a converter exists). Enter = built-in lab icon."
  ask_path a "App icon path" "${HV[ICON]}"
  if [ -n "$a" ] && [ ! -f "$a" ]; then warn "Icon not found - using the default icon"; a=""; fi
  HV[ICON]="$a"

  section "DISPLAY"
  HV[ORIENTATION]="$(pick_val "Screen orientation" "${HV[ORIENTATION]}" \
    "Auto (follow system):auto" "Portrait only:portrait" "Landscape only:landscape" \
    "Portrait (both directions, sensor):sensorPortrait" "Landscape (both directions, sensor):sensorLandscape" \
    "Free rotation (ignore lock):fullSensor")"
  HV[DISPLAY]="$(pick_val "Screen mode" "${HV[DISPLAY]}" \
    "Normal (status + navigation bars):normal" "Fullscreen (hide status bar):fullscreen" \
    "Immersive (hide all bars, swipe to show):immersive")"
  HV[THEME]="$(pick_val "Theme" "${HV[THEME]}" "Light:light" "Dark:dark")"
  if ask_yn "Show the native title bar (action bar)?" "$([ "${HV[ACTIONBAR]}" = 1 ] && echo Y || echo N)"; then HV[ACTIONBAR]=1; else HV[ACTIONBAR]=0; fi
  ask_color BG_COLOR "Page/background color behind the web page"
  ask_color STATUS_COLOR "Status bar color"
  ask_color NAV_COLOR "Navigation bar color"

  section "SPLASH SCREEN"
  HV[SPLASH]="$(pick_val "Splash screen" "${HV[SPLASH]}" \
    "No splash:none" "Auto info (icon + name + version):auto" "My image (9:16):image")"
  case "${HV[SPLASH]}" in
    auto)
      ask a "Tagline under the name (optional)" "${HV[SPLASH_TAGLINE]}"; HV[SPLASH_TAGLINE]="$a"
      ask_color SPLASH_BG "Splash background color"
      ask_color SPLASH_FG "Splash text color"
      if ask_yn "Show version number?" "$([ "${HV[SPLASH_VERSION]}" = 1 ] && echo Y || echo N)"; then HV[SPLASH_VERSION]=1; else HV[SPLASH_VERSION]=0; fi
      if ask_yn "Show loading spinner?" "$([ "${HV[SPLASH_SPINNER]}" = 1 ] && echo Y || echo N)"; then HV[SPLASH_SPINNER]=1; else HV[SPLASH_SPINNER]=0; fi
      ask_num SPLASH_MS "Minimum splash time (ms)" 0 15000 ;;
    image)
      ask_path a "Splash image path (portrait 9:16 works best)" "${HV[SPLASH_IMAGE]}"
      if [ -f "$a" ]; then HV[SPLASH_IMAGE]="$a"; else warn "Image not found - using the auto splash"; HV[SPLASH]=auto; fi
      ask_color SPLASH_BG "Color behind the image"
      ask_num SPLASH_MS "Minimum splash time (ms)" 0 15000 ;;
  esac

  section "PERMISSIONS"
  TK=(P_INTERNET P_CAMERA P_MIC P_LOCATION P_STORAGE P_VIBRATE P_WAKE P_NOTIFY P_BLUETOOTH)
  TL=("Internet" "Camera" "Microphone" "Location (GPS)" "Files / media read" "Vibrate" "Keep CPU awake (wake lock)" "Notifications (Android 13+)" "Bluetooth")
  toggle_screen "Permissions the app declares and requests"

  section "WEBVIEW FEATURES"
  TK=(JS DOM FILE_ACCESS MIXED ZOOM LONGPRESS SELECT AUTOPLAY UPLOAD DOWNLOADS JS_DIALOGS FS_VIDEO BACK_NAV DOUBLE_BACK KEEP_ON PROGRESS SCROLLBARS BRIDGE OFFLINE_PAGE CLEAR_CACHE CLEARTEXT DEBUG BACKUP)
  TL=("JavaScript" "DOM storage (localStorage, IndexedDB)" "Allow file:// pages to read other local files" "Allow mixed http/https content" "Pinch to zoom" "Allow long-press" "Allow text selection" "Media autoplay (no tap needed)" "File upload (<input type=file>)" "Downloads incl. blob:/data: (save to Downloads)" "JS alert / confirm / prompt dialogs" "Fullscreen video" "Back button goes to previous page" "Double back to exit" "Keep screen on" "Top loading bar" "Show scrollbars" "Native JS bridge (window.Android.toast/vibrate/share/copy/exit)" "Friendly offline/error page" "Clear cache on every start" "Allow http:// (cleartext) traffic" "WebView remote debugging (chrome://inspect)" "Allow Android backup")
  toggle_screen "Features"

  section "ADVANCED"
  HV[EXTERNAL]="$(pick_val "Links to other websites" "${HV[EXTERNAL]}" "Open in the phone browser:browser" "Open inside the app:inside")"
  HV[UA]="$(pick_val "User agent" "${HV[UA]}" "Default mobile:default" "Desktop site:desktop" "Custom:custom")"
  if [ "${HV[UA]}" = custom ]; then ask a "Custom user-agent string" "${HV[UA_CUSTOM]}"; HV[UA_CUSTOM]="$a"; fi
  HV[CACHE]="$(pick_val "Cache mode" "${HV[CACHE]}" "Default:default" "No cache:none" "Prefer cache (offline friendly):prefer")"
  if [ "$H_MODE" = local ]; then
    HV[ORIGIN]="$(pick_val "How local pages are loaded" "${HV[ORIGIN]}" \
      "file:///android_asset (best for video/audio):file" "https://apkb.local virtual origin (modules, fetch, CORS-friendly):https")"
  fi
  if [ "${HV[BRIDGE]}" = 1 ]; then ask a "JS bridge object name" "${HV[BRIDGE_NAME]}"; [[ "$a" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && HV[BRIDGE_NAME]="$a"; fi
}

html_summary() {
  section "SUMMARY"
  kv "Source" "$([ "$H_MODE" = url ] && echo "$H_URL" || echo "$H_WWW/$H_ENTRY")"
  kv "App" "${HV[APP_NAME]}  (${HV[PKG]})"
  kv "Version" "${HV[VERSION_NAME]} (${HV[VERSION_CODE]})"
  kv "Android API" "min ${HV[MIN_SDK]} · target ${HV[TARGET_SDK]}"
  kv "Orientation" "${HV[ORIENTATION]}"
  kv "Screen mode" "${HV[DISPLAY]} · theme ${HV[THEME]}"
  kv "Splash" "${HV[SPLASH]}"
  local perms="" x
  for x in INTERNET CAMERA MIC LOCATION STORAGE VIBRATE WAKE NOTIFY BLUETOOTH; do [ "${HV[P_$x]}" = 1 ] && perms+="$x "; done
  kv "Permissions" "${perms:-none}"
}

html_to_apk() {
  banner
  section "HTML → APK"
  dim "Turn a web page or HTML5 project into a real WebView app."
  new_work "html"
  html_source || { pause; return 1; }
  html_defaults
  if html_load_last && ask_yn "Reuse your last HTML→APK settings as defaults?" Y; then :; else html_defaults; fi
  html_wizard
  html_summary
  ask_yn "Build this app?" Y || { info "Cancelled"; pause; return 0; }
  html_save_last

  local conf="$WORK/html.kv" k perms=""
  : > "$conf"
  for k in "${!HV[@]}"; do printf '%s=%s\n' "$k" "${HV[$k]}" >> "$conf"; done
  local x
  for x in INTERNET CAMERA MIC LOCATION STORAGE VIBRATE WAKE NOTIFY BLUETOOTH; do [ "${HV[P_$x]}" = 1 ] && perms+="$x,"; done
  {
    echo "PERMS=${perms%,}"; echo "MODE=$H_MODE"; echo "WWW_DIR=$H_WWW"; echo "ENTRY=$H_ENTRY"; echo "URL=$H_URL"
    echo "JAR_API=${JAR_API:-0}"
  } >> "$conf"

  run_step "Generating the WebView project" py html2apk.py "$conf" "$WORK/gen" "$APKB_ROOT" || { show_tail "$STEP_OUT"; save_fail_log "HTML project generation failed"; pause; return 1; }
  grep -E '^(icon|splash)' "$STEP_OUT" | sed 's/^/      /'
  PROJECT_ROOT="$WORK/gen"; PROJECT_NAME="${HV[APP_NAME]}"
  analyze_project || { pause; return 1; }
  reset_opts
  OPT_TYPE="$(pick_val "Build type" release "Release:release" "Debuggable:debug")"
  build_core
  local rc=$?
  if [ $rc -eq 0 ] && ask_yn "Also save the generated Java project source (to edit later)?" N; then
    mkdir -p "$OUT_DIR"
    local sd="$OUT_DIR/$(printf '%s' "${HV[PKG]}" | tr -cd 'A-Za-z0-9._-')-src"
    rm -rf "$sd"; cp -r "$WORK/gen" "$sd" && ok "Source saved: $sd"
  fi
  pause
  return $rc
}
