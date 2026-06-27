#!/usr/bin/env bash
# test/invariant-desktop0.sh — Invariante: workspace.desktops[0] bleibt identisch
#
# Beweist: das VirtualDesktop-Objekt an workspace.desktops[0] ist VOR und NACH
# einem vollständigen Create+Remove-Zyklus (Fenster maximieren → Space an Index 1
# entsteht → wiederherstellen → Space weg) DASSELBE Objekt (Objektidentität ===).
#
# So ist die zentrale Annahme „createDesktop(1,…) fügt an Index 1 ein, permanenter
# Desktop bleibt Index 0" explizit gesichert.
#
# Läuft AUSSCHLIESSLICH in isolierter nested KWin-Session (virtual, eigener D-Bus,
# eigenes XDG_CONFIG_HOME). NIEMALS gegen die Live-Session ausführen. Kein sudo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="${LOG:-/tmp/wsf-invariant-d0-$$.log}"
PASS=0
FAIL=0

# shellcheck source=test/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

MAIN_JS="$PROJECT_DIR/contents/code/main.js"

echo "WSF-TEST: invariant-desktop0 — workspace.desktops[0] Objektidentität"
echo "WSF-TEST: PROJECT=$PROJECT_DIR"
echo "WSF-TEST: LOG=$LOG"
echo ""

CFG_DIR="$(mktemp -d /tmp/wsf-invariant-d0-cfg-XXXXXX)"
PROBE_JS="$(mktemp /tmp/wsf-invariant-d0-probe-XXXXXX.js)"
trap 'rm -f "$PROBE_JS"; rm -rf "$CFG_DIR"' EXIT

cat > "$CFG_DIR/kwinrc" << 'KWINRC_EOF'
[Desktops]
Number=1
Rows=1

[Script-workspaceflow]
IgnoreClasses=
KWINRC_EOF

cat > "$PROBE_JS" << 'PROBE_EOF'
// invariant-desktop0-probe.js
// Prüft: workspace.desktops[0] ist VOR und NACH einem Create+Remove-Zyklus
// dasselbe JS-Objekt (=== Objektidentität) und hat dieselbe id (UUID).
print("WSF-PROBE: invariant-desktop0 gestartet");

var d0_before = workspace.desktops[0];
print("WSF-PROBE: d0_before_id=" + d0_before.id);
print("WSF-PROBE: desktops_before=" + workspace.desktops.length);

var win = null;
var phaseCreateDone = false;

// Globaler Desktop-Zähler-Watch für Create (1→2) und Remove (2→1)
workspace.desktopsChanged.connect(function() {
    var cnt = workspace.desktops.length;
    var d0_now = workspace.desktops[0];
    var sameObj = (d0_before === d0_now);
    var sameId  = (d0_before.id === d0_now.id);

    print("WSF-PROBE: desktopsChanged cnt=" + cnt +
          " d0_now_id=" + d0_now.id +
          " same-object=" + sameObj +
          " same-id=" + sameId);

    if (cnt === 2 && !phaseCreateDone) {
        phaseCreateDone = true;
        print("WSF-PROBE: identity-during-create same-object=" + sameObj + " id-same=" + sameId);
        // Space existiert jetzt — Fenster wiederherstellen, damit Space entfernt wird
        if (win !== null) {
            print("WSF-PROBE: stellt wieder her: " + win.caption);
            win.setMaximize(false, false);
        } else {
            print("WSF-PROBE: WARN win ist null beim Restore");
        }
    }

    if (cnt === 1 && phaseCreateDone) {
        print("WSF-PROBE: identity-after-remove same-object=" + sameObj + " id-same=" + sameId);
        print("WSF-PROBE: DONE");
    }
});

function tryMaximize(w) {
    if (win !== null) return;                    // nur einmal
    if (!w.maximizable || w.specialWindow || w.dock) return;
    win = w;
    print("WSF-PROBE: starte Zyklus: " + w.caption);
    w.setMaximize(true, true);
    print("WSF-PROBE: nach setMaximize maximizeMode=" + w.maximizeMode);
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

echo "════════════════════════════════"
echo "WSF-TEST: Starte nested KWin-Session (virtual, isoliert)"
echo "════════════════════════════════"

(
    export QT_LOGGING_RULES="js.debug=true;js=true"
    export QT_FORCE_STDERR_LOGGING=1
    export XDG_CONFIG_HOME="$CFG_DIR"

    dbus-run-session -- bash << INNER
set -u
export QT_LOGGING_RULES="js.debug=true;js=true"
export QT_FORCE_STDERR_LOGGING=1

BEFORE_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)

XDG_CONFIG_HOME="$CFG_DIR" kwin_wayland \
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

# Invariant-Probe VOR dem Testfenster laden (damit windowAdded greift)
qdbus-qt6 org.kde.KWin /Scripting loadScript "$PROBE_JS" wsf-probe >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: invariant-Probe geladen"

# Testfenster starten (xmessage — maximierbar, kein Spezialfenster)
DISPLAY="\$XDISPLAY" xmessage -timeout 60 "WSF Invariant Desktop0 Test" &
XMSG_PID=\$!
echo "WSF-TEST: Testfenster gestartet (PID=\$XMSG_PID)"

# Warten: windowAdded → setMaximize → desktopsChanged(cnt=2) →
#          setMaximize(false) → desktopsChanged(cnt=1) → DONE
sleep 8

kill \$XMSG_PID 2>/dev/null || true
kill \$KWIN_PID 2>/dev/null || true
wait \$KWIN_PID 2>/dev/null || true
echo "WSF-TEST: Session beendet"
INNER
) 2>"$LOG"

echo ""
echo "── WSF-Zeilen im Log ──"
grep -E "WSF[-:]" "$LOG" || echo "(keine WSF-Zeilen)"
echo ""

echo "════════════════════════════════"
echo "── Assertions ──"
echo "════════════════════════════════"

assert_log "WSF: loaded v"                                                    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: invariant-desktop0 gestartet"                          && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: created space at index 1"                                     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF: removed space"                                                && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: identity-during-create same-object=true id-same=true"  && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: identity-after-remove same-object=true id-same=true"   && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"                                                   && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 1                                                         && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "════════════════════════════════"
echo "── Gesamt-Ergebnis: PASS=$PASS FAIL=$FAIL ──"
echo "════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
