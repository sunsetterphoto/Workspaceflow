#!/usr/bin/env bash
# Task-3-Test: Space-Erzeugung beim Maximieren (nested KWin, isoliertes Config)
# Startet eine isolierte nested KWin-Session mit eigenem XDG_CONFIG_HOME
# (1 Desktop), lädt main.js + xmessage-Fenster, maximiert programmatisch
# via KWin-JS und prüft die WSF-Log-Ausgabe.
#
# Verwendung: ./test/task-3-test.sh
# NIEMALS gegen die Live-Session ausführen.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="${LOG:-/tmp/wsf-task3-$$.log}"
PASS=0
FAIL=0

# shellcheck source=test/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

echo "WSF-TEST: Task-3 — Space-Erzeugung beim Maximieren"
echo "WSF-TEST: PROJECT=$PROJECT_DIR"
echo "WSF-TEST: LOG=$LOG"
echo ""

# ── Isoliertes KWin-Config (1 Desktop, kein Gitter) ──────────────────────────
CFG_DIR="$(mktemp -d /tmp/wsf-task3-cfg-XXXXXX)"
mkdir -p "$CFG_DIR"
cat > "$CFG_DIR/kwinrc" << 'KWINRC_EOF'
[Desktops]
Number=1
Rows=1
KWINRC_EOF

# ── Probe-Skript: maximiert das erste maximierbare Fenster ────────────────────
PROBE_JS="$(mktemp /tmp/wsf-task3-probe-XXXXXX.js)"
cat > "$PROBE_JS" << 'PROBE_EOF'
// Task-3-Probe: maximiert erstes maximierbares Fenster via setMaximize
print("WSF-PROBE: Task3-Probe gestartet");
print("WSF-PROBE: desktops_before=" + workspace.desktops.length);

function maximiereErsteFenster() {
    var wins = workspace.windowList();
    print("WSF-PROBE: windowList.length=" + wins.length);
    var gefunden = false;
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        if (w.maximizable && !w.specialWindow && !w.dock && !w.deleted) {
            print("WSF-PROBE: maximiere vorhandenes Fenster: " + w.caption);
            w.setMaximize(true, true);
            print("WSF-PROBE: setMaximize done, maximizeMode=" + w.maximizeMode);
            gefunden = true;
        }
    }
    return gefunden;
}

// windowAdded-Hook: maximiert neue Fenster sofort wenn sie erscheinen
workspace.windowAdded.connect(function(w) {
    print("WSF-PROBE: windowAdded: " + w.caption +
          " maximizable=" + w.maximizable +
          " specialWindow=" + w.specialWindow);
    if (w.maximizable && !w.specialWindow && !w.dock) {
        print("WSF-PROBE: maximiere neu hinzugefügtes Fenster: " + w.caption);
        w.setMaximize(true, true);
        print("WSF-PROBE: nach setMaximize maximizeMode=" + w.maximizeMode);
        print("WSF-PROBE: DONE");
    }
});

// Schon vorhandene Fenster prüfen
if (!maximiereErsteFenster()) {
    print("WSF-PROBE: noch keine maximierbaren Fenster, warte auf windowAdded ...");
} else {
    print("WSF-PROBE: DONE");
}
PROBE_EOF

MAIN_JS="$PROJECT_DIR/contents/code/main.js"

# ── Nested Session ────────────────────────────────────────────────────────────
(
    export QT_LOGGING_RULES="js.debug=true;js=true"
    export QT_FORCE_STDERR_LOGGING=1
    # Isoliertes KWin-Config damit die Session mit 1 Desktop startet
    export XDG_CONFIG_HOME="$CFG_DIR"

    dbus-run-session -- bash << INNER
set -u

# Vorhandene X11-Sockets merken (um den Xwayland-Display zu erkennen)
BEFORE_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)

# KWin mit isoliertem Config starten
XDG_CONFIG_HOME="$CFG_DIR" kwin_wayland \
    --virtual --xwayland --no-lockscreen --no-global-shortcuts --no-kactivities &
KWIN_PID=\$!

# Warten bis org.kde.KWin auf dem Bus erscheint
for i in \$(seq 1 40); do
    qdbus-qt6 org.kde.KWin /Scripting >/dev/null 2>&1 && break
    sleep 0.5
done
echo "WSF-TEST: KWin bereit (PID=\$KWIN_PID)"

# main.js laden und starten
qdbus-qt6 org.kde.KWin /Scripting loadScript "$MAIN_JS" workspaceflow >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: main.js geladen"

# Xwayland-Display ermitteln (neuer Socket nach KWin-Start)
sleep 1
AFTER_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)
NEW_XSOCK=\$(comm -13 <(echo "\$BEFORE_X11") <(echo "\$AFTER_X11") | head -1 || true)
if [ -n "\$NEW_XSOCK" ]; then
    XDISPLAY=":\${NEW_XSOCK#X}"
else
    XDISPLAY=":1"
fi
echo "WSF-TEST: Xwayland-Display=\$XDISPLAY"

# Test-Fenster via Xwayland starten
DISPLAY="\$XDISPLAY" xmessage -timeout 30 "WSF Task3 Test" &
XMSG_PID=\$!
echo "WSF-TEST: xmessage gestartet (PID=\$XMSG_PID)"

# Kurz warten bis xmessage im KWin erscheint, dann Probe laden
sleep 2

qdbus-qt6 org.kde.KWin /Scripting loadScript "$PROBE_JS" wsf-probe >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: Probe geladen"

# Probe laufen lassen
sleep 5

# Aufräumen
kill \$XMSG_PID 2>/dev/null || true
kill \$KWIN_PID 2>/dev/null || true
wait \$KWIN_PID 2>/dev/null || true
echo "WSF-TEST: Session beendet"
INNER
) 2>"$LOG"

echo "── WSF:-Zeilen im Log ──"
grep -E "WSF[-:]" "$LOG" || echo "(keine WSF-Zeilen)"
echo ""

# ── Assertions ───────────────────────────────────────────────────────────────
echo "── Assertions ──"
assert_log "WSF: loaded v"                    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"                  && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: created space at index 1"    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 2                         && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# Bonus: Desktop-Anzahl um 1 gestiegen
BEFORE_COUNT=$(grep "WSF-PROBE: desktops_before=" "$LOG" | sed 's/.*desktops_before=//' | tr -d '[:space:]' | tail -1 || echo "")
AFTER_COUNT=$(grep "WSF: desktop_count=" "$LOG" | sed 's/.*desktop_count=//' | tr -d '[:space:]' | tail -1 || echo "")
if [ -n "$BEFORE_COUNT" ] && [ -n "$AFTER_COUNT" ]; then
    EXPECTED_AFTER=$((BEFORE_COUNT + 1))
    if [ "$AFTER_COUNT" -eq "$EXPECTED_AFTER" ]; then
        echo "WSF-TEST PASS: desktop_count stieg von $BEFORE_COUNT auf $AFTER_COUNT (Δ=+1)"
        PASS=$((PASS+1))
    else
        echo "WSF-TEST FAIL: erwartet +1 (von $BEFORE_COUNT auf $EXPECTED_AFTER), got $AFTER_COUNT"
        FAIL=$((FAIL+1))
    fi
else
    echo "WSF-TEST FAIL: konnte BEFORE/AFTER desktop_count nicht extrahieren"
    FAIL=$((FAIL+1))
fi

echo ""
echo "── Ergebnis: PASS=$PASS FAIL=$FAIL ──"

rm -f "$PROBE_JS"
rm -rf "$CFG_DIR"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
