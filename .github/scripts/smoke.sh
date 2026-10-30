#!/usr/bin/env bash
# Emulator smoke checklist for the Phase 0 sandbox spike APK.
#
# Runs INSIDE reactivecircus/android-emulator-runner, on a booted
# arm64-v8a API 36 emulator (KVM-accelerated, ARM Linux runner).
# Mirrors the by-hand checklist:
# install -> launch -> wizard (Continue -> Install Alpine Linux) ->
# first-run extraction -> finish (Start) -> observe the auto-created
# userland session.
#
# Honesty rules baked in:
#  * Every step records PASS/FAIL with its evidence in smoke-results.txt.
#  * A shell inside the userland is NOT driven: the app exposes no
#    intent/service/API route into one (SessionService carries only
#    internal EXIT / wakelock-toggle actions, OnboardingActivity is not
#    exported, sessions are created only from the app's own UI). The
#    checklist therefore stops at extraction-verified BY DESIGN and the
#    summary says so in plain words. Nothing is simulated.
#  * All timings here are EMULATOR-ONLY and say nothing about speed on
#    real hardware. The guest is stock Android: Samsung One UI SELinux
#    behaviour and Fold 6 performance remain phone-only questions.

set +e
PKG=io.github.sylirre.terminal
APK=$(ls apk/*.apk 2>/dev/null | head -1)
WORK="$GITHUB_WORKSPACE/smoke-out"
mkdir -p "$WORK"
RESULTS="$WORK/smoke-results.txt"
: > "$RESULTS"

R_INSTALL="NOT RUN" R_LAUNCH="NOT RUN" R_WIZARD="NOT RUN"
R_EXTRACT="NOT RUN" R_SESSION="NOT RUN" AVC_COUNT="unknown"
FAILED=0

say() { echo "$*" | tee -a "$RESULTS"; }
step() { say ""; say "=== $* ==="; }

# --- UI driving helpers ---------------------------------------------------
cat > "$WORK/tap.py" <<'PY'
import sys, re
path, mode, needle = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(1)
for tag in re.findall(r"<node[^>]*>", data):
    if mode == "resid":
        m = re.search(r'resource-id="([^"]*)"', tag)
        if not m or not m.group(1).endswith(":id/" + needle):
            continue
    else:  # text substring
        m = re.search(r'text="([^"]*)"', tag)
        if not m or needle not in m.group(1):
            continue
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
    if b:
        x1, y1, x2, y2 = (int(v) for v in b.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(1)
PY

dump_ui() { # $1 = label
  local i
  for i in 1 2 3; do
    adb shell uiautomator dump /sdcard/wd.xml >/dev/null 2>&1
    adb pull /sdcard/wd.xml "$WORK/ui-$1.xml" >/dev/null 2>&1
    [ -s "$WORK/ui-$1.xml" ] && break
    sleep 2
  done
  cp "$WORK/ui-$1.xml" "$WORK/current.xml" 2>/dev/null
}

tap_by() { # $1 = mode (resid|text), $2 = needle
  local xy
  xy=$(python3 "$WORK/tap.py" "$WORK/current.xml" "$1" "$2" 2>/dev/null)
  if [ -n "$xy" ]; then
    adb shell input tap $xy >/dev/null 2>&1
    say "tapped ($1=$2) at $xy"
    return 0
  fi
  say "tap target NOT FOUND ($1=$2)"
  return 1
}

ui_has() { grep -q "$1" "$WORK/current.xml" 2>/dev/null; }

top_activity() {
  adb shell dumpsys activity activities 2>/dev/null \
    | grep -m1 "topResumedActivity" | sed 's/^ *//'
}

shot() { adb exec-out screencap -p > "$WORK/$1" 2>/dev/null; }

# --- logcat capture starts now --------------------------------------------
adb logcat -c >/dev/null 2>&1
adb logcat -v threadtime > "$WORK/logcat-full.txt" 2>&1 &
LOGPID=$!

step "0. Guest environment (verbatim)"
say "runner: $(uname -a)"
say "guest sdk: $(adb shell getprop ro.build.version.sdk | tr -d '\r')"
say "guest abi: $(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
say "guest avd: $(adb shell getprop ro.boot.qemu.avd_name | tr -d '\r')"
say "apk under test: $APK"
[ -n "$APK" ] && { sha256sum "$APK" || shasum -a 256 "$APK"; } | tee -a "$RESULTS"

# --- 1. Install -------------------------------------------------------------
step "1. adb install"
OUT=$(adb install "$APK" 2>&1)
say "$OUT"
if echo "$OUT" | grep -q "Success"; then
  R_INSTALL="PASS"
else
  R_INSTALL="FAIL"
  FAILED=1
  say "install did not report Success (any INSTALL_FAILED_* line above is verbatim)"
fi

if [ "$R_INSTALL" = "PASS" ]; then
  # --- 2. Launch ------------------------------------------------------------
  step "2. Launch app"
  OUT=$(adb shell am start -W -n "$PKG/.ui.MainActivity" 2>&1)
  say "$OUT"
  for i in $(seq 1 18); do
    top_activity | tee -a "$RESULTS"
    top_activity | grep -q "OnboardingActivity" && break
    sleep 5
  done
  if top_activity | grep -q "OnboardingActivity"; then
    R_LAUNCH="PASS (MainActivity routed to first-run OnboardingActivity)"
  else
    R_LAUNCH="FAIL (OnboardingActivity never came to front)"
    FAILED=1
  fi
fi

if [ "$R_INSTALL" = "PASS" ] && [ "${R_LAUNCH#PASS}" != "$R_LAUNCH" ]; then
  # --- 3a. Wizard: welcome -> chooser ---------------------------------------
  step "3a. Wizard welcome step"
  sleep 3
  dump_ui welcome
  shot wizard-welcome.png
  if ui_has 'text="Continue"'; then
    say 'welcome step shows primary button text "Continue"'
    tap_by resid btn_primary
    R_WIZARD="welcome->chooser tapped"
  else
    say "welcome step: Continue button not found in UI dump (see ui-welcome.xml)"
    R_WIZARD="FAIL at welcome"
    FAILED=1
  fi
fi

if [ "$R_WIZARD" = "welcome->chooser tapped" ]; then
  # --- 3b. Wizard: chooser -> install Alpine -------------------------------
  step "3b. Wizard distro chooser"
  sleep 3
  dump_ui choose
  shot wizard-choose.png
  if ui_has 'text="Alpine Linux"'; then
    say 'chooser lists "Alpine Linux" (preselected by the wizard)'
    tap_by resid btn_primary
    R_WIZARD="PASS (Continue, then Install Alpine Linux)"
  else
    say "chooser: Alpine Linux card not found in UI dump (see ui-choose.xml)"
    R_WIZARD="FAIL at chooser"
    FAILED=1
  fi
fi

if [ "$R_WIZARD" = "PASS (Continue, then Install Alpine Linux)" ]; then
  # --- 3c. Extraction: wait for the atomic userland dir ----------------------
  step "3c. First-run extraction (poll app data dir)"
  VERIFY_ROUTE=""
  extracted=0
  for i in $(seq 1 90); do
    if adb shell run-as "$PKG" ls files/userland >/dev/null 2>&1; then
      VERIFY_ROUTE="run-as"
      extracted=1
      break
    fi
    if [ $((i % 6)) -eq 0 ]; then
      STAGE=$(adb shell run-as "$PKG" ls files/ 2>/dev/null | tr '\n' ' ')
      say "poll $i: files/ = $STAGE"
    fi
    sleep 10
  done
  if [ "$extracted" != "1" ]; then
    # Fallback route: emulator images allow adb root; record which route
    # verified (or that neither could see the tree).
    adb root >/dev/null 2>&1
    sleep 2
    if adb shell ls "/data/data/$PKG/files/userland" >/dev/null 2>&1; then
      VERIFY_ROUTE="adb-root (run-as route failed)"
      extracted=1
    fi
  fi
  if [ "$extracted" = "1" ]; then
    R_EXTRACT="PASS (verified via $VERIFY_ROUTE)"
    say "verification route: $VERIFY_ROUTE"
    if [ "$VERIFY_ROUTE" = "run-as" ]; then
      say "userland top level:"
      adb shell run-as "$PKG" ls files/userland 2>&1 | tee -a "$RESULTS"
      say "etc/alpine-release: $(adb shell run-as "$PKG" cat files/userland/etc/alpine-release 2>&1 | tr -d '\r')"
      say "bin/ (first entries):"
      adb shell run-as "$PKG" ls files/userland/bin 2>&1 | head -5 | tee -a "$RESULTS"
    else
      say "userland top level:"
      adb shell ls "/data/data/$PKG/files/userland" 2>&1 | tee -a "$RESULTS"
      say "etc/alpine-release: $(adb shell cat "/data/data/$PKG/files/userland/etc/alpine-release" 2>&1 | tr -d '\r')"
    fi
  else
    R_EXTRACT="FAIL (files/userland never appeared within 15 min; see logcat)"
    FAILED=1
  fi
fi

if [ "${R_EXTRACT#PASS}" != "$R_EXTRACT" ]; then
  # --- 3d. Wizard finish -> first userland session ---------------------------
  step "3d. Wizard finish (Start) and first session"
  for i in $(seq 1 12); do
    dump_ui "installing-$i"
    ui_has 'text="All set"' && break
    sleep 5
  done
  shot wizard-done.png
  if ui_has 'text="Start"'; then
    say 'install step shows "All set" / "Start"'
    tap_by resid btn_primary
  else
    say 'Start button not found after extraction (see ui-installing-*.xml, wizard-done.png)'
  fi
  sleep 5
  dump_ui after-start
  # Runtime-permission dialog (notification permission is requested only
  # after onboarding) may cover the terminal; dismiss it honestly.
  if ui_has "permissioncontroller" || ui_has "Don.t allow"; then
    say "permission dialog present; tapping Don't allow"
    tap_by text "t allow"
    sleep 2
  fi
  say "settling 25s while the auto-created userland session starts..."
  sleep 25
  dump_ui final
  shot final-terminal.png
  top_activity | tee -a "$RESULTS"
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  if [ -n "$PID" ]; then
    R_SESSION="PASS (app process alive, pid $PID; prompt itself is in final-terminal.png)"
    say "app process alive: pid $PID"
  else
    R_SESSION="FAIL (app process not running after first session start)"
    FAILED=1
  fi
fi

# --- 4. Userland shell: not attempted, by design -----------------------------
step "4. Shell inside the userland"
say "NOT ATTEMPTED - the app exposes no intent/service/API route into a"
say "userland shell: SessionService carries only internal EXIT and"
say "wakelock-toggle actions, OnboardingActivity is not exported, and"
say "sessions are created only from the app's own UI. Under the smoke"
say "rules the checklist stops at extraction-verified rather than"
say "simulating a shell. Whether the auto-created session reached a"
say "live prompt is observable in final-terminal.png."

# --- 5. Logcat analysis -------------------------------------------------------
step "5. Logcat: SELinux denials and crashes (verbatim)"
kill $LOGPID >/dev/null 2>&1
sleep 1
AVC_COUNT=$(grep -c "avc: denied" "$WORK/logcat-full.txt" 2>/dev/null)
say "avc: denied line count: $AVC_COUNT"
grep "avc: denied" "$WORK/logcat-full.txt" 2>/dev/null | head -50 | tee -a "$RESULTS"
say "--- crash signatures (FATAL EXCEPTION / Fatal signal / tombstones) ---"
grep -nE "FATAL EXCEPTION|Fatal signal|signal 11|signal 6|Tombstone|>>> $PKG <<<" \
  "$WORK/logcat-full.txt" 2>/dev/null | head -30 | tee -a "$RESULTS"
say "--- app process death lines, if any ---"
grep -nE "Process $PKG.*has died|Killing .* $PKG" \
  "$WORK/logcat-full.txt" 2>/dev/null | head -10 | tee -a "$RESULTS"
say "--- lines mentioning the emulation layer (first 30) ---"
grep -niE "arm64chroot|chroot-ng|userland" "$WORK/logcat-full.txt" 2>/dev/null \
  | head -30 | tee -a "$RESULTS"

# --- Summary ------------------------------------------------------------------
step "SMOKE SUMMARY"
{
  echo "## Emulator smoke test — spike APK"
  echo ""
  echo "- APK install (adb install): **$R_INSTALL**"
  echo "- App launch -> first-run wizard: **$R_LAUNCH**"
  echo "- Wizard flow (Continue -> Install Alpine Linux): **$R_WIZARD**"
  echo "- Alpine rootfs extraction (app data dir): **$R_EXTRACT**"
  echo "- First userland session (process survival): **$R_SESSION**"
  echo "- Shell inside userland (uname / apk add python3 / persistence): **NOT ATTEMPTED** — no intent/service/API route into a session exists; automation stops at extraction-verified by design."
  echo "- SELinux \`avc: denied\` lines in logcat: **$AVC_COUNT** (verbatim lines in the smoke-evidence artifact, logcat-full.txt)"
  echo ""
  echo "Guest: stock Android API 36, arm64-v8a, on a macOS ARM runner. This proves install, wizard, extraction and session start on stock Android only."
  echo "It does NOT prove Samsung One UI SELinux behaviour or real speed on a Fold 6 — those remain phone-only questions. All timings here are EMULATOR-ONLY."
} | tee -a "$RESULTS" >> "$GITHUB_STEP_SUMMARY"

say "overall: $([ "$FAILED" = "0" ] && echo PASS || echo FAIL)"
exit $FAILED
