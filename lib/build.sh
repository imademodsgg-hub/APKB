#!/usr/bin/env bash
# APKB :: build pipeline (aapt2/aapt -> ecj/javac -> d8/dx -> zip -> zipalign -> verify)

OPT_TYPE=release; OPT_MIN=""; OPT_TARGET=""; OPT_VNAME=""; OPT_VCODE=""; OPT_PKG=""; OPT_NAME=""
OPT_LEVEL=auto; OPT_ABI=all; OPT_OUTNAME=""
BUILD_APK=""; BUILD_PKG=""; BUILD_LABEL=""

reset_opts() {
  OPT_TYPE=release; OPT_MIN=""; OPT_TARGET=""; OPT_VNAME=""; OPT_VCODE=""; OPT_PKG=""; OPT_NAME=""
  OPT_LEVEL=auto; OPT_ABI=all; OPT_OUTNAME=""
}

xml_res_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g" -e 's/"/\\"/g' -e 's/&/\&amp;/g' -e 's/</\&lt;/g'
}

is_num() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

save_fail_log() {  # save_fail_log "reason" - every failed build leaves a log file behind
  local dir="${OUT_DIR:-$HOME/apks}/logs" name f
  name="$(basename "${WORK:-build}")"
  mkdir -p "$dir" 2>/dev/null || { dir="$HOME/apks/logs"; mkdir -p "$dir"; }
  f="$dir/${name}-FAILED.log"
  { echo "APKB $APKB_VERSION - FAILED BUILD REPORT"; echo "Reason : ${1:-unknown}"; echo "Project: ${PROJECT_NAME:-?}"; date; echo "------------------------------"; cat "$LOG" 2>/dev/null; } > "$f" 2>/dev/null
  if [ -s "$f" ]; then info "Failure log saved: $f"; emit failed_log "$f"; emit failed_reason "${1:-unknown}"; fi
}

build_fail() {
  printf '\n%s' "$C_RED"
  printf '  ╔══════════════════════════════════════╗\n'
  printf '  ║            BUILD FAILED              ║\n'
  printf '  ╚══════════════════════════════════════╝%s\n' "$C_RST"
  [ -n "${1:-}" ] && err "$1"
  info "Full log: $LOG"
  mkdir -p "$APKB_HOME/logs"; cp "$LOG" "$APKB_HOME/logs/$(basename "$WORK").log" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "${PROJECT_NAME:-?}" "FAILED" "-" >> "$APKB_HOME/history.log"
  save_fail_log "${1:-build failed}"
  return 1
}

# ------------------------------------------------------------------ main entry
build_core() {
  local B="$WORK/b"
  mkdir -p "$B/classes" "$B/gen" "$B/dex" "$B/stage" "$B/res_auto"
  local T0=$SECONDS
  java_heap_opts
  : > "$LOG"
  { echo "APKB $APKB_VERSION build log"; date; echo "project: $PROJECT_ROOT"; echo "android.jar: $ANDROID_JAR (API ${JAR_API:-?})"; } >> "$LOG"

  # ---- engines --------------------------------------------------------------
  local RES_ENG="$RES_ENGINE"
  [ "$RES_ENG" = auto ] && { [ -n "$AAPT2" ] && RES_ENG=aapt2 || RES_ENG=aapt; }
  [ "$RES_ENG" = aapt2 ] && [ -z "$AAPT2" ] && RES_ENG=aapt
  [ "$RES_ENG" = aapt ] && [ -z "$AAPT" ] && RES_ENG=aapt2
  local COMPILER="$JAVA_COMPILER"
  [ "$COMPILER" = auto ] && { [ -n "$ECJ" ] && COMPILER=ecj || COMPILER=javac; }
  [ "$COMPILER" = ecj ] && [ -z "$ECJ" ] && COMPILER=javac
  [ "$COMPILER" = javac ] && [ -z "$JAVAC" ] && COMPILER=ecj

  section "BUILD · ${PROJECT_NAME}"
  kv "Resources" "$RES_ENG"; kv "Compiler" "$COMPILER"; kv "Type" "$OPT_TYPE"

  # ---- 1. libraries (aar / jar / native) ---------------------------------------
  local JARS=() AAR_RES=() AAR_ASSETS=() EXTRA_PKGS=() AAR_PERMS=() SOS=() line
  while IFS= read -r line; do [ -n "$line" ] && JARS+=("$line"); done < "$S/jar.list"
  local n=0 aar d j abi f
  while IFS= read -r aar; do
    [ -z "$aar" ] && continue
    n=$((n+1)); d="$B/aar/$n"; mkdir -p "$d"
    unzip -q -o "$aar" -d "$d" >>"$LOG" 2>&1 || { warn "Could not open $(basename "$aar")"; continue; }
    [ -f "$d/classes.jar" ] && JARS+=("$d/classes.jar")
    for j in "$d"/libs/*.jar; do [ -f "$j" ] && JARS+=("$j"); done
    [ -d "$d/res" ] && [ -n "$(ls -A "$d/res" 2>/dev/null)" ] && AAR_RES+=("$d/res")
    [ -d "$d/assets" ] && AAR_ASSETS+=("$d/assets")
    if [ -f "$d/AndroidManifest.xml" ]; then
      local ap; ap="$(grep -o 'package="[^"]*"' "$d/AndroidManifest.xml" | head -n1 | cut -d'"' -f2)"
      [ -n "$ap" ] && EXTRA_PKGS+=("$ap")
      while IFS= read -r f; do AAR_PERMS+=("$f"); done < <(grep -o 'uses-permission[^>]*android:name="[^"]*"' "$d/AndroidManifest.xml" | grep -o 'android:name="[^"]*"' | cut -d'"' -f2)
    fi
    if [ -d "$d/jni" ]; then
      for abi in "$d"/jni/*/; do
        [ -d "$abi" ] || continue
        for f in "$abi"*.so; do [ -f "$f" ] && SOS+=("$(basename "$abi")"$'\t'"$f"); done
      done
    fi
  done < "$S/aar.list"
  while IFS= read -r line; do [ -n "$line" ] && SOS+=("$line"); done < "$S/so.list"
  [ $n -gt 0 ] && info "Unpacked $n .aar librar$([ $n = 1 ] && echo y || echo ies)"

  # ---- 2. manifest ---------------------------------------------------------------
  local MF="$B/AndroidManifest.xml" MF_SRC="$MANIFEST"
  if [ -z "$MF_SRC" ]; then
    if [ -z "$GUESS_ACTIVITY" ]; then build_fail "No AndroidManifest.xml and no Activity found"; return 1; fi
    local gp="${GUESS_PACKAGE:-com.apkb.app}"
    py manifest.py gen "$B/generated_manifest.xml" "$gp" "$GUESS_ACTIVITY" "$PROJECT_NAME"
    MF_SRC="$B/generated_manifest.xml"
    warn "Generated a manifest (launcher: $GUESS_ACTIVITY)"
  fi
  declare -A MI=()
  local COMPS=() k v
  while IFS=$'\t' read -r k v; do
    [ -z "$k" ] && continue
    case "$k" in activity|service|receiver|provider|permission) COMPS+=("$k:$v") ;; *) MI[$k]="$v" ;; esac
  done < <(py manifest.py info "$MF_SRC" "${GRADLE_NAMESPACE:-$GUESS_PACKAGE}")
  if [ -n "${MI[error]:-}" ]; then build_fail "Manifest problem: ${MI[error]}"; return 1; fi

  local P0="${MI[package]}"
  [ -z "$P0" ] && P0="${GRADLE_NAMESPACE:-${GRADLE_APPID:-$GUESS_PACKAGE}}"
  [ -z "$P0" ] && P0="com.apkb.app"
  local PKG_FINAL="$P0"
  [ -z "${MI[package]}" ] && [ -n "${GRADLE_APPID:-}" ] && PKG_FINAL="$GRADLE_APPID"
  [ -n "$OPT_PKG" ] && PKG_FINAL="$OPT_PKG"

  local MIN="${OPT_MIN:-${MI[minSdk]:-${GRADLE_MIN:-21}}}"
  is_num "$MIN" || MIN=21
  local TARGET="${OPT_TARGET:-${MI[targetSdk]:-${GRADLE_TARGET:-}}}"
  if ! is_num "$TARGET"; then
    TARGET="${JAR_API:-34}"; [ "$TARGET" -gt 34 ] && TARGET=34
  fi
  [ "$TARGET" -lt "$MIN" ] && TARGET="$MIN"

  local fa=(--package "$P0" --min "$MIN" --target "$TARGET" --default-version)
  [ "$TARGET" -ge 31 ] && fa+=(--exported)
  [ -n "$JAR_API" ] && fa+=(--api "$JAR_API")
  [ -n "$OPT_VCODE" ] && fa+=(--version-code "$OPT_VCODE")
  [ -z "$OPT_VCODE" ] && [ -n "${GRADLE_VCODE:-}" ] && [ -z "${MI[versionCode]}" ] && fa+=(--version-code "$GRADLE_VCODE")
  [ -n "$OPT_VNAME" ] && fa+=(--version-name "$OPT_VNAME")
  [ -z "$OPT_VNAME" ] && [ -n "${GRADLE_VNAME:-}" ] && [ -z "${MI[versionName]}" ] && fa+=(--version-name "$GRADLE_VNAME")
  [ "$OPT_TYPE" = debug ] && fa+=(--debuggable 1)
  local p
  for p in "${AAR_PERMS[@]}"; do fa+=(--perm "$p"); done
  if [ -n "$OPT_NAME" ]; then
    mkdir -p "$B/res_auto/values"
    printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="apkb_app_label">%s</string>\n</resources>\n' \
      "$(xml_res_escape "$OPT_NAME")" > "$B/res_auto/values/apkb_label.xml"
    fa+=(--label "@string/apkb_app_label")
  fi
  if ! py manifest.py fix "$MF_SRC" "$MF" "${fa[@]}" >>"$LOG" 2>&1; then
    build_fail "Could not process the manifest (invalid XML?)"; return 1
  fi
  ok "Manifest ready  ${C_DIM}pkg=$PKG_FINAL min=$MIN target=$TARGET${C_RST}"
  [ "$PKG_FINAL" != "$P0" ] && info "Package id renamed: $P0 → $PKG_FINAL"

  # ---- 3. resources --------------------------------------------------------------
  local RES_DIRS=("${AAR_RES[@]}") ASSET_DIRS=() RZ=()
  while IFS= read -r line; do [ -n "$line" ] && RES_DIRS+=("$line"); done < "$S/res.list"
  while IFS= read -r line; do [ -n "$line" ] && ASSET_DIRS+=("$line"); done < "$S/assets.list"
  ASSET_DIRS+=("${AAR_ASSETS[@]}")

  local linked=0
  if [ "$RES_ENG" = aapt2 ]; then
    local i=0 z
    for d in "${RES_DIRS[@]}"; do
      i=$((i+1)); z="$B/res_$i.zip"
      if ! run_step "Compile resources $i/${#RES_DIRS[@]}" "$AAPT2" compile --dir "$d" -o "$z"; then
        if ! run_step "Retry in --legacy mode" "$AAPT2" compile --legacy --dir "$d" -o "$z"; then
          show_tail "$STEP_OUT" 16
          if [ -n "$AAPT" ]; then warn "aapt2 rejected the resources - falling back to classic aapt"; RES_ENG=aapt; break; fi
          build_fail "Resource compilation failed in ${d#$PROJECT_ROOT/}"; return 1
        fi
      fi
      RZ+=("$z")
    done
  fi
  if [ "$RES_ENG" = aapt2 ]; then
    link_aapt2 && linked=1
    if [ $linked = 0 ] && [ -n "$AAPT" ]; then warn "aapt2 link failed - trying classic aapt"; RES_ENG=aapt; fi
  fi
  if [ "$RES_ENG" = aapt ] && [ $linked = 0 ]; then link_aapt && linked=1; fi
  [ $linked = 1 ] || { build_fail "Resource linking failed"; return 1; }

  # BuildConfig when sources use it but did not ship one
  if [ -s "$S/java.list" ] && xargs -d '\n' grep -l 'BuildConfig' < "$S/java.list" >/dev/null 2>&1 \
     && ! grep -q '/BuildConfig.java$' "$S/java.list"; then
    local vc="${MI[versionCode]:-${OPT_VCODE:-${GRADLE_VCODE:-1}}}" vn="${MI[versionName]:-${OPT_VNAME:-${GRADLE_VNAME:-1.0}}}" bp
    [ -n "$OPT_VCODE" ] && vc="$OPT_VCODE"; [ -n "$OPT_VNAME" ] && vn="$OPT_VNAME"
    for bp in "$P0" "$PKG_FINAL"; do
      mkdir -p "$B/gen/$(echo "$bp" | tr . /)"
      printf 'package %s;\npublic final class BuildConfig {\n  public static final boolean DEBUG = %s;\n  public static final String APPLICATION_ID = "%s";\n  public static final String BUILD_TYPE = "%s";\n  public static final int VERSION_CODE = %s;\n  public static final String VERSION_NAME = "%s";\n}\n' \
        "$bp" "$([ "$OPT_TYPE" = debug ] && echo true || echo false)" "$PKG_FINAL" "$OPT_TYPE" "$vc" "$vn" \
        > "$B/gen/$(echo "$bp" | tr . /)/BuildConfig.java"
    done
    info "Generated BuildConfig.java"
  fi

  # ---- 4. java -------------------------------------------------------------------
  local HAVE_CODE=0
  compile_java || return 1

  # ---- 5. dex --------------------------------------------------------------------
  if [ "$HAVE_CODE" = 1 ]; then build_dex || return 1; fi

  # ---- 6. package ----------------------------------------------------------------
  local APK="$B/app.apk"
  cp "$B/base.apk" "$APK"
  if ls "$B"/dex/classes*.dex >/dev/null 2>&1; then
    (cd "$B/dex" && zip -q -X "$APK" classes*.dex) >>"$LOG" 2>&1 || { build_fail "Could not add dex to the APK"; return 1; }
  fi
  # java resources that came inside jars
  rm -rf "$B/jres"; mkdir -p "$B/jres"
  for j in "${JARS[@]}"; do unzip -q -o "$j" -x '*.class' 'META-INF/*' -d "$B/jres" >/dev/null 2>&1; done
  if [ -n "$(ls -A "$B/jres" 2>/dev/null)" ]; then (cd "$B/jres" && zip -qr -X "$APK" .) >>"$LOG" 2>&1; fi
  # native libraries (stored uncompressed so zipalign -p can page-align them)
  local nso=0 rec
  for rec in "${SOS[@]}"; do
    abi="${rec%%$'\t'*}"; f="${rec#*$'\t'}"
    if [ "$OPT_ABI" != all ] && [[ ",$OPT_ABI," != *",$abi,"* ]]; then continue; fi
    mkdir -p "$B/stage/lib/$abi"; cp "$f" "$B/stage/lib/$abi/"; nso=$((nso+1))
  done
  if [ $nso -gt 0 ]; then
    (cd "$B/stage" && zip -qr -X -0 "$APK" lib) >>"$LOG" 2>&1 && ok "Added $nso native librar$([ $nso = 1 ] && echo y || echo ies)"
  fi
  # zipalign
  local FINAL="$B/final.apk"
  if [ "$DO_ZIPALIGN" = 1 ] && [ -n "$ZIPALIGN" ]; then
    if ! run_step "Zipalign" "$ZIPALIGN" -f -p 4 "$APK" "$FINAL"; then warn "zipalign failed - using the unaligned APK"; cp "$APK" "$FINAL"; fi
  else
    cp "$APK" "$FINAL"
    [ "$DO_ZIPALIGN" = 1 ] && warn "zipalign not installed - APK left unaligned (still valid)"
  fi

  # ---- 7. verify ---------------------------------------------------------------
  verify_apk "$FINAL" "$B"

  # ---- 8. deliver ------------------------------------------------------------------
  ensure_out_dir
  local base="$OPT_OUTNAME"
  if [ -z "$base" ]; then
    base="$(printf '%s' "${BUILD_LABEL:-}" | tr -cd 'A-Za-z0-9._-')"
    [ -z "$base" ] && base="$(printf '%s' "$PKG_FINAL" | tr -cd 'A-Za-z0-9._-')"
    base="${base}-${V_NAME:-1.0}"
  fi
  base="$(printf '%s' "$base" | tr -cd 'A-Za-z0-9._-')"; [ -z "$base" ] && base="app"
  BUILD_APK="$OUT_DIR/${base}-unsigned.apk"
  cp -f "$FINAL" "$BUILD_APK" || { build_fail "Cannot write to $OUT_DIR"; return 1; }
  BUILD_PKG="$PKG_FINAL"

  local size sha el=$((SECONDS-T0))
  size="$(stat -c %s "$BUILD_APK" 2>/dev/null || wc -c < "$BUILD_APK")"
  sha="$(sha256sum "$BUILD_APK" 2>/dev/null | cut -c1-16)"
  printf '\n%s' "$C_GRN"
  printf '  ╔══════════════════════════════════════╗\n'
  printf '  ║           BUILD COMPLETE  ✔          ║\n'
  printf '  ╚══════════════════════════════════════╝%s\n' "$C_RST"
  kv "APK" "$BUILD_APK"
  kv "Size" "$(human_size "$size")"
  kv "SHA-256" "${sha}…"
  kv "Time" "${el}s"
  emit apk "$BUILD_APK"; emit size "$size"; emit sha "$sha"; emit pkg "$PKG_FINAL"; emit seconds "$el"; emit label "${BUILD_LABEL:-}"; emit version "${V_NAME:-}"
  warn "UNSIGNED - sign it with your signer app before installing"
  mkdir -p "$APKB_HOME/logs"; cp "$LOG" "$APKB_HOME/logs/$(basename "$WORK").log" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "${PROJECT_NAME:-?}" "$BUILD_APK" "$size" >> "$APKB_HOME/history.log"
  [ "$KEEP_WORK" = 1 ] && info "Work folder kept: $WORK" || { rm -rf "$B" "$WORK/src" 2>/dev/null; }
  return 0
}

# ----------------------------------------------------------- aapt2 link + auto-fix
link_aapt2() {
  local attempt a
  for attempt in 1 2 3 4 5 6; do
    local args=(link -o "$B/base.apk" -I "$ANDROID_JAR" --manifest "$MF" --java "$B/gen" --auto-add-overlay)
    for a in "${ASSET_DIRS[@]}"; do args+=(-A "$a"); done
    [ ${#EXTRA_PKGS[@]} -gt 0 ] && args+=(--extra-packages "$(IFS=:; echo "${EXTRA_PKGS[*]}")")
    [ "$PKG_FINAL" != "$P0" ] && args+=(--rename-manifest-package "$PKG_FINAL")
    [ "$OPT_TYPE" = debug ] && args+=(--debug-mode)
    for a in mp3 ogg mp4 webm mkv wav m4a flac wasm; do args+=(-0 "$a"); done
    local zs=() first=1 z
    [ -f "$B/res_auto.zip" ] && zs+=("$B/res_auto.zip")
    zs+=("${RZ[@]}")
    for z in "${zs[@]}"; do
      if [ $first = 1 ]; then args+=("$z"); first=0; else args+=(-R "$z"); fi
    done
    if run_step "Link resources" "$AAPT2" "${args[@]}"; then return 0; fi
    # ---- auto-fix ----
    local fixes rc
    rm -f "$B/drop_attrs.txt"
    fixes="$(py autores.py fix "$STEP_OUT" "$B/res_auto" "${OPT_NAME:-${PROJECT_NAME:-App}}" "$B/drop_attrs.txt")"; rc=$?
    local l
    while IFS= read -r l; do
      case "$l" in
        FIXED*)     ok "Auto-fix: ${l#FIXED }" ;;
        UNFIXABLE*) warn "Cannot auto-create: ${l#UNFIXABLE }" ;;
      esac
    done <<< "$fixes"
    if [ $rc -ne 0 ]; then show_tail "$STEP_OUT" 18; hint_link_error; return 1; fi
    if [ -s "$B/drop_attrs.txt" ]; then
      # shellcheck disable=SC2046
      py manifest.py drop "$MF" $(cat "$B/drop_attrs.txt") >>"$LOG" 2>&1
    fi
    if [ -n "$(find "$B/res_auto" -type f 2>/dev/null | head -n1)" ]; then
      rm -f "$B/res_auto.zip"
      run_step "Compile auto-generated resources" "$AAPT2" compile --dir "$B/res_auto" -o "$B/res_auto.zip" || { show_tail "$STEP_OUT"; return 1; }
    fi
  done
  show_tail "$STEP_OUT" 18
  return 1
}

hint_link_error() {
  if grep -q 'not found' "$STEP_OUT" 2>/dev/null && grep -q "attr/" "$STEP_OUT" 2>/dev/null; then
    warn "Some XML attributes are unknown to this android.jar - try a newer android.jar"
  fi
  if grep -q -E 'duplicate value|already defined' "$STEP_OUT" 2>/dev/null; then
    warn "Duplicate resources between project folders/libraries"
  fi
}

link_aapt() {
  local args=(package -f -m -J "$B/gen" -M "$MF" -I "$ANDROID_JAR" -F "$B/base.apk" --auto-add-overlay)
  local i a
  for ((i=${#RES_DIRS[@]}-1; i>=0; i--)); do args+=(-S "${RES_DIRS[$i]}"); done
  [ -d "$B/res_auto" ] && [ -n "$(find "$B/res_auto" -type f | head -n1)" ] && args+=(-S "$B/res_auto")
  for a in "${ASSET_DIRS[@]}"; do args+=(-A "$a"); done
  [ ${#EXTRA_PKGS[@]} -gt 0 ] && args+=(--extra-packages "$(IFS=:; echo "${EXTRA_PKGS[*]}")")
  [ "$PKG_FINAL" != "$P0" ] && args+=(--rename-manifest-package "$PKG_FINAL")
  [ "$OPT_TYPE" = debug ] && args+=(--debug-mode)
  local attempt
  for attempt in 1 2 3 4; do
    if run_step "Link resources (aapt)" "$AAPT" "${args[@]}"; then return 0; fi
    local fixes rc
    rm -f "$B/drop_attrs.txt"
    fixes="$(py autores.py fix "$STEP_OUT" "$B/res_auto" "${OPT_NAME:-${PROJECT_NAME:-App}}" "$B/drop_attrs.txt")"; rc=$?
    [ $rc -ne 0 ] && break
    printf '%s\n' "$fixes" | grep '^FIXED' | sed 's/^FIXED /  auto-fix: /'
    [ -s "$B/drop_attrs.txt" ] && py manifest.py drop "$MF" $(cat "$B/drop_attrs.txt") >>"$LOG" 2>&1
    case " ${args[*]} " in *" $B/res_auto "*) ;; *) args+=(-S "$B/res_auto") ;; esac
  done
  show_tail "$STEP_OUT" 18
  return 1
}

# --------------------------------------------------------------------- java
try_compile() {  # try_compile <level> <boot|cp>
  local lvl="$1" mode="$2" cp="$ANDROID_JAR" srcs=()
  [ -n "$cpj" ] && cp="$cp:$cpj"
  rm -rf "$B/classes"; mkdir -p "$B/classes"
  mapfile -t srcs < "$jl"
  if [ "$COMPILER" = ecj ]; then
    local a=("$ECJ" "-$lvl" -encoding UTF-8 -proc:none -nowarn -d "$B/classes")
    if [ "$mode" = boot ]; then
      a+=(-bootclasspath "$ANDROID_JAR"); [ -n "$cpj" ] && a+=(-cp "$cpj")
    else
      a+=(-cp "$cp")
    fi
    "${a[@]}" "${srcs[@]}"
  else
    local jl_lvl="$lvl"; [ "$lvl" = "1.8" ] && jl_lvl=8
    local a=("$JAVAC" -source "$jl_lvl" -target "$jl_lvl" -encoding UTF-8 -proc:none -nowarn -Xlint:-options -d "$B/classes")
    if [ "$mode" = boot ]; then a+=(-bootclasspath "$ANDROID_JAR"); [ -n "$cpj" ] && a+=(-cp "$cpj"); else a+=(-cp "$cp"); fi
    "${a[@]}" "${srcs[@]}"
  fi
}

compile_java() {
  local jl="$B/java_all.list" cpj att lvl mode pruned=0 done_ok=0
  cp "$S/java.list" "$jl"
  find "$B/gen" -name '*.java' >> "$jl"
  if [ ! -s "$jl" ]; then
    warn "No Java sources - the APK will contain resources only"
    HAVE_CODE=0
    return 0
  fi
  [ "${KT_COUNT:-0}" -gt 0 ] && warn "Skipping $KT_COUNT Kotlin file(s) (no Kotlin compiler)"
  cpj="$(IFS=:; echo "${JARS[*]}")"
  local attempts=()
  if [ "$OPT_LEVEL" != auto ]; then
    attempts=("$OPT_LEVEL boot" "$OPT_LEVEL cp")
  else
    attempts=("1.8 boot" "1.8 cp" "11 cp" "17 cp")
  fi
  local cands=("$COMPILER") cc ci=0
  [ "$COMPILER" = ecj ] && [ -n "$JAVAC" ] && cands+=(javac)
  [ "$COMPILER" = javac ] && [ -n "$ECJ" ] && cands+=(ecj)
  [ "$JAVA_COMPILER" = auto ] && [ "$COMPILER" = ecj ] && [ -n "$JAVAC" ] && cands=(javac ecj)
  for cc in "${cands[@]}"; do
    COMPILER="$cc"; ci=$((ci+1)); pruned=0
    for att in "${attempts[@]}"; do
      lvl="${att%% *}"; mode="${att#* }"
      [ "$COMPILER" = ecj ] && [ "$lvl" = 17 ] && continue
      while true; do
        if run_step "Compile Java ($COMPILER · -source $lvl · $mode)" try_compile "$lvl" "$mode"; then done_ok=1; break 3; fi
        if [ $pruned -lt 3 ] && py scan.py prune "$jl" "$STEP_OUT" "$MAIN_ROOT" > "$B/pruned.txt" 2>/dev/null; then
          pruned=$((pruned+1))
          warn "Auto-fix: skipped $(wc -l < "$B/pruned.txt") broken file(s) outside the main module"
          continue
        fi
        break
      done
    done
    [ $ci -lt ${#cands[@]} ] && warn "Auto-fix: $cc could not compile - trying the other compiler"
  done
  if [ $done_ok = 0 ]; then
    show_tail "$STEP_OUT" 22
    if grep -q -E 'androidx|android\.support' "$STEP_OUT" 2>/dev/null; then
      warn "AndroidX / support library is used. Put its .jar/.aar files inside the project (e.g. libs/)."
    fi
    if grep -q -E 'R cannot be resolved|symbol: +variable R' "$STEP_OUT" 2>/dev/null; then
      warn "R class problem - check the manifest package and resource errors above"
    fi
    build_fail "Java compilation failed"; return 1
  fi
  if [ -z "$(find "$B/classes" -name '*.class' | head -n1)" ]; then
    warn "Compiler produced no classes"; HAVE_CODE=0; return 0
  fi
  HAVE_CODE=1
  return 0
}

build_dex() {
  rm -rf "$B/dex" "$B/classes.jar"; mkdir -p "$B/dex"
  (cd "$B/classes" && zip -qr "$B/classes.jar" .) >>"$LOG" 2>&1
  local dmin="$MIN" mode=--release tries=0
  [ "$dmin" -lt 21 ] && dmin=21
  [ "$OPT_TYPE" = debug ] && mode=--debug
  while [ $tries -lt 4 ]; do
    tries=$((tries+1))
    local okd=1
    if [ -n "$D8" ]; then
      run_step "Dex (d8)" "$D8" "$mode" --lib "$ANDROID_JAR" --min-api "$dmin" --output "$B/dex" "$B/classes.jar" "${JARS[@]}" && okd=0
    else
      run_step "Dex (dx)" "$DX" --dex --output="$B/dex/classes.dex" "$B/classes.jar" "${JARS[@]}" && okd=0
    fi
    [ $okd = 0 ] && return 0
    local dups; dups="$(py scan.py dupjars "$STEP_OUT")"
    if [ -n "$dups" ]; then
      local nj=() jj dd
      for jj in "${JARS[@]}"; do
        local skip=0
        for dd in $dups; do [ "$jj" = "$dd" ] && skip=1; done
        [ $skip = 0 ] && nj+=("$jj")
      done
      JARS=("${nj[@]}")
      warn "Auto-fix: removed duplicate library jar(s) and retrying"
      continue
    fi
    break
  done
  # last resorts: d8 with minimal flags, then dx
  rm -rf "$B/dex"; mkdir -p "$B/dex"
  if [ -n "$D8" ] && run_step "Dex (d8, minimal flags)" "$D8" --output "$B/dex" "$B/classes.jar" "${JARS[@]}"; then return 0; fi
  if [ -n "$DX" ]; then
    rm -rf "$B/dex"; mkdir -p "$B/dex"
    run_step "Dex (dx fallback)" "$DX" --dex --output="$B/dex/classes.dex" "$B/classes.jar" "${JARS[@]}" && return 0
  fi
  show_tail "$STEP_OUT" 18
  build_fail "Dexing failed"
  return 1
}

# --------------------------------------------------------------------- verify
V_NAME=""
verify_apk() {  # verify_apk apk workdir
  local apk="$1" B="$2" bad=0
  section "VERIFICATION"
  if unzip -tq "$apk" >/dev/null 2>&1; then ok "Archive integrity OK"; else err "Archive is corrupt"; bad=1; fi
  local list; list="$(unzip -Z1 "$apk" 2>/dev/null)"
  grep -qx 'AndroidManifest.xml' <<<"$list" && ok "AndroidManifest.xml present" || { err "AndroidManifest.xml missing"; bad=1; }
  if [ "${HAVE_CODE:-0}" = 1 ]; then
    grep -qx 'classes.dex' <<<"$list" && ok "classes.dex present ($(grep -c '^classes[0-9]*\.dex$' <<<"$list") dex)" || { err "classes.dex missing"; bad=1; }
  fi
  if [ -n "$(find "$S" -name res.list -size +0 2>/dev/null)" ] || [ ${#RES_DIRS[@]} -gt 0 ]; then
    grep -qx 'resources.arsc' <<<"$list" && ok "resources.arsc present" || warn "resources.arsc missing"
  fi
  local badging=""
  if [ -n "$AAPT2" ]; then badging="$("$AAPT2" dump badging "$apk" 2>/dev/null)"; fi
  [ -z "$badging" ] && [ -n "$AAPT" ] && badging="$("$AAPT" dump badging "$apk" 2>/dev/null)"
  local pk vn vc sdk tgt lab act
  if [ -n "$badging" ]; then
    pk="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
    vc="$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
    vn="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
    sdk="$(sed -n "s/^sdkVersion:'\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
    tgt="$(sed -n "s/^targetSdkVersion:'\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
    lab="$(sed -n "s/^application-label:'\(.*\)'$/\1/p" <<<"$badging" | head -n1)"
    act="$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
    ok "Parsed by Android tools: $pk  v${vn:-?} (${vc:-?})"
    kv "SDK" "min ${sdk:-?} · target ${tgt:-?}"
    [ -n "$lab" ] && kv "Label" "$lab"
    [ -n "$act" ] && ok "Launcher activity: $act" || warn "No launcher activity - the app will not show an icon"
    BUILD_LABEL="$lab"; V_NAME="$vn"
    local np; np="$(grep -c "^uses-permission" <<<"$badging")"
    [ "$np" -gt 0 ] && kv "Permissions" "$np"
    local nc; nc="$(sed -n "s/^native-code: //p" <<<"$badging" | head -n1)"
    [ -n "$nc" ] && kv "Native ABIs" "$nc"
    [ -n "$tgt" ] && [ "$tgt" -lt 24 ] 2>/dev/null && warn "targetSdk $tgt is old - Android 14+ may refuse to install it"
  else
    warn "Could not read badging (aapt dump unavailable)"
  fi
  # every declared component must have a class
  if [ "${HAVE_CODE:-0}" = 1 ]; then
    local idx="$B/class.idx"
    { (cd "$B/classes" && find . -name '*.class' | sed 's|^\./||'); for j in "${JARS[@]}"; do unzip -Z1 "$j" 2>/dev/null | grep '\.class$'; done; } > "$idx"
    local c miss=0 name
    for c in "${COMPS[@]}"; do
      case "$c" in permission:*) continue ;; esac
      name="${c#*:}"; [ -z "$name" ] && continue
      if ! grep -qxF "$(echo "$name" | tr . /).class" "$idx"; then warn "Declared ${c%%:*} has no class: $name"; miss=$((miss+1)); fi
    done
    [ $miss = 0 ] && ok "All declared components have classes"
  fi
  [ $bad = 1 ] && warn "Verification found problems (see above)"
  return 0
}
