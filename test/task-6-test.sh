#!/usr/bin/env bash
# Task-6-Test: Konfigurierbare Ignorier-Liste
#
# TDD-Nachweis (historisch; loadConfig() ist implementiert):
#   RUN A (RED):   Reproduziert den Zustand VOR der Implementierung — loadConfig()
#                  war noch nicht vorhanden → Space wurde TROTZDEM erzeugt, kein
#                  "WSF: ignored …". Dieses Run schlägt heute IMMER FEHL, da
#                  loadConfig() inzwischen implementiert ist. Überspringen via
#                  --skip-red ist der normale Betriebsmodus.
#   RUN B (GREEN): loadConfig() implementiert → Xmessage wird ignoriert,
#                  kein Space erzeugt, desktop_count=1 bleibt.
#   RUN C (Gegenprobe): IgnoreClasses leer → Space wird wie gewohnt erzeugt.
#
# Verwendung: ./test/task-6-test.sh [--skip-red]
# NIEMALS gegen die Live-Session ausführen.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
SKIP_RED="${1:-}"

# shellcheck source=test/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

MAIN_JS="$PROJECT_DIR/contents/code/main.js"

echo "WSF-TEST: Task-6 — Konfigurierbare Ignorier-Liste"
echo "WSF-TEST: PROJECT=$PROJECT_DIR"
echo ""

# ── Hilfsfunktion: Session starten ──────────────────────────────────────────
# run_session <log_file> <probe_js> <kwinrc_content>
run_session() {
    local log_file="$1"
    local probe_js="$2"
    local kwinrc_content="$3"

    local cfg_dir
    cfg_dir="$(mktemp -d /tmp/wsf-task6-cfg-XXXXXX)"
    printf '%s' "$kwinrc_content" > "$cfg_dir/kwinrc"

    (
        export QT_LOGGING_RULES="js.debug=true;js=true"
        export QT_FORCE_STDERR_LOGGING=1
        export XDG_CONFIG_HOME="$cfg_dir"

        dbus-run-session -- bash << INNER
set -u

BEFORE_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)

XDG_CONFIG_HOME="$cfg_dir" kwin_wayland \
    --virtual --xwayland --no-lockscreen --no-global-shortcuts --no-kactivities &
KWIN_PID=\$!

for i in \$(seq 1 40); do
    qdbus-qt6 org.kde.KWin /Scripting >/dev/null 2>&1 && break
    sleep 0.5
done
echo "WSF-TEST: KWin bereit (PID=\$KWIN_PID)"

qdbus-qt6 org.kde.KWin /Scripting loadScript "$MAIN_JS" workspaceflow >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: main.js geladen"

sleep 1
AFTER_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)
NEW_XSOCK=\$(comm -13 <(echo "\$BEFORE_X11") <(echo "\$AFTER_X11") | head -1 || true)
if [ -n "\$NEW_XSOCK" ]; then
    XDISPLAY=":\${NEW_XSOCK#X}"
else
    XDISPLAY=":1"
fi
echo "WSF-TEST: Xwayland-Display=\$XDISPLAY"

DISPLAY="\$XDISPLAY" xmessage -timeout 30 "WSF Task6 Test" &
XMSG_PID=\$!
echo "WSF-TEST: xmessage gestartet (PID=\$XMSG_PID)"

sleep 2

qdbus-qt6 org.kde.KWin /Scripting loadScript "$probe_js" wsf-probe >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: Probe geladen"

sleep 6

kill \$XMSG_PID 2>/dev/null || true
kill \$KWIN_PID 2>/dev/null || true
wait \$KWIN_PID 2>/dev/null || true
echo "WSF-TEST: Session beendet"
INNER
    ) 2>"$log_file"

    rm -rf "$cfg_dir"
}

# ── Probe-Skript: maximiert das erste maximierbare Fenster ───────────────────
PROBE_MAXIMIZE_JS="$(mktemp /tmp/wsf-task6-maximize-XXXXXX.js)"
cat > "$PROBE_MAXIMIZE_JS" << 'PROBE_EOF'
// Task-6-Probe: maximiert erstes maximierbares Fenster
print("WSF-PROBE: Task6-Probe gestartet");
print("WSF-PROBE: desktops_before=" + workspace.desktops.length);

function tryMaximize(w) {
    if (w.maximizable && !w.specialWindow && !w.dock) {
        print("WSF-PROBE: resourceClass=[" + w.resourceClass + "]");
        print("WSF-PROBE: maximiere: " + w.caption);
        w.setMaximize(true, true);
        print("WSF-PROBE: maximizeMode=" + w.maximizeMode);
        print("WSF-PROBE: desktops_after=" + workspace.desktops.length);
        print("WSF-PROBE: DONE");
    }
}

workspace.windowAdded.connect(function(w) {
    print("WSF-PROBE: windowAdded: " + w.caption);
    tryMaximize(w);
});

var wins = workspace.windowList();
print("WSF-PROBE: windowList.length=" + wins.length);
for (var i = 0; i < wins.length; i++) {
    tryMaximize(wins[i]);
}
PROBE_EOF

# ═══════════════════════════════════════════════════════════════════════════════
# RUN A (RED): IgnoreClasses=Xmessage gesetzt, aber loadConfig() noch NICHT
#              implementiert → Space wird erzeugt, kein "ignored Xmessage"
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_RED" != "--skip-red" ]; then
    echo "════════════════════════════════"
    echo "WSF-TEST: RUN A (RED/historisch) — simuliert Zustand vor loadConfig()-Implementierung"
    echo "WSF-TEST: Erwartet heute FAIL (loadConfig() ist implementiert — RED nur historischer TDD-Beleg)"
    echo "════════════════════════════════"

    LOG_A="$(mktemp /tmp/wsf-task6-runA-XXXXXX.log)"
    LOG="$LOG_A"

    KWINRC_A='[Desktops]
Number=1
Rows=1

[Script-workspaceflow]
IgnoreClasses=Xmessage
'
    run_session "$LOG_A" "$PROBE_MAXIMIZE_JS" "$KWINRC_A"

    echo "── WSF-Zeilen (RUN A) ──"
    grep -E "WSF" "$LOG_A" || echo "(keine)"
    echo ""

    echo "── Assertions RUN A (erwartet: FAIL für ignored + desktop_count=1) ──"
    # Diese Assertions sollen FEHLSCHLAGEN (RED-Phase)
    assert_log "WSF: ignored Xmessage"         && PASS=$((PASS+1)) || { echo "  → RED: erwartet FAIL ✓"; FAIL=$((FAIL+1)); }
    assert_desktop_count 1                      && PASS=$((PASS+1)) || { echo "  → RED: erwartet FAIL ✓"; FAIL=$((FAIL+1)); }
    echo ""
    echo "WSF-TEST: RUN A abgeschlossen (Failures oben = TDD RED bestätigt)"
    echo ""

    rm -f "$LOG_A"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# RUN B (GREEN): Nach loadConfig()-Implementierung in main.js
#   IgnoreClasses=Xmessage → Xmessage wird ignoriert, kein Space, desktop_count=1
# ═══════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════"
echo "WSF-TEST: RUN B (GREEN) — loadConfig() implementiert"
echo "WSF-TEST: Erwartet: PASS für alle Assertions"
echo "════════════════════════════════"

LOG_B="$(mktemp /tmp/wsf-task6-runB-XXXXXX.log)"
LOG="$LOG_B"

KWINRC_B='[Desktops]
Number=1
Rows=1

[Script-workspaceflow]
IgnoreClasses=Xmessage
'
run_session "$LOG_B" "$PROBE_MAXIMIZE_JS" "$KWINRC_B"

echo "── WSF-Zeilen (RUN B) ──"
grep -E "WSF" "$LOG_B" || echo "(keine)"
echo ""

echo "── Assertions RUN B ──"
BEFORE_PASS=$PASS; BEFORE_FAIL=$FAIL
assert_log "WSF: loaded v"                    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: ignore=Xmessage"            && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"                 && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: ignored Xmessage"           && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log_not "WSF: created space at index" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
# Wenn ignoriert: createSpaceFor/removeSpaceFor werden NIE aufgerufen,
# daher erscheint "WSF: desktop_count=N" nie im Log. Gegenprüfung:
# desktop_count=2 darf NICHT erscheinen (kein Space erzeugt),
# und die Probe bestätigt desktops_after=1.
assert_log_not "WSF: desktop_count=2"        && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: desktops_after=1"     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
B_PASS=$((PASS - BEFORE_PASS))
B_FAIL=$((FAIL - BEFORE_FAIL))
echo "WSF-TEST: RUN B Ergebnis: PASS=$B_PASS FAIL=$B_FAIL"
echo ""

rm -f "$LOG_B"

# ═══════════════════════════════════════════════════════════════════════════════
# RUN C (Gegenprobe): IgnoreClasses leer → Space wird wie gewohnt erzeugt
# ═══════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════"
echo "WSF-TEST: RUN C (Gegenprobe) — IgnoreClasses leer"
echo "WSF-TEST: Erwartet: Space erzeugt, desktop_count=2"
echo "════════════════════════════════"

LOG_C="$(mktemp /tmp/wsf-task6-runC-XXXXXX.log)"
LOG="$LOG_C"

KWINRC_C='[Desktops]
Number=1
Rows=1

[Script-workspaceflow]
IgnoreClasses=
'
run_session "$LOG_C" "$PROBE_MAXIMIZE_JS" "$KWINRC_C"

echo "── WSF-Zeilen (RUN C) ──"
grep -E "WSF" "$LOG_C" || echo "(keine)"
echo ""

echo "── Assertions RUN C ──"
BEFORE_PASS=$PASS; BEFORE_FAIL=$FAIL
assert_log "WSF: loaded v"                    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"                 && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: created space at index 1"   && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 2                        && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
C_PASS=$((PASS - BEFORE_PASS))
C_FAIL=$((FAIL - BEFORE_FAIL))
echo "WSF-TEST: RUN C Ergebnis: PASS=$C_PASS FAIL=$C_FAIL"
echo ""

rm -f "$LOG_C"

# ── Aufräumen ─────────────────────────────────────────────────────────────────
rm -f "$PROBE_MAXIMIZE_JS"

echo "════════════════════════════════"
echo "── Gesamt-Ergebnis: PASS=$PASS FAIL=$FAIL ──"
echo "════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
