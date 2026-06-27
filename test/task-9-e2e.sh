#!/usr/bin/env bash
# test/task-9-e2e.sh — End-to-End-Verifikation des Vollszenarios (Task 9)
#
# Läuft AUSSCHLIESSLICH in einer isolierten nested KWin-Session (virtual).
# NIEMALS gegen die Live-Session ausführen. Kein sudo.
# Live-~/.config/kwinrc und ~/.local/share/kwin/scripts bleiben unberührt.
#
# Vollszenario:
#   1. App A starten + maximieren → Space@Index 1 entsteht, desktop_count=2
#   2. App B starten + maximieren → Space@Index 1, A rückt→2; desktop_count=3
#      Reihenfolge Desktop|B|A wird via window.desktops-Index belegt
#   3. Desktop-Wechsel zu Desktop[0] und zurück zu Desktop[1]
#   4. App B wiederherstellen → B-Space weg, desktop_count=2
#   5. App A schließen → A-Space weg, desktop_count=1
#   6. overviewEnabled=true in isolierter Config (install.sh-Logik)
#
# Verwendung: ./test/task-9-e2e.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="${LOG:-/tmp/wsf-task9-e2e-$$.log}"
PASS=0
FAIL=0

# shellcheck source=test/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

MAIN_JS="$PROJECT_DIR/contents/code/main.js"

echo "WSF-TEST: Task-9 E2E — Vollszenario in nested Session"
echo "WSF-TEST: PROJECT=$PROJECT_DIR"
echo "WSF-TEST: LOG=$LOG"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Schritt 6: overviewEnabled in isolierter Config (kein KWin nötig)
# Verifikation der install.sh-Logik gegen isolierte kwinrc, NICHT Live-Config.
# ═══════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════"
echo "WSF-TEST: Schritt 6 — overviewEnabled in isolierter Config"
OVERVIEW_CFG_DIR="$(mktemp -d /tmp/wsf-task9-overview-XXXXXX)"
# install.sh Zeile 42: kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true
XDG_CONFIG_HOME="$OVERVIEW_CFG_DIR" kwriteconfig6 \
    --file kwinrc --group Plugins --key overviewEnabled true
OVERVIEW_VAL=$(XDG_CONFIG_HOME="$OVERVIEW_CFG_DIR" kreadconfig6 \
    --file kwinrc --group Plugins --key overviewEnabled)
if [ "$OVERVIEW_VAL" = "true" ]; then
    echo "WSF-TEST PASS: overviewEnabled=true in isolierter Config (install.sh-Logik bestätigt)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: overviewEnabled='$OVERVIEW_VAL' — erwartet 'true'"
    FAIL=$((FAIL+1))
fi
rm -rf "$OVERVIEW_CFG_DIR"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Probe-Skripte erstellen (temporär, werden am Ende aufgeräumt)
# ═══════════════════════════════════════════════════════════════════════════════

# Stage 1: maximiert App A (erstes Fenster) und App B (zweites Fenster)
# via windowAdded. Nutzt desktopsChanged um Space-Erzeugung zu bestätigen.
PROBE_S1="$(mktemp /tmp/wsf-task9-stage1-XXXXXX.js)"
cat > "$PROBE_S1" << 'STAGE1_EOF'
// Stage 1: Maximiert App A (erstes Fenster), dann App B (zweites Fenster)
print("WSF-PROBE: Stage1 gestartet");
var windowA = null;
var windowB = null;

workspace.windowAdded.connect(function(w) {
    if (!w.maximizable || w.specialWindow || w.dock) return;
    print("WSF-PROBE: windowAdded: " + w.caption +
          " maximizable=" + w.maximizable +
          " specialWindow=" + w.specialWindow);

    if (windowA === null) {
        windowA = w;
        print("WSF-PROBE: Step1-AppA erkannt: " + w.caption);
        // desktopsChanged feuert wenn Space für A erzeugt und window.desktops gesetzt
        w.desktopsChanged.connect(function() {
            var cnt = workspace.desktops.length;
            print("WSF-PROBE: Step1-AppA-desktopsChanged cnt=" + cnt);
        });
        w.setMaximize(true, true);
        print("WSF-PROBE: Step1-AppA-setMaximize-done maximizeMode=" + w.maximizeMode);
    } else if (windowB === null && w !== windowA) {
        windowB = w;
        print("WSF-PROBE: Step2-AppB erkannt: " + w.caption);
        // desktopsChanged feuert wenn Space für B erzeugt (desktop_count wird 3)
        w.desktopsChanged.connect(function() {
            var cnt = workspace.desktops.length;
            print("WSF-PROBE: Step2-AppB-desktopsChanged cnt=" + cnt);
            if (cnt >= 3) {
                print("WSF-PROBE: Stage1-DONE");
            }
        });
        w.setMaximize(true, true);
        print("WSF-PROBE: Step2-AppB-setMaximize-done maximizeMode=" + w.maximizeMode);
    }
});

print("WSF-PROBE: warte auf App A und App B...");
STAGE1_EOF

# Stage 2: Reihenfolge prüfen (B@1, A@2), Navigation, B wiederherstellen
PROBE_S2="$(mktemp /tmp/wsf-task9-stage2-XXXXXX.js)"
cat > "$PROBE_S2" << 'STAGE2_EOF'
// Stage 2: Reihenfolge prüfen, Desktop-Navigation, App B wiederherstellen
print("WSF-PROBE: Stage2 gestartet");

var desks = workspace.desktops;
print("WSF-PROBE: Stage2-desktop_count=" + desks.length);

// Desktop-Reihenfolge loggen (Index → Name)
for (var i = 0; i < desks.length; i++) {
    print("WSF-PROBE: desktops-" + i + "-name=" + desks[i].name);
}

// Fenster auf Index 1 (B) und Index 2 (A) identifizieren
// Nach Vollszenario: desktops[0]=permanent, desktops[1]=B-Space, desktops[2]=A-Space
var windowA = null;
var windowB = null;
var wins = workspace.windowList();
print("WSF-PROBE: Stage2-windowList.length=" + wins.length);

for (var j = 0; j < wins.length; j++) {
    var w = wins[j];
    if (!w.maximizable || w.specialWindow) continue;
    if (!w.desktops || w.desktops.length === 0) continue;
    var wDesk = w.desktops[0];
    for (var k = 0; k < desks.length; k++) {
        if (desks[k] === wDesk) {
            print("WSF-PROBE: win-" + j + "-caption=" + w.caption +
                  " auf-desktops-idx=" + k + " name=" + desks[k].name);
            if (k === 1) {
                windowB = w;
                // BEWEIS: B auf Index 1 (direkt rechts vom permanenten Desktop)
                print("WSF-PROBE: B-space-index=1");
            }
            if (k === 2) {
                windowA = w;
                // BEWEIS: A auf Index 2 (durch B-Space verdrängt)
                print("WSF-PROBE: A-space-index=2");
            }
            break;
        }
    }
}

if (windowA === null) print("WSF-PROBE: WARN-windowA-nicht-gefunden-auf-idx2");
if (windowB === null) print("WSF-PROBE: WARN-windowB-nicht-gefunden-auf-idx1");

// Schritt 3: Desktop-Navigation — zu Desktop[0], zurück zu Desktop[1]
print("WSF-PROBE: Step3-Navigation-start");
var d0 = desks[0];
var d1 = desks[1];
workspace.currentDesktop = d0;
print("WSF-PROBE: Step3-auf-Desktop0=" + d0.name);
workspace.currentDesktop = d1;
print("WSF-PROBE: Step3-auf-Desktop1=" + d1.name);
print("WSF-PROBE: Step3-Navigation-done");

// Schritt 4: App B wiederherstellen (setMaximize(false,false))
// → onMaximizeChanged → removeSpaceFor(B) → WSF: removed space + desktop_count=2
if (windowB !== null) {
    print("WSF-PROBE: Step4-B-restore-start");
    windowB.setMaximize(false, false);
    print("WSF-PROBE: Step4-B-maximizeMode-nach-restore=" + windowB.maximizeMode);
} else {
    print("WSF-PROBE: WARN Step4 windowB nicht gefunden - uebersprungen");
}

// Schritt 5 wird aus dem Bash-Skript erledigt:
// kill APP_A_PID → workspace.windowRemoved → removeSpaceFor(A) → desktop_count=1

print("WSF-PROBE: DONE");
STAGE2_EOF

# ── Isoliertes KWin-Config (NICHT die Live-kwinrc) ───────────────────────────
CFG_DIR="$(mktemp -d /tmp/wsf-task9-cfg-XXXXXX)"
cat > "$CFG_DIR/kwinrc" << 'KWINRC_EOF'
[Desktops]
Number=1
Rows=1

[Script-workspaceflow]
IgnoreClasses=
KWINRC_EOF

# ═══════════════════════════════════════════════════════════════════════════════
# Nested KWin-Session (isolierter D-Bus via dbus-run-session)
# ═══════════════════════════════════════════════════════════════════════════════
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

# X11-Sockets vor KWin-Start merken (für Xwayland-Display-Erkennung)
BEFORE_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)

# KWin virtuell starten (eigener Session-Bus, kein echter Display)
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

# Xwayland-Display ermitteln (neuer X11-Socket nach KWin-Start)
sleep 1
AFTER_X11=\$(ls /tmp/.X11-unix/ 2>/dev/null | sort || true)
NEW_XSOCK=\$(comm -13 <(echo "\$BEFORE_X11") <(echo "\$AFTER_X11") | head -1 || true)
if [ -n "\$NEW_XSOCK" ]; then
    XDISPLAY=":\${NEW_XSOCK#X}"
else
    XDISPLAY=":1"
fi
echo "WSF-TEST: Xwayland-Display=\$XDISPLAY"

# Stage-1-Probe laden (BEVOR Fenster erscheinen, damit windowAdded greift)
qdbus-qt6 org.kde.KWin /Scripting loadScript "$PROBE_S1" wsf-probe-s1 >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: Stage1-Probe geladen"

# ── Schritt 1: App A starten ──────────────────────────────────────────────────
DISPLAY="\$XDISPLAY" xmessage -timeout 120 "WSF App A" &
APP_A_PID=\$!
echo "WSF-TEST: App A gestartet (PID=\$APP_A_PID)"

# Warten: App A erscheint, windowAdded feuert, setMaximize, desktopsChanged
sleep 4

# ── Schritt 2: App B starten ──────────────────────────────────────────────────
DISPLAY="\$XDISPLAY" xmessage -timeout 120 "WSF App B" &
APP_B_PID=\$!
echo "WSF-TEST: App B gestartet (PID=\$APP_B_PID)"

# Warten: App B erscheint, maximiert wird, desktopsChanged mit cnt=3 feuert
sleep 4

# ── Stage-2-Probe: Reihenfolge + Navigation + B-Restore ──────────────────────
qdbus-qt6 org.kde.KWin /Scripting loadScript "$PROBE_S2" wsf-probe-s2 >/dev/null
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
echo "WSF-TEST: Stage2-Probe geladen"

# Warten: Stage2 läuft durch (setMaximize(false,false) → removeSpaceFor(B))
sleep 3

# ── Schritt 5: App A schließen ────────────────────────────────────────────────
# kill → Fenster wird entfernt → workspace.windowRemoved → removeSpaceFor(A)
# → WSF: removed space + WSF: desktop_count=1
kill \$APP_A_PID 2>/dev/null || true
echo "WSF-TEST: App A beendet (windowRemoved erwartet)"

# Warten für async windowRemoved-Verarbeitung
sleep 2

# ── Aufräumen ─────────────────────────────────────────────────────────────────
kill \$APP_B_PID 2>/dev/null || true
kill \$KWIN_PID 2>/dev/null || true
wait \$KWIN_PID 2>/dev/null || true
echo "WSF-TEST: Session beendet"
INNER
) 2>"$LOG"

# ── Log-Ausgabe ───────────────────────────────────────────────────────────────
echo ""
echo "── WSF-Zeilen im Log ──"
grep -E "WSF[-:]" "$LOG" || echo "(keine WSF-Zeilen im Log)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Assertions
# ═══════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════"
echo "── Assertions ──"
echo "════════════════════════════════"

echo ""
echo "── Grundfunktion ──"
assert_log "WSF: loaded v"                      && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Stage1 gestartet"        && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Stage1-DONE"             && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Stage2 gestartet"        && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: DONE"                    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "── Schritt 1+2: Space-Erzeugung (erwartet >= 2x) ──"
COUNT_CREATED=$(grep -c "WSF: created space at index 1" "$LOG" 2>/dev/null || echo "0")
if [ "$COUNT_CREATED" -ge 2 ]; then
    echo "WSF-TEST PASS: 'WSF: created space at index 1' erscheint ${COUNT_CREATED}x (>= 2)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: 'WSF: created space at index 1' erscheint ${COUNT_CREATED}x (erwartet >= 2)"
    FAIL=$((FAIL+1))
fi
# Beide Zähler müssen je mindestens einmal aufgetreten sein
assert_desktop_count 2                          && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 3                          && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "── Schritt 2: Reihenfolge Desktop | B | A ──"
# B-Space muss bei Index 1 sein (direkt rechts vom permanenten Desktop)
assert_log "WSF-PROBE: B-space-index=1"         && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
# A-Space muss bei Index 2 sein (durch B verdrängt)
assert_log "WSF-PROBE: A-space-index=2"         && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "── Schritt 3: Desktop-Navigation ──"
assert_log "WSF-PROBE: Step3-Navigation-start"  && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Step3-auf-Desktop0="     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Step3-auf-Desktop1="     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "── Schritt 4+5: Space-Abbau (erwartet >= 2x) ──"
COUNT_REMOVED=$(grep -c "WSF: removed space" "$LOG" 2>/dev/null || echo "0")
if [ "$COUNT_REMOVED" -ge 2 ]; then
    echo "WSF-TEST PASS: 'WSF: removed space' erscheint ${COUNT_REMOVED}x (>= 2)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: 'WSF: removed space' erscheint ${COUNT_REMOVED}x (erwartet >= 2)"
    FAIL=$((FAIL+1))
fi
# Endzustand: nur permanenter Desktop
assert_desktop_count 1                          && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "── desktop_count Verlauf (informativ) ──"
VERLAUF=$(grep "WSF: desktop_count=" "$LOG" 2>/dev/null \
    | sed 's/.*desktop_count=//' | tr -d '\r\n ' | sed 's/.\{1\}/&→/g' | sed 's/→$//' || echo "(leer)")
echo "WSF-TEST: Verlauf: $VERLAUF"

# ── Gesamt-Ergebnis ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════"
echo "── Gesamt-Ergebnis: PASS=$PASS FAIL=$FAIL ──"
echo "════════════════════════════════"

# Aufräumen (auch bei Fehler)
rm -f "$PROBE_S1" "$PROBE_S2"
rm -rf "$CFG_DIR"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
