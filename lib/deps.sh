#!/usr/bin/env bash
# APKB :: configuration, package auto-install, android.jar handling

CFG="$APKB_HOME/config"
ANDROID_JAR=""; JAR_API=""; OUT_DIR=""; JAVA_COMPILER="auto"; RES_ENGINE="auto"
DO_ZIPALIGN=1; KEEP_WORK=0; VERBOSE=0

default_out_dir() {
  local d
  for d in /storage/emulated/0 "$HOME/storage/shared" /sdcard; do
    if [ -d "$d" ] && [ -w "$d" ]; then echo "$d/apks"; return; fi
  done
  echo "$HOME/apks"
}

cfg_load() {
  [ -f "$CFG" ] && . "$CFG"
  [ -z "$OUT_DIR" ] && OUT_DIR="$(default_out_dir)"
  return 0
}

cfg_set() {  # cfg_set KEY VALUE
  local k="$1" v="$2"
  touch "$CFG"
  grep -v "^$k=" "$CFG" > "$CFG.tmp" 2>/dev/null || true
  printf '%s=%q\n' "$k" "$v" >> "$CFG.tmp"
  mv "$CFG.tmp" "$CFG"
  printf -v "$k" '%s' "$v"
}

# ------------------------------------------------------------------ platform
IS_TERMUX=0
if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux/files/usr ]; then IS_TERMUX=1; fi

PM=""
detect_pm() {
  if [ "$IS_TERMUX" = 1 ] && command -v pkg >/dev/null 2>&1; then PM=pkg
  elif command -v apt-get >/dev/null 2>&1; then PM=apt
  elif command -v pacman >/dev/null 2>&1; then PM=pacman
  elif command -v dnf >/dev/null 2>&1; then PM=dnf
  elif command -v apk >/dev/null 2>&1; then PM=apk
  else PM=""; fi
}

SUDO=""
if [ "$(id -u 2>/dev/null)" != "0" ] && command -v sudo >/dev/null 2>&1 && [ "$IS_TERMUX" = 0 ]; then SUDO="sudo"; fi

# package names per tool for each package manager (space separated candidates)
pkgs_for() {  # pkgs_for tool
  case "$PM:$1" in
    pkg:java)     echo "openjdk-17" ;;
    pkg:aapt2)    echo "aapt2" ;;
    pkg:aapt)     echo "aapt" ;;
    pkg:d8)       echo "d8" ;;
    pkg:dx)       echo "dx" ;;
    pkg:ecj)      echo "ecj" ;;
    pkg:zip)      echo "zip" ;;
    pkg:unzip)    echo "unzip" ;;
    pkg:zipalign) echo "zipalign" ;;
    pkg:python3)  echo "python" ;;
    pkg:pillow)   echo "python-pillow" ;;
    pkg:apktool)  echo "apktool" ;;
    apt:java)     echo "default-jdk-headless openjdk-17-jdk-headless" ;;
    apt:aapt2)    echo "aapt2 google-android-build-tools-installer" ;;
    apt:aapt)     echo "aapt" ;;
    apt:d8)       echo "d8" ;;
    apt:dx)       echo "dalvik-exchange dx" ;;
    apt:ecj)      echo "ecj" ;;
    apt:zip)      echo "zip" ;;
    apt:unzip)    echo "unzip" ;;
    apt:zipalign) echo "zipalign" ;;
    apt:python3)  echo "python3" ;;
    apt:pillow)   echo "python3-pil" ;;
    apt:apktool)  echo "apktool" ;;
    pacman:java)  echo "jdk17-openjdk" ;;
    pacman:zip|pacman:unzip|pacman:ecj) echo "$1" ;;
    pacman:python3) echo "python" ;;
    pacman:aapt|pacman:aapt2|pacman:zipalign|pacman:d8|pacman:dx) echo "android-sdk-build-tools" ;;
    dnf:java)     echo "java-17-openjdk-devel" ;;
    dnf:zip|dnf:unzip) echo "$1" ;;
    dnf:python3)  echo "python3" ;;
    dnf:aapt|dnf:aapt2|dnf:zipalign) echo "aapt zipalign" ;;
    apk:java)     echo "openjdk17-jdk" ;;
    apk:zip|apk:unzip) echo "$1" ;;
    apk:python3)  echo "python3" ;;
    apk:aapt|apk:aapt2|apk:zipalign) echo "aapt zipalign" ;;
    *) echo "" ;;
  esac
}

pm_install() {  # pm_install pkg...
  case "$PM" in
    pkg)    pkg install -y "$@" ;;
    apt)    $SUDO apt-get install -y "$@" ;;
    pacman) $SUDO pacman -S --noconfirm --needed "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    apk)    $SUDO apk add "$@" ;;
    *)      return 1 ;;
  esac
}

PM_UPDATED=0
pm_update_once() {
  [ "$PM_UPDATED" = 1 ] && return 0
  PM_UPDATED=1
  case "$PM" in
    pkg) pkg update -y >/dev/null 2>&1 || true ;;
    apt) $SUDO apt-get update -y >/dev/null 2>&1 || true ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------- tool resolution
AAPT2=""; AAPT=""; D8=""; DX=""; ECJ=""; JAVAC=""; JAVA=""; ZIPALIGN=""; APKTOOL=""
resolve_tools() {
  AAPT2="$(command -v aapt2 2>/dev/null || true)"
  AAPT="$(command -v aapt 2>/dev/null || true)"
  D8="$(command -v d8 2>/dev/null || true)"
  DX="$(command -v dx 2>/dev/null || true)"
  ECJ="$(command -v ecj 2>/dev/null || true)"
  JAVAC="$(command -v javac 2>/dev/null || true)"
  JAVA="$(command -v java 2>/dev/null || true)"
  ZIPALIGN="$(command -v zipalign 2>/dev/null || true)"
  APKTOOL="$(command -v apktool 2>/dev/null || true)"
}

install_tool() {  # install_tool tool  -> tries each candidate package
  local tool="$1" p ok=1
  for p in $(pkgs_for "$tool"); do
    if pm_install "$p" >>"${LOG:-/dev/null}" 2>&1; then ok=0; break; fi
  done
  return $ok
}

# Installs whatever is missing. Required: java, (aapt2|aapt), (d8|dx), (ecj|javac), zip, unzip, python3
ensure_deps() {
  detect_pm
  resolve_tools
  local missing=()
  have python3 || missing+=(python3)
  have zip     || missing+=(zip)
  have unzip   || missing+=(unzip)
  have java    || missing+=(java)
  [ -n "$AAPT2" ] || [ -n "$AAPT" ] || missing+=(aapt2)
  [ -n "$D8" ] || [ -n "$DX" ] || missing+=(d8)
  [ -n "$ECJ" ] || [ -n "$JAVAC" ] || missing+=(ecj)
  # nice to have
  [ -n "$ZIPALIGN" ] || missing+=(zipalign)
  [ -n "$AAPT2" ] || [ -z "$AAPT" ] || true

  if [ ${#missing[@]} -gt 0 ]; then
    if [ -z "$PM" ]; then
      warn "No supported package manager found. Install manually: ${missing[*]}"
      return 1
    fi
    section "AUTO-INSTALL"
    info "Missing tools: ${missing[*]}"
    pm_update_once
    local t
    for t in "${missing[@]}"; do
      if install_tool "$t"; then ok "installed $t"; else warn "could not install $t"; fi
    done
    # Termux: ecj/dx/aapt are useful fallbacks even when aapt2/d8 exist
    resolve_tools
    [ -z "$AAPT" ] && [ "$IS_TERMUX" = 1 ] && install_tool aapt >/dev/null 2>&1
    resolve_tools
  fi

  # hard requirements
  local fatal=0
  have python3 || { err "python3 is required"; fatal=1; }
  have zip     || { err "zip is required"; fatal=1; }
  have unzip   || { err "unzip is required"; fatal=1; }
  have java    || { err "java (JDK) is required"; fatal=1; }
  [ -n "$AAPT2$AAPT" ] || { err "aapt2 (or aapt) is required"; fatal=1; }
  [ -n "$D8$DX" ] || { err "d8 (or dx) is required"; fatal=1; }
  [ -n "$ECJ$JAVAC" ] || { err "ecj (or javac) is required"; fatal=1; }
  return $fatal
}

# ------------------------------------------------------------------ android.jar
validate_jar() {
  [ -f "$1" ] || return 1
  unzip -Z1 "$1" 2>/dev/null | grep -q '^android/app/Activity.class$'
}

detect_jar_api() {  # sets JAR_API (approximate) by probing known classes
  local idx; idx="$(mktemp)"
  unzip -Z1 "$ANDROID_JAR" 2>/dev/null > "$idx"
  local api=0 probe
  for probe in \
    "35:android/window/SystemOverlayRequest?" \
    "34:android/credentials/CredentialManager.class" \
    "33:android/window/OnBackInvokedCallback.class" \
    "32:android/app/GameManager.class?" \
    "31:android/window/SplashScreen.class" \
    "30:android/view/WindowInsetsController.class" \
    "29:android/media/AudioPlaybackCaptureConfiguration.class" \
    "28:android/hardware/biometrics/BiometricPrompt.class" \
    "27:android/os/SharedMemory.class" \
    "26:android/app/NotificationChannel.class" \
    "25:android/content/pm/ShortcutManager.class" \
    "24:android/os/LocaleList.class" \
    "23:android/app/assist/AssistContent.class" \
    "21:android/app/job/JobScheduler.class" \
    "19:android/print/PrintManager.class" ; do
    local v="${probe%%:*}" c="${probe#*:}"
    case "$c" in *\?) continue ;; esac
    if grep -qx "$c" "$idx"; then api="$v"; break; fi
  done
  rm -f "$idx"
  JAR_API="$api"
  [ "$api" = 0 ] && JAR_API=""
  return 0
}

jar_is_new_enough() { [ -z "$JAR_API" ] || [ "$JAR_API" -ge "$1" ]; }

ensure_android_jar() {
  while true; do
    if [ -n "$ANDROID_JAR" ] && validate_jar "$ANDROID_JAR"; then
      detect_jar_api
      return 0
    fi
    section "ANDROID.JAR"
    [ -n "$ANDROID_JAR" ] && warn "Saved android.jar is missing or invalid: $ANDROID_JAR"
    info "APKB needs a ready android.jar (from an Android SDK platform)."
    dim  "Give the file path, or a folder that contains it."
    local p
    ask_path p "Path to android.jar"
    [ -z "$p" ] && { err "Path is required"; ask_yn "Try again?" Y || return 1; continue; }
    if [ -d "$p" ]; then
      local found
      found="$(find "$p" -maxdepth 5 -name android.jar 2>/dev/null | sort -V | tail -n1)"
      [ -n "$found" ] && p="$found"
    fi
    if validate_jar "$p"; then
      cfg_set ANDROID_JAR "$(readlink -f "$p" 2>/dev/null || echo "$p")"
      detect_jar_api
      ok "android.jar accepted (API ${JAR_API:-unknown})"
    else
      err "That is not a valid android.jar (android/app/Activity.class not found)"
      ask_yn "Try again?" Y || return 1
    fi
  done
}

# ------------------------------------------------------------------ output dir
ensure_out_dir() {
  if [ -d /storage/emulated/0 ] && [ ! -w /storage/emulated/0 ] && have termux-setup-storage; then
    warn "Storage permission missing. Opening Termux storage setup..."
    termux-setup-storage >/dev/null 2>&1 || true
    sleep 3
    OUT_DIR="$(default_out_dir)"
  fi
  mkdir -p "$OUT_DIR" 2>/dev/null || { warn "Cannot create $OUT_DIR - using $HOME/apks"; OUT_DIR="$HOME/apks"; mkdir -p "$OUT_DIR"; }
}

java_heap_opts() {
  # pick a sane -Xmx from available memory so d8/ecj do not get killed
  [ -n "${JAVA_TOOL_OPTIONS:-}" ] && return 0
  local kb mb
  kb="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
  [ -z "$kb" ] && return 0
  mb=$((kb/1024*6/10))
  [ "$mb" -gt 2048 ] && mb=2048
  [ "$mb" -lt 384 ] && mb=384
  export JAVA_TOOL_OPTIONS="-Xmx${mb}m"
}
