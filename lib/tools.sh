#!/usr/bin/env bash
# APKB :: menus, build flows, inspector, doctor, settings, history

# ------------------------------------------------------------ build options menu
opts_menu() {
  local a
  while true; do
    section "BUILD OPTIONS"
    printf '   %s[1]%s Build type        %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$OPT_TYPE" "$C_RST"
    printf '   %s[2]%s Min SDK           %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_MIN:-auto}" "$C_RST"
    printf '   %s[3]%s Target SDK        %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_TARGET:-auto}" "$C_RST"
    printf '   %s[4]%s Version name      %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_VNAME:-auto}" "$C_RST"
    printf '   %s[5]%s Version code      %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_VCODE:-auto}" "$C_RST"
    printf '   %s[6]%s Package id        %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_PKG:-keep}" "$C_RST"
    printf '   %s[7]%s App name          %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_NAME:-keep}" "$C_RST"
    printf '   %s[8]%s Java level        %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$OPT_LEVEL" "$C_RST"
    printf '   %s[9]%s Java compiler     %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$JAVA_COMPILER" "$C_RST"
    printf '   %s[10]%s Resource engine  %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$RES_ENGINE" "$C_RST"
    printf '   %s[11]%s ABI filter       %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$OPT_ABI" "$C_RST"
    printf '   %s[12]%s Zipalign         %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$([ "$DO_ZIPALIGN" = 1 ] && echo on || echo off)" "$C_RST"
    printf '   %s[13]%s Output file name %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "${OPT_OUTNAME:-auto}" "$C_RST"
    printf '   %s[14]%s Keep work folder %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$([ "$KEEP_WORK" = 1 ] && echo on || echo off)" "$C_RST"
    printf '   %s[15]%s Verbose output   %s%s%s\n'      "$C_CYN" "$C_RST" "$C_GRN" "$([ "$VERBOSE" = 1 ] && echo on || echo off)" "$C_RST"
    printf '   %s[B]%s Build now      %s[0]%s Cancel\n' "$C_GRN" "$C_RST" "$C_DIM" "$C_RST"
    IFS= read -r -p "  ${C_CYN}➜${C_RST} " a || return 1
    case "$a" in
      1) OPT_TYPE="$(pick_val "Build type" "$OPT_TYPE" "Release:release" "Debuggable:debug")" ;;
      2) ask a "Min SDK (number, empty = auto)" "${OPT_MIN}"; [[ -z "$a" || "$a" =~ ^[0-9]+$ ]] && OPT_MIN="$a" || warn "Numbers only" ;;
      3) ask a "Target SDK (number, empty = auto)" "${OPT_TARGET}"; [[ -z "$a" || "$a" =~ ^[0-9]+$ ]] && OPT_TARGET="$a" || warn "Numbers only" ;;
      4) ask a "Version name (empty = auto)" "${OPT_VNAME}"; OPT_VNAME="$a" ;;
      5) ask a "Version code (empty = auto)" "${OPT_VCODE}"; [[ -z "$a" || "$a" =~ ^[0-9]+$ ]] && OPT_VCODE="$a" || warn "Numbers only" ;;
      6) ask a "New package id (empty = keep)" "${OPT_PKG}"; if [ -z "$a" ] || valid_pkg "$a"; then OPT_PKG="$a"; else warn "Invalid package id"; fi ;;
      7) ask a "New app name (empty = keep)" "${OPT_NAME}"; OPT_NAME="$a" ;;
      8) OPT_LEVEL="$(pick_val "Java source level" "$OPT_LEVEL" "Auto (1.8 → 11 → 17):auto" "Java 8:1.8" "Java 11:11" "Java 17:17")" ;;
      9) JAVA_COMPILER="$(pick_val "Java compiler" "$JAVA_COMPILER" "Auto:auto" "ecj:ecj" "javac:javac")" ;;
      10) RES_ENGINE="$(pick_val "Resource engine" "$RES_ENGINE" "Auto:auto" "aapt2:aapt2" "aapt (classic):aapt")" ;;
      11) ask a "ABIs to keep, comma separated (arm64-v8a,armeabi-v7a,x86,x86_64) or 'all'" "$OPT_ABI"; OPT_ABI="${a:-all}" ;;
      12) [ "$DO_ZIPALIGN" = 1 ] && DO_ZIPALIGN=0 || DO_ZIPALIGN=1 ;;
      13) ask a "Output file name without extension (empty = auto)" "${OPT_OUTNAME}"; OPT_OUTNAME="$a" ;;
      14) [ "$KEEP_WORK" = 1 ] && KEEP_WORK=0 || KEEP_WORK=1 ;;
      15) [ "$VERBOSE" = 1 ] && VERBOSE=0 || VERBOSE=1 ;;
      b|B) return 0 ;;
      0|q) return 1 ;;
    esac
  done
}

# ------------------------------------------------------------------ build flows
do_build_project() {  # do_build_project <path> [quick]
  local path="$1" quick="${2:-}"
  prepare_input "$path" || { save_fail_log "Cannot read the project input: $path"; return 1; }
  analyze_project || { save_fail_log "Project scan failed"; return 1; }
  print_report
  if [ -z "$MANIFEST" ] && [ -z "$GUESS_ACTIVITY" ]; then
    err "APKB needs at least an AndroidManifest.xml or an Activity class."
    save_fail_log "No AndroidManifest.xml and no Activity class"
    return 1
  fi
  reset_opts
  if [ -z "$quick" ]; then
    local m
    m="$(pick_val "How do you want to build?" quick "Quick build (auto settings):quick" "Custom options:custom")"
    if [ "$m" = custom ]; then opts_menu || { info "Cancelled"; return 0; }; fi
  fi
  build_core
}

build_menu() {
  while true; do
    banner
    section "BUILD APK"
    if ! menu_pick "" "My project (zip or folder)" "Test APK (Example app)"; then return 0; fi
    case "$PICK" in
      1)
        local p
        dim "Give a .zip (folder inside it or files directly) or a project folder."
        ask_path p "Project path"
        [ -z "$p" ] && continue
        do_build_project "$p"; pause ;;
      2)
        build_test_apk; pause ;;
    esac
  done
}

build_test_apk() {
  new_work "example"
  mkdir -p "$WORK/src"
  run_step "Creating the Example project" py scaffold.py flat "$WORK/src" "APKB Example" "com.apkb.example" "Hello Android!, I'm APKB!" || { show_tail "$STEP_OUT"; return 1; }
  PROJECT_ROOT="$WORK/src"; PROJECT_NAME="APKB-Example"
  analyze_project || return 1
  print_report
  reset_opts
  OPT_OUTNAME="APKB-Example"
  KEEP_WORK=0 build_core
}

new_project_wizard() {
  banner
  section "NEW PROJECT"
  dim "Creates a small raw-Java Android project you can edit and build with APKB."
  local style name pkg dest
  style="$(pick_val "Folder layout" flat "Flat (AndroidManifest.xml, src/, res/, assets/):flat" "Gradle-like (app/src/main/...):gradle" "Eclipse/ADT-like (+ libs/):eclipse")"
  ask name "App name" "My App"
  pkg="com.apkb.$(slugify "$name")"; [ "$pkg" = "com.apkb." ] && pkg="com.apkb.app"
  while true; do ask pkg "Package id" "$pkg"; valid_pkg "$pkg" && break; warn "Invalid package id"; done
  ask_path dest "Create it in folder" "$OUT_DIR/projects/$(slugify "$name")"
  mkdir -p "$dest"
  if py scaffold.py "$style" "$dest" "$name" "$pkg" >/dev/null; then
    ok "Project created: $dest"
    info "Build it with: Build APK → My project → $dest"
  else
    err "Could not create the project"
  fi
  pause
}

# --------------------------------------------------------------------- analyze
analyze_menu() {
  banner
  section "ANALYZE PROJECT"
  local p; ask_path p "Project path (zip or folder)"
  [ -z "$p" ] && return 0
  prepare_input "$p" && analyze_project && print_report
  if [ -n "${S:-}" ] && [ -s "$S/dups.txt" ]; then section "IGNORED DUPLICATES"; head -n 8 "$S/dups.txt" | sed 's/^/    /'; fi
  pause
}

# ------------------------------------------------------------------- inspector
inspect_apk() {
  local apk="$1"
  [ -f "$apk" ] || { err "APK not found: $apk"; return 1; }
  section "APK INSPECTOR"
  kv "File" "$(basename "$apk")"
  kv "Size" "$(human_size "$(stat -c %s "$apk")")"
  kv "SHA-256" "$(sha256sum "$apk" | cut -c1-32)…"
  local list; list="$(unzip -Z1 "$apk" 2>/dev/null)"
  if grep -q '^META-INF/.*\.\(RSA\|DSA\|EC\)$' <<<"$list" || grep -q '^META-INF/CERT' <<<"$list"; then
    kv "Signature" "${C_GRN}v1 signature present${C_RST}"
  else
    kv "Signature" "${C_YEL}no v1 signature (unsigned or v2+ only)${C_RST}"
  fi
  kv "Dex files" "$(grep -c '^classes[0-9]*\.dex$' <<<"$list")"
  kv "Entries" "$(wc -l <<<"$list")"
  local b=""
  [ -n "$AAPT2" ] && b="$("$AAPT2" dump badging "$apk" 2>/dev/null)"
  [ -z "$b" ] && [ -n "$AAPT" ] && b="$("$AAPT" dump badging "$apk" 2>/dev/null)"
  if [ -n "$b" ]; then
    sed -n "s/^package: name='\([^']*\)'.*versionCode='\([^']*\)'.*versionName='\([^']*\)'.*/Package     \1  v\3 (\2)/p" <<<"$b" | sed 's/^/  /'
    sed -n "s/^sdkVersion:'\(.*\)'/  Min SDK     \1/p; s/^targetSdkVersion:'\(.*\)'/  Target SDK  \1/p; s/^application-label:'\(.*\)'/  Label       \1/p; s/^launchable-activity: name='\([^']*\)'.*/  Launcher    \1/p; s/^native-code: \(.*\)/  ABIs        \1/p" <<<"$b"
    section "PERMISSIONS"
    sed -n "s/^uses-permission: name='\(.*\)'.*/    \1/p" <<<"$b" | sed 's/android.permission.//' | head -n 40
  fi
  section "BIGGEST ENTRIES"
  unzip -lv "$apk" 2>/dev/null | awk 'NR>3 && NF>=8 && $1 ~ /^[0-9]+$/ {print $1, $NF}' | sort -rn | head -n 8 \
    | while read -r sz nm; do printf '    %10s  %s\n' "$(human_size "$sz")" "$nm"; done
}

inspect_menu() {
  banner
  section "APK INSPECTOR"
  local p; ask_path p "Path to an APK"
  [ -n "$p" ] && inspect_apk "$p"
  pause
}

# ---------------------------------------------------------------------- doctor
doctor() {
  banner
  section "LAB DOCTOR"
  detect_pm; resolve_tools
  kv "Platform" "$([ "$IS_TERMUX" = 1 ] && echo Termux || uname -s) · pkg mgr: ${PM:-none}"
  kv "APKB" "$APKB_VERSION  ($APKB_ROOT)"
  local t
  for t in "java:$JAVA" "javac:$JAVAC" "aapt2:$AAPT2" "aapt:$AAPT" "d8:$D8" "dx:$DX" "ecj:$ECJ" "zipalign:$ZIPALIGN" "zip:$(command -v zip)" "unzip:$(command -v unzip)" "python3:$(command -v python3)"; do
    if [ -n "${t#*:}" ]; then printf '  %s●%s %-9s %s%s%s\n' "$C_GRN" "$C_RST" "${t%%:*}" "$C_DIM" "${t#*:}" "$C_RST"
    else printf '  %s○%s %-9s %snot installed%s\n' "$C_RED" "$C_RST" "${t%%:*}" "$C_DIM" "$C_RST"; fi
  done
  python3 -c "import PIL" 2>/dev/null && ok "Pillow: icon/splash resizing available" || warn "Pillow missing: icons will use ImageMagick or be copied as-is"
  [ -n "$JAVA" ] && kv "Java" "$(java -version 2>&1 | head -n1)"
  [ -n "$ANDROID_JAR" ] && kv "android.jar" "$ANDROID_JAR (API ${JAR_API:-?})" || warn "android.jar not set"
  kv "Output" "$OUT_DIR"
  [ -w "$(dirname "$OUT_DIR")" ] && ok "Output location is writable" || warn "Output location not writable (Termux: run termux-setup-storage)"
  local mem; mem="$(awk '/MemAvailable/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null)"
  [ -n "$mem" ] && kv "Free RAM" "$mem"
  echo
  if ask_yn "Install / repair missing packages now?" Y; then ensure_deps; fi
  pause
}

# -------------------------------------------------------------------- settings
settings_menu() {
  while true; do
    banner
    section "SETTINGS"
    kv "android.jar" "${ANDROID_JAR:-not set}"
    kv "Output folder" "$OUT_DIR"
    kv "Java compiler" "$JAVA_COMPILER"
    kv "Resource engine" "$RES_ENGINE"
    kv "Zipalign" "$([ "$DO_ZIPALIGN" = 1 ] && echo on || echo off)"
    kv "Keep work" "$([ "$KEEP_WORK" = 1 ] && echo on || echo off)"
    kv "Verbose" "$([ "$VERBOSE" = 1 ] && echo on || echo off)"
    menu_pick "" "Change android.jar" "Change output folder" "Java compiler" "Resource engine" "Toggle zipalign" "Toggle keep work folder" "Toggle verbose" "Reset all settings" || return 0
    case "$PICK" in
      1) cfg_set ANDROID_JAR ""; ensure_android_jar ;;
      2) local d; ask_path d "Output folder" "$OUT_DIR"; [ -n "$d" ] && { mkdir -p "$d" && cfg_set OUT_DIR "$d"; } ;;
      3) cfg_set JAVA_COMPILER "$(pick_val "Java compiler" "$JAVA_COMPILER" "Auto:auto" "ecj:ecj" "javac:javac")" ;;
      4) cfg_set RES_ENGINE "$(pick_val "Resource engine" "$RES_ENGINE" "Auto:auto" "aapt2:aapt2" "aapt (classic):aapt")" ;;
      5) [ "$DO_ZIPALIGN" = 1 ] && cfg_set DO_ZIPALIGN 0 || cfg_set DO_ZIPALIGN 1 ;;
      6) [ "$KEEP_WORK" = 1 ] && cfg_set KEEP_WORK 0 || cfg_set KEEP_WORK 1 ;;
      7) [ "$VERBOSE" = 1 ] && cfg_set VERBOSE 0 || cfg_set VERBOSE 1 ;;
      8) ask_yn "Delete all APKB settings?" N && { rm -f "$CFG"; ANDROID_JAR=""; OUT_DIR="$(default_out_dir)"; JAVA_COMPILER=auto; RES_ENGINE=auto; DO_ZIPALIGN=1; KEEP_WORK=0; VERBOSE=0; ok "Settings reset"; sleep 1; } ;;
    esac
  done
}

# --------------------------------------------------------------------- history
history_menu() {
  banner
  section "BUILD HISTORY"
  if [ -s "$APKB_HOME/history.log" ]; then
    tail -n 12 "$APKB_HOME/history.log" | awk -F'\t' '{ printf "  %s  %-18s %s\n", substr($1,6,11), substr($2,1,18), ($3=="FAILED" ? "FAILED" : $3) }'
  else
    dim "No builds yet."
  fi
  local last; last="$(ls -t "$APKB_HOME"/logs/*.log 2>/dev/null | head -n1)"
  if [ -n "$last" ] && ask_yn "View the last build log?" N; then
    ${PAGER:-less} "$last" 2>/dev/null || tail -n 80 "$last"
  fi
  pause
}

clean_menu() {
  banner
  section "CLEAN WORKSPACE"
  local sz; sz="$(du -sh "$APKB_HOME/work" 2>/dev/null | cut -f1)"
  kv "Work folders" "${sz:-0}"
  if ask_yn "Delete all temporary work folders?" Y; then rm -rf "$APKB_HOME/work"; mkdir -p "$APKB_HOME/work"; ok "Cleaned"; fi
  if ask_yn "Delete saved build logs too?" N; then rm -rf "$APKB_HOME/logs"; mkdir -p "$APKB_HOME/logs"; ok "Logs removed"; fi
  pause
}

# ------------------------------------------------------------------ main menu
help_text() {
  cat <<EOF
APKB $APKB_VERSION - Android Package Kit Builder (lab edition)

Usage:
  apkb                     interactive lab menu
  apkb build <zip|dir>     quick build of a source project
  apkb html  <html|dir|zip|url>   HTML to APK wizard
  apkb inspect <apk>       inspect an APK
  apkb doctor              check/install tools
  apkb broadcast [--lan] [--port N] [--no-open]
                           Broadcast Into Browser: the whole lab as a web UI
  apkb --install           install the 'apkb' command
EOF
}

install_cmd() {
  local bin="${PREFIX:-$HOME/.local}/bin"
  mkdir -p "$bin"
  ln -sf "$APKB_SELF" "$bin/apkb" && chmod +x "$APKB_SELF" && ok "Installed: $bin/apkb"
}

main_menu() {
  while true; do
    banner
    printf '   %s[1]%s Build APK\n' "$C_CYN" "$C_RST"
    printf '   %s[2]%s %sHTML → APK%s  %s★ WebView app maker%s\n' "$C_CYN" "$C_RST" "$C_B$C_ORG" "$C_RST" "$C_ORG" "$C_RST"
    printf '   %s[3]%s Analyze project\n' "$C_CYN" "$C_RST"
    printf '   %s[4]%s APK Inspector\n' "$C_CYN" "$C_RST"
    printf '   %s[5]%s New project (scaffold)\n' "$C_CYN" "$C_RST"
    printf '   %s[6]%s Lab Doctor\n' "$C_CYN" "$C_RST"
    printf '   %s[7]%s Settings\n' "$C_CYN" "$C_RST"
    printf '   %s[8]%s Build history & logs\n' "$C_CYN" "$C_RST"
    printf '   %s[9]%s Clean workspace\n' "$C_CYN" "$C_RST"
    printf '   %s[B]%s %sBroadcast Into Browser%s  %s★ graphical lab · Try Before Build%s\n' "$C_CYN" "$C_RST" "$C_B$C_GRN" "$C_RST" "$C_GRN" "$C_RST"
    printf '   %s[0]%s Exit\n' "$C_DIM" "$C_RST"
    local a; IFS= read -r -p "  ${C_CYN}➜${C_RST} " a || exit 0
    case "$a" in
      1) ensure_ready && build_menu ;;
      2) ensure_ready && { jar_is_new_enough 23 || warn "HTML→APK needs android.jar API 23+ (yours is ${JAR_API})"; html_to_apk; } ;;
      3) analyze_menu ;;
      4) inspect_menu ;;
      5) new_project_wizard ;;
      6) doctor ;;
      7) settings_menu ;;
      8) history_menu ;;
      9) clean_menu ;;
      b|B|10) broadcast_menu ;;
      0|q) printf '\n  %sLab powered down. Happy building!%s\n\n' "$C_DIM" "$C_RST"; exit 0 ;;
    esac
  done
}

READY=0
ensure_ready() {
  [ "$READY" = 1 ] && return 0
  ensure_deps || { pause; return 1; }
  ensure_android_jar || { pause; return 1; }
  ensure_out_dir
  READY=1
  return 0
}

main() {
  cfg_load
  resolve_tools
  case "${1:-}" in
    -h|--help|help) help_text; exit 0 ;;
    --install) install_cmd; exit 0 ;;
    doctor) doctor; exit 0 ;;
    broadcast) shift; broadcast_cmd "$@"; exit $? ;;
    __job) shift; job_main "$@"; exit $? ;;
    inspect) resolve_tools; inspect_apk "$(clean_path "${2:-}")"; exit $? ;;
    build)
      ensure_ready || exit 1
      [ -z "${2:-}" ] && { err "Usage: apkb build <zip|dir>"; exit 1; }
      do_build_project "$(clean_path "$2")" quick; exit $? ;;
    html)
      ensure_ready || exit 1
      html_to_apk; exit $? ;;
  esac
  main_menu
}
