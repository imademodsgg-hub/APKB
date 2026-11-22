#!/usr/bin/env bash
# APKB :: Broadcast Into Browser
# Termux / Linux does ALL the processing; the browser only shows the graphical lab.
#   broadcast_menu / broadcast_cmd  -> starts the local web server (server/apkb_server.py)
#   job_main                        -> non-interactive entry used by the server for every task

free_port() {  # free_port [start]
  python3 - "${1:-8765}" <<'PY'
import socket, sys
p = int(sys.argv[1])
for q in range(p, p + 60):
    s = socket.socket()
    try:
        s.bind(('0.0.0.0', q)); s.close(); print(q); break
    except OSError:
        s.close()
PY
}

lan_ip() {
  python3 - <<'PY' 2>/dev/null
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(('10.255.255.255', 1)); print(s.getsockname()[0])
except Exception:
    print('')
PY
}

open_url() {
  local u="$1"
  if have termux-open-url; then termux-open-url "$u" >/dev/null 2>&1 && return 0; fi
  if [ "$IS_TERMUX" = 1 ] && have am; then am start --user 0 -a android.intent.action.VIEW -d "$u" >/dev/null 2>&1 && return 0; fi
  if have xdg-open; then xdg-open "$u" >/dev/null 2>&1 & return 0; fi
  return 1
}

broadcast_menu() {
  banner
  section "BROADCAST INTO BROWSER"
  dim "Serves the full APKB lab as a graphical website from this session."
  dim "Termux/Linux processes everything - the browser only displays it."
  local m
  m="$(pick_val "Who can open the page?" local "This device only (127.0.0.1) - safest:local" "Other devices on my Wi-Fi / LAN:lan")"
  local port; ask port "Port" "$(free_port 8765)"
  [[ "$port" =~ ^[0-9]+$ ]] || port=8765
  local args=(--port "$port"); [ "$m" = lan ] && args+=(--lan)
  broadcast_cmd "${args[@]}"
  pause
}

broadcast_cmd() {
  local lan=0 port="" noopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --lan) lan=1 ;;
      --port) shift; port="$1" ;;
      --no-open) noopen=1 ;;
    esac
    shift
  done
  have python3 || { err "python3 is required"; return 1; }
  [ -z "$port" ] && port="$(free_port 8765)"
  [ -z "$port" ] && { err "No free port found"; return 1; }
  local token host url ip
  token="$(python3 -c 'import secrets;print(secrets.token_urlsafe(12))')"
  [ "$lan" = 1 ] && host=0.0.0.0 || host=127.0.0.1
  url="http://127.0.0.1:$port/?t=$token"
  section "BROADCASTING"
  ok "APKB lab is live"
  kv "This device" "$url"
  if [ "$lan" = 1 ]; then
    ip="$(lan_ip)"
    [ -n "$ip" ] && kv "Local network" "http://$ip:$port/?t=$token" || warn "Could not detect the LAN address"
    warn "Anyone with this link can use the lab. Keep it private."
  fi
  dim "The link contains a private access token. Press Ctrl+C to stop broadcasting."
  [ "$noopen" = 0 ] && { open_url "$url" && info "Opening your browser..." || dim "Open the link above in your browser."; }
  echo
  ( cd "$APKB_ROOT" && APKB_SELF="$APKB_SELF" python3 "$APKB_ROOT/server/apkb_server.py" \
      --root "$APKB_ROOT" --home "$APKB_HOME" --host "$host" --port "$port" --token "$token" --version "$APKB_VERSION" )
  echo
  info "Broadcast stopped"
}

# ============================================================ non-interactive jobs
apply_env_opts() {
  OPT_TYPE="${APKB_O_TYPE:-release}"; OPT_MIN="${APKB_O_MIN:-}"; OPT_TARGET="${APKB_O_TARGET:-}"
  OPT_VNAME="${APKB_O_VNAME:-}"; OPT_VCODE="${APKB_O_VCODE:-}"; OPT_PKG="${APKB_O_PKG:-}"; OPT_NAME="${APKB_O_NAME:-}"
  OPT_LEVEL="${APKB_O_LEVEL:-auto}"; OPT_ABI="${APKB_O_ABI:-all}"; OPT_OUTNAME="${APKB_O_OUTNAME:-}"
  [ -n "${APKB_O_COMPILER:-}" ] && JAVA_COMPILER="$APKB_O_COMPILER"
  [ -n "${APKB_O_RESENG:-}" ] && RES_ENGINE="$APKB_O_RESENG"
  [ -n "${APKB_O_ZIPALIGN:-}" ] && DO_ZIPALIGN="$APKB_O_ZIPALIGN"
  [ -n "${APKB_O_KEEP:-}" ] && KEEP_WORK="$APKB_O_KEEP"
  [ -n "${APKB_O_VERBOSE:-}" ] && VERBOSE="$APKB_O_VERBOSE"
  return 0
}

job_ready() {
  ensure_deps || { err "Required tools are missing and could not be installed"; emit need tools; return 1; }
  if [ -z "$ANDROID_JAR" ] || ! validate_jar "$ANDROID_JAR"; then
    err "android.jar is not set. Open Settings and give its path."; emit need android_jar; return 1
  fi
  detect_jar_api; ensure_out_dir
  return 0
}

job_doctor() {
  detect_pm; resolve_tools
  local t
  for t in "java:$JAVA" "javac:$JAVAC" "aapt2:$AAPT2" "aapt:$AAPT" "d8:$D8" "dx:$DX" "ecj:$ECJ" "zipalign:$ZIPALIGN" "zip:$(command -v zip)" "unzip:$(command -v unzip)" "python3:$(command -v python3)"; do
    emit "tool.${t%%:*}" "${t#*:}"
  done
  [ -n "$ANDROID_JAR" ] && validate_jar "$ANDROID_JAR" && detect_jar_api
  emit platform "$([ "$IS_TERMUX" = 1 ] && echo Termux || uname -s)"
  emit pm "${PM:-none}"
  emit apkb "$APKB_VERSION"
  emit android_jar "${ANDROID_JAR:-}"; emit jar_api "${JAR_API:-}"
  emit out_dir "$OUT_DIR"
  [ -n "$JAVA" ] && emit java_version "$(java -version 2>&1 | grep -v Picked | head -n1)"
  python3 -c "import PIL" 2>/dev/null && emit pillow 1 || emit pillow 0
  local mem; mem="$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"; [ -n "$mem" ] && emit ram_mb "$mem"
  [ -w "$(dirname "$OUT_DIR")" ] && emit out_writable 1 || emit out_writable 0
  ok "Doctor finished"
}

job_build() {  # job_build <zip|dir>
  job_ready || return 1
  local path="$1"
  prepare_input "$path" || { save_fail_log "Cannot read the project input: $path"; return 1; }
  analyze_project || { save_fail_log "Project scan failed"; return 1; }
  print_report
  if [ -z "$MANIFEST" ] && [ -z "$GUESS_ACTIVITY" ]; then
    err "APKB needs at least an AndroidManifest.xml or an Activity class."
    save_fail_log "No AndroidManifest.xml and no Activity class"; return 1
  fi
  reset_opts; apply_env_opts
  emit work "$WORK"
  build_core
}

job_test() {
  job_ready || return 1
  new_work "example"
  mkdir -p "$WORK/src"
  run_step "Creating the Example project" py scaffold.py flat "$WORK/src" "APKB Example" "com.apkb.example" "Hello Android!, I'm APKB!" || { show_tail "$STEP_OUT"; save_fail_log "Example project creation failed"; return 1; }
  PROJECT_ROOT="$WORK/src"; PROJECT_NAME="APKB-Example"
  analyze_project || return 1
  print_report
  reset_opts; apply_env_opts; OPT_OUTNAME="APKB-Example"
  KEEP_WORK=0 build_core
}

job_html() {  # job_html <conf.kv written by the server>
  job_ready || return 1
  local conf_in="$1"
  new_work "html"
  cp "$conf_in" "$WORK/html.kv" || { err "Cannot read the HTML settings"; return 1; }
  echo "JAR_API=${JAR_API:-0}" >> "$WORK/html.kv"
  local name; name="$(sed -n 's/^APP_NAME=//p' "$WORK/html.kv" | head -n1)"
  run_step "Generating the WebView project" py html2apk.py "$WORK/html.kv" "$WORK/gen" "$APKB_ROOT" || { show_tail "$STEP_OUT"; save_fail_log "HTML project generation failed"; return 1; }
  grep -E '^(icon|splash)' "$STEP_OUT" | sed 's/^/      /'
  PROJECT_ROOT="$WORK/gen"; PROJECT_NAME="${name:-WebApp}"
  analyze_project || return 1
  reset_opts; apply_env_opts
  emit work "$WORK"
  build_core
  local rc=$?
  if [ $rc -eq 0 ] && [ "${APKB_O_SAVESRC:-0}" = 1 ]; then
    local pk sd; pk="$(sed -n 's/^PKG=//p' "$WORK/html.kv" | head -n1)"
    sd="$OUT_DIR/$(printf '%s' "$pk" | tr -cd 'A-Za-z0-9._-')-src"
    rm -rf "$sd"; cp -r "$WORK/gen" "$sd" && { ok "Source saved: $sd"; emit src_dir "$sd"; }
  fi
  return $rc
}

job_scaffold() {  # job_scaffold <style> <dest> <name> <pkg>
  py scaffold.py "$1" "$2" "$3" "$4" >/dev/null && ok "Project created: $2" || { err "Could not create the project"; return 1; }
}

job_main() {
  export APKB_JOB=1
  local kind="${1:-}"; shift
  # the server owns the console, so a job never asks questions
  case "$kind" in
    doctor)   job_doctor ;;
    install)  detect_pm; ensure_deps ;;
    build)    job_build "$@" ;;
    test)     job_test ;;
    html)     job_html "$@" ;;
    inspect)  resolve_tools; inspect_apk "$1" ;;
    scaffold) job_scaffold "$@" ;;
    *) err "Unknown job: $kind"; return 2 ;;
  esac
}
