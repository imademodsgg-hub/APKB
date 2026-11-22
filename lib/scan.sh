#!/usr/bin/env bash
# APKB :: project input resolving + analysis

PROJECT_ROOT=""; PROJECT_NAME=""; WORK=""; LOG=""; S=""
py() { python3 "$APKB_ROOT/py/$1" "${@:2}"; }

new_work() {  # new_work name
  local slug
  slug="$(printf '%s' "$1" | tr -cd 'A-Za-z0-9._-' | cut -c1-24)"
  [ -z "$slug" ] && slug="project"
  WORK="$APKB_HOME/work/$(now_ts)-$slug"
  mkdir -p "$WORK" "$WORK/scan"
  S="$WORK/scan"
  LOG="$WORK/build.log"
  : > "$LOG"
  STEP_N=0
}

prepare_input() {  # prepare_input <zip|dir>
  local in="$1" low
  if [ -z "$in" ] || [ ! -e "$in" ]; then err "Path not found: ${in:-<empty>}"; return 1; fi
  new_work "$(basename "$in")"
  if [ -d "$in" ]; then
    PROJECT_ROOT="$(cd "$in" && pwd)"
    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    return 0
  fi
  low="$(printf '%s' "$in" | tr 'A-Z' 'a-z')"
  PROJECT_NAME="$(basename "$in")"; PROJECT_NAME="${PROJECT_NAME%.*}"
  mkdir -p "$WORK/src"
  case "$low" in
    *.zip)
      run_step "Extracting zip" unzip -q -o "$in" -d "$WORK/src" || {
        # some zips carry non-UTF8 names / odd headers - try python as a fallback
        run_step "Extracting zip (fallback)" python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$in" "$WORK/src" || { show_tail "$STEP_OUT"; return 1; }
      } ;;
    *.tar.gz|*.tgz) run_step "Extracting archive" tar -xzf "$in" -C "$WORK/src" || return 1 ;;
    *.tar)          run_step "Extracting archive" tar -xf "$in" -C "$WORK/src" || return 1 ;;
    *) err "Unsupported input. Give a project folder or a .zip file."; return 1 ;;
  esac
  PROJECT_ROOT="$WORK/src"
  return 0
}

MANIFEST=""; MAIN_ROOT=""; LAYOUT=""
analyze_project() {
  MANIFEST=""; MAIN_ROOT=""; LAYOUT=""; GRADLE_NAMESPACE=""; GRADLE_APPID=""; GRADLE_MIN=""
  GRADLE_TARGET=""; GRADLE_VCODE=""; GRADLE_VNAME=""; GUESS_ACTIVITY=""; GUESS_PACKAGE=""
  run_step "Scanning project structure" py scan.py scan "$PROJECT_ROOT" "$S" || { show_tail "$STEP_OUT"; return 1; }
  # shellcheck disable=SC1091
  . "$S/scan.env"
  return 0
}

print_report() {
  local root="$PROJECT_ROOT"
  section "PROJECT ANALYSIS"
  kv "Layout" "${LAYOUT:-unknown}"
  if [ -n "$MANIFEST" ]; then kv "Manifest" "${MANIFEST#$root/}"; else kv "Manifest" "${C_YEL}missing${C_RST}"; fi
  kv "Java files" "$JAVA_COUNT"
  kv "Res folders" "$RES_COUNT"
  kv "Asset folders" "$ASSET_COUNT"
  kv "Libs" "$JAR_COUNT jar · $AAR_COUNT aar · $SO_COUNT .so"
  [ -n "$GRADLE_APPID$GRADLE_NAMESPACE" ] && kv "Gradle hints" "id=${GRADLE_APPID:-$GRADLE_NAMESPACE} min=${GRADLE_MIN:-?} target=${GRADLE_TARGET:-?}"
  [ "${KT_COUNT:-0}" -gt 0 ] && warn "$KT_COUNT Kotlin file(s) found - Kotlin is not compiled (Java only)"
  [ "${AIDL_COUNT:-0}" -gt 0 ] && warn "$AIDL_COUNT .aidl file(s) found - AIDL is not compiled"
  [ "${NATIVE_SRC:-0}" -gt 0 ] && warn "C/C++ sources found - native code is not built (prebuilt .so only)"
  [ "${DUP_COUNT:-0}" -gt 0 ] && info "Auto-fix: ignored $DUP_COUNT duplicate class file(s) (flavors/copies)"
  [ "${EXCL_COUNT:-0}" -gt 0 ] && info "Auto-fix: ignored $EXCL_COUNT other app module(s)"
  [ "${APKTOOL:-0}" = 1 ] && warn "apktool.yml found - this looks like a decoded APK (smali), not Java source"
  if [ -z "$MANIFEST" ]; then
    if [ -n "$GUESS_ACTIVITY" ]; then
      warn "No AndroidManifest.xml - APKB will generate one for $GUESS_ACTIVITY"
    else
      err "No AndroidManifest.xml and no Activity class found"
    fi
  fi
}
