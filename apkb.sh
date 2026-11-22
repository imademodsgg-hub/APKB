#!/usr/bin/env bash
# ╔══════════════════════════════════════════════╗
# ║  APKB - Android Package Kit Builder (Lab)    ║
# ║  raw Java -> APK · no Gradle · no Flutter    ║
# ╚══════════════════════════════════════════════╝
APKB_VERSION="2.0.0"
APKB_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
APKB_ROOT="$(cd "$(dirname "$APKB_SELF")" && pwd)"
export APKB_ROOT APKB_VERSION
APKB_HOME="${APKB_HOME:-$HOME/.apkb}"
mkdir -p "$APKB_HOME/work" "$APKB_HOME/logs"
for f in ui deps scan build html2apk tools broadcast; do
  # shellcheck disable=SC1090
  source "$APKB_ROOT/lib/$f.sh" || { echo "APKB: cannot load lib/$f.sh"; exit 1; }
done
main "$@"
