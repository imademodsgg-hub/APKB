#!/usr/bin/env bash
# APKB :: terminal UI toolkit

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[38;5;203m'; C_GRN=$'\033[38;5;84m'; C_YEL=$'\033[38;5;221m'
  C_BLU=$'\033[38;5;75m';  C_PUR=$'\033[38;5;141m'; C_CYN=$'\033[38;5;87m'
  C_ORG=$'\033[38;5;215m'
else
  C_RST=''; C_B=''; C_DIM=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_PUR=''; C_CYN=''; C_ORG=''
fi
UI_W=46

hr()   { printf '%s' "$C_DIM"; printf '─%.0s' $(seq 1 "$UI_W"); printf '%s\n' "$C_RST"; }
hr2()  { printf '%s' "$C_CYN"; printf '═%.0s' $(seq 1 "$UI_W"); printf '%s\n' "$C_RST"; }
info() { printf '  %s•%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '  %s▲%s %s\n' "$C_YEL" "$C_RST" "$*"; }
err()  { printf '  %s✘%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
dim()  { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RST"; }
kv()   { printf '  %s%-14s%s %s\n' "$C_DIM" "$1" "$C_RST" "$2"; }

section() {  # section "TITLE"
  printf '\n%s┌─[%s %s %s]%s\n' "$C_CYN" "$C_B" "$1" "$C_RST$C_CYN" "$C_RST"
}

banner() {
  clear 2>/dev/null || true
  printf '%s' "$C_CYN"
  printf '╔════════════════════════════════════════════╗\n'
  printf '║%s  ▄▀█ █▀█ █▄▀ █▄▄   ANDROID PACKAGE KIT     %s║\n' "$C_B$C_GRN" "$C_RST$C_CYN"
  printf '║%s  █▀█ █▀▀ █ █ █▄█   BUILDER  ·  LAB EDITION %s║\n' "$C_B$C_GRN" "$C_RST$C_CYN"
  printf '╠════════════════════════════════════════════╣\n'
  printf '║%s  ⚗ raw Java → APK · no Gradle · no Flutter %s║\n' "$C_DIM" "$C_RST$C_CYN"
  printf '╚════════════════════════════════════════════╝%s\n' "$C_RST"
  lab_status
}

# one-line instrument panel
lab_status() {
  local t
  t="$(printf '  %sREACTOR%s ' "$C_DIM" "$C_RST")"
  for x in aapt2:"${AAPT2:-}" d8:"${D8:-${DX:-}}" ecj:"${ECJ:-${JAVAC:-}}" zip:"${ZIPALIGN:-}"; do
    local n="${x%%:*}" p="${x#*:}"
    if [ -n "$p" ]; then t+="${C_GRN}●${C_RST}${n} "; else t+="${C_RED}○${C_RST}${n} "; fi
  done
  printf '%s\n' "$t"
  if [ -n "${ANDROID_JAR:-}" ]; then
    printf '  %sandroid.jar%s API %s%s%s\n' "$C_DIM" "$C_RST" "$C_GRN" "${JAR_API:-?}" "$C_RST"
  else
    printf '  %sandroid.jar%s %snot set%s\n' "$C_DIM" "$C_RST" "$C_YEL" "$C_RST"
  fi
  hr
}

emit() { [ "${APKB_JOB:-0}" = 1 ] && printf '@@APKB %s=%s\n' "$1" "$2"; return 0; }

pause() { [ "${APKB_JOB:-0}" = 1 ] && return 0; printf '\n  %s↵ Press Enter to continue%s' "$C_DIM" "$C_RST"; read -r _; }

clean_path() {  # strip quotes/spaces, expand ~ and file://
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
  p="${p#\'}"; p="${p%\'}"; p="${p#\"}"; p="${p%\"}"
  p="${p#file://}"
  case "$p" in "~"|"~/"*) p="$HOME${p#\~}" ;; esac
  printf '%s' "$p"
}

# ask VAR "Prompt" [default]
ask() {
  local __v="$1" __p="$2" __d="${3:-}" __a
  if [ -n "$__d" ]; then
    printf '  %s?%s %s %s[%s]%s\n' "$C_PUR" "$C_RST" "$__p" "$C_DIM" "$__d" "$C_RST"
  else
    printf '  %s?%s %s\n' "$C_PUR" "$C_RST" "$__p"
  fi
  IFS= read -r -e -p "  ${C_CYN}➜${C_RST} " __a || __a=""
  [ -z "$__a" ] && __a="$__d"
  printf -v "$__v" '%s' "$__a"
}

ask_path() {  # ask_path VAR "Prompt" [default]
  local __tmp
  ask __tmp "$2" "${3:-}"
  printf -v "$1" '%s' "$(clean_path "$__tmp")"
}

# ask_yn "Prompt" Y|N  -> returns 0 for yes
ask_yn() {
  local p="$1" d="${2:-Y}" a hint
  [ "$d" = "Y" ] && hint="Y/n" || hint="y/N"
  printf '  %s?%s %s %s[%s]%s ' "$C_PUR" "$C_RST" "$p" "$C_DIM" "$hint" "$C_RST"
  IFS= read -r a || a=""
  [ -z "$a" ] && a="$d"
  case "$a" in y|Y|yes|YES|1) return 0 ;; *) return 1 ;; esac
}

# menu_pick "Title" "opt1" "opt2" ... -> sets PICK (1-based); returns 1 on 0/back
menu_pick() {
  local title="$1"; shift
  local i=1 o
  [ -n "$title" ] && printf '\n  %s%s%s\n' "$C_B" "$title" "$C_RST"
  for o in "$@"; do
    printf '   %s[%d]%s %s\n' "$C_CYN" "$i" "$C_RST" "$o"; i=$((i+1))
  done
  printf '   %s[0]%s Back\n' "$C_DIM" "$C_RST"
  local a
  while true; do
    IFS= read -r -p "  ${C_CYN}➜${C_RST} " a || return 1
    if [ "$a" = "0" ] || [ "$a" = "q" ]; then PICK=0; return 1; fi
    if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le $# ]; then PICK="$a"; return 0; fi
    warn "Choose a number from the list"
  done
}

# pick_val "Title" default "label1:value1" "label2:value2" ...  -> echoes value
pick_val() {
  local title="$1" def="$2"; shift 2
  local labels=() vals=() item
  for item in "$@"; do labels+=("${item%%:*}"); vals+=("${item#*:}"); done
  local i=1
  printf '\n  %s%s%s\n' "$C_B" "$title" "$C_RST" >&2
  for item in "${labels[@]}"; do
    local mark=" "; [ "${vals[$((i-1))]}" = "$def" ] && mark="${C_GRN}*${C_RST}"
    printf '   %s[%d]%s %s %s\n' "$C_CYN" "$i" "$C_RST" "$item" "$mark" >&2; i=$((i+1))
  done
  local a
  while true; do
    IFS= read -r -p "  ${C_CYN}➜${C_RST} " a >&2 || a=""
    [ -z "$a" ] && { printf '%s' "$def"; return 0; }
    if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#vals[@]} ]; then
      printf '%s' "${vals[$((a-1))]}"; return 0
    fi
    warn "Choose a number from the list (Enter = default)" >&2
  done
}

# run_step "Label" cmd args...   (external commands; output goes to $STEP_OUT and $LOG)
STEP_N=0
run_step() {
  local label="$1"; shift
  local start=$SECONDS
  STEP_N=$((STEP_N+1))
  STEP_OUT="${WORK:-/tmp}/.step_${STEP_N}.log"
  : > "$STEP_OUT"
  emit step "$label"
  ( "$@" >"$STEP_OUT" 2>&1 ) &
  local pid=$! i=0
  local fr=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s %s(%ss)%s\033[K' "$C_CYN" "${fr[i%10]}" "$C_RST" "$label" "$C_DIM" "$((SECONDS-start))" "$C_RST"
      i=$((i+1)); sleep 0.1
    done
  fi
  wait "$pid"; local rc=$?
  local el=$((SECONDS-start))
  [ -t 1 ] && printf '\r\033[K'
  if [ -n "${LOG:-}" ]; then
    { printf '\n=== %s (rc=%s, %ss) ===\n$ %s\n' "$label" "$rc" "$el" "$*"; cat "$STEP_OUT"; } >> "$LOG"
  fi
  if [ $rc -eq 0 ]; then
    printf '  %s✔%s %s %s(%ss)%s\n' "$C_GRN" "$C_RST" "$label" "$C_DIM" "$el" "$C_RST"
    [ "${VERBOSE:-0}" = "1" ] && sed 's/^/      /' "$STEP_OUT" | head -40
  else
    printf '  %s✘%s %s %s(%ss)%s\n' "$C_RED" "$C_RST" "$label" "$C_DIM" "$el" "$C_RST"
  fi
  return $rc
}

show_tail() {  # show_tail file [lines]
  local f="$1" n="${2:-14}"
  [ -s "$f" ] || return 0
  printf '%s' "$C_DIM"
  grep -v -E '^Picked up|^NOTE:|^$' "$f" | tail -n "$n" | cut -c1-110 | sed 's/^/      │ /'
  printf '%s' "$C_RST"
}

human_size() {  # bytes -> human
  awk -v b="$1" 'BEGIN{ s="B KB MB GB"; split(s,u," "); i=1; while (b>=1024 && i<4){b/=1024;i++} printf (i==1? "%d %s":"%.1f %s"), b, u[i] }'
}

now_ts() { date +%Y%m%d-%H%M%S; }
