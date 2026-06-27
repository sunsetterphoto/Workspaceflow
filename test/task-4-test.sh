#!/usr/bin/env bash
# Task-4-Test: Space-Auflösung beim Wiederherstellen UND Schließen
# Startet je eine isolierte nested KWin-Session für Run A (restore) und
# Run B (close), prüft ob "WSF: removed space" und desktop_count=1 erscheinen.
#
# Verwendung: ./test/task-4-test.sh
# NIEMALS gegen die Live-Session ausführen.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

# shellcheck source=test/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

MAIN_JS="$PROJECT_DIR/contents/code/main.js"

echo "WSF-TEST: Task-4 — Space-Auflösung beim Wiederherstellen und Schließen"
echo "WSF-TEST: PROJECT=$PROJECT_DIR"
echo ""

# ── Hilfsfunktion: KWin-Session starten und Probe ausführen ──────────────────
# run_session <log_file> <probe_js>
run_session() {
    local log_file="$1"
    local probe_js="$2"

    local cfg_dir
    cfg_dir="$(mktemp -d /tmp/wsf-task4-cfg-XXXXXX)"
    cat > "$cfg_dir/kwinrc" << 'KWINRC_EOF'
[Desktops]
Number=1
Rows=1
KWINRC_EOF

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

DISPLAY="\$XDISPLAY" xmessage -timeout 30 "WSF Task4 Test" &
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

# ═══════════════════════════════════════════════════════════════════════════════
# RUN A: maximize → restore (setMaximize(false, false))
# ═══════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════"
echo "WSF-TEST: RUN A — maximize → restore"
echo "════════════════════════════════"

LOG_A="$(mktemp /tmp/wsf-task4-runA-XXXXXX.log)"
LOG="$LOG_A"

PROBE_A="$(mktemp /tmp/wsf-task4-probeA-XXXXXX.js)"
cat > "$PROBE_A" << 'PROBE_A_EOF'
// Task-4-Probe A: maximiert dann stellt wieder her
print("WSF-PROBE: Task4-ProbeA gestartet");
print("WSF-PROBE: desktops_before=" + workspace.desktops.length);

workspace.windowAdded.connect(function(w) {
    print("WSF-PROBE: windowAdded: " + w.caption +
          " maximizable=" + w.maximizable +
          " specialWindow=" + w.specialWindow);
    if (w.maximizable && !w.specialWindow && !w.dock) {
        print("WSF-PROBE: maximiere: " + w.caption);
        w.setMaximize(true, true);
        print("WSF-PROBE: nach Maximize, maximizeMode=" + w.maximizeMode);

        // Restore via desktopsChanged: erst wenn Space existiert (cnt >= 2) ist
        // sichergestellt, dass main.js die createSpaceFor-Logik abgeschlossen hat.
        w.desktopsChanged.connect(function() {
            print("WSF-PROBE: desktopsChanged gefeuert, desktops.length=" + workspace.desktops.length);
            if (workspace.desktops.length >= 2) {
                print("WSF-PROBE: jetzt Restore");
                w.setMaximize(false, false);
                print("WSF-PROBE: DONE");
            }
        });
    }
});

var wins = workspace.windowList();
print("WSF-PROBE: windowList.length=" + wins.length);
for (var i = 0; i < wins.length; i++) {
    var w = wins[i];
    if (w.maximizable && !w.specialWindow && !w.dock && !w.deleted) {
        print("WSF-PROBE: maximiere vorhandenes Fenster: " + w.caption);
        w.setMaximize(true, true);
        print("WSF-PROBE: nach Maximize, maximizeMode=" + w.maximizeMode);
        w.desktopsChanged.connect(function() {
            if (workspace.desktops.length >= 2) {
                print("WSF-PROBE: jetzt Restore (vorhanden)");
                w.setMaximize(false, false);
                print("WSF-PROBE: DONE");
            }
        });
    }
}
PROBE_A_EOF

run_session "$LOG_A" "$PROBE_A"

echo "── WSF:-Zeilen im Log (Run A) ──"
grep -E "WSF[-:]" "$LOG_A" || echo "(keine WSF-Zeilen)"
echo ""

echo "── Assertions (Run A) ──"
assert_log "WSF: loaded v"                 && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"              && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: created space at index 1" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: removed space"            && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 1                     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# RUN B: maximize → close the window
# ═══════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════"
echo "WSF-TEST: RUN B — maximize → close"
echo "════════════════════════════════"

LOG_B="$(mktemp /tmp/wsf-task4-runB-XXXXXX.log)"
LOG="$LOG_B"

PROBE_B="$(mktemp /tmp/wsf-task4-probeB-XXXXXX.js)"
cat > "$PROBE_B" << 'PROBE_B_EOF'
// Task-4-Probe B: maximiert dann schließt das Fenster
print("WSF-PROBE: Task4-ProbeB gestartet");
print("WSF-PROBE: desktops_before=" + workspace.desktops.length);

function processWindow(w) {
    print("WSF-PROBE: processWindow: " + w.caption);
    w.desktopsChanged.connect(function() {
        print("WSF-PROBE: desktopsChanged, desktops.length=" + workspace.desktops.length);
        if (workspace.desktops.length >= 2) {
            print("WSF-PROBE: schließe Fenster: " + w.caption);
            w.closeWindow();
            print("WSF-PROBE: closeWindow aufgerufen");
            print("WSF-PROBE: DONE");
        }
    });
    print("WSF-PROBE: maximiere: " + w.caption);
    w.setMaximize(true, true);
    print("WSF-PROBE: nach Maximize, maximizeMode=" + w.maximizeMode);
}

workspace.windowAdded.connect(function(w) {
    print("WSF-PROBE: windowAdded: " + w.caption +
          " maximizable=" + w.maximizable +
          " specialWindow=" + w.specialWindow);
    if (w.maximizable && !w.specialWindow && !w.dock) {
        processWindow(w);
    }
});

var wins = workspace.windowList();
print("WSF-PROBE: windowList.length=" + wins.length);
for (var i = 0; i < wins.length; i++) {
    var w = wins[i];
    if (w.maximizable && !w.specialWindow && !w.dock && !w.deleted) {
        processWindow(w);
    }
}
PROBE_B_EOF

run_session "$LOG_B" "$PROBE_B"

echo "── WSF:-Zeilen im Log (Run B) ──"
grep -E "WSF[-:]" "$LOG_B" || echo "(keine WSF-Zeilen)"
echo ""

echo "── Assertions (Run B) ──"
assert_log "WSF: loaded v"                 && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"              && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: created space at index 1" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: removed space"            && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 1                     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
echo ""

# ── Aufräumen ─────────────────────────────────────────────────────────────────
rm -f "$PROBE_A" "$PROBE_B" "$LOG_A" "$LOG_B"

echo "════════════════════════════════"
echo "── Gesamt-Ergebnis: PASS=$PASS FAIL=$FAIL ──"
echo "════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
