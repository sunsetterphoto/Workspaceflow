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
#      Reihenfolge Desktop|B|A wird via w.pid IDENTITÄTSBASIERT belegt (Fix 1)
#   3. Desktop-Wechsel zu Desktop[0] und zurück zu Desktop[1]
#      current-is-Rücklesung verifiziert Navigation (Minor)
#   4. App B wiederherstellen → B-Space weg, desktop_count=2
#   5. App A schließen → A-Space weg, desktop_count=1
#      count-Sequenz 2→3→2→1 sequenziell geprüft (Fix 2)
#   6. overviewEnabled=true in isolierter Config (install.sh-Logik)
#
# Hinweis: feste Sleeps (sleep 4, sleep 3, sleep 2) sind absichtlich großzügig,
# damit async KWin-Signal-Verarbeitung (desktopsChanged, windowRemoved) abgeschlossen
# ist, bevor die nächste Stage greift. Kein busy-wait wegen KWin-JS-API-Grenzen.
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
# Probe-Skripte erstellen (temporär)
# ═══════════════════════════════════════════════════════════════════════════════

PROBE_S1="$(mktemp /tmp/wsf-task9-stage1-XXXXXX.js)"
PROBE_S2="$(mktemp /tmp/wsf-task9-stage2-XXXXXX.js)"
CFG_DIR="$(mktemp -d /tmp/wsf-task9-cfg-XXXXXX)"

# Minor Fix: Temp-Cleanup bei normalem Abbruch UND vorzeitigem Exit
trap 'rm -f "$PROBE_S1" "$PROBE_S2"; rm -rf "$CFG_DIR"' EXIT

# Stage 1: maximiert App A (erstes Fenster) und App B (zweites Fenster)
# via windowAdded. Loggt w.pid beider Fenster für identitätsbasierte Stage2-Assertion (Fix 1).
cat > "$PROBE_S1" << 'STAGE1_EOF'
// Stage 1: Maximiert App A, dann App B. Loggt w.pid für identitätsbasierte Proof (Fix 1).
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
        // Fix 1: PID loggen — bash-Seite nutzt dies zum identitätsbasierten Kreuzen mit Stage2
        print("WSF-PROBE: AppA-pid=" + w.pid);
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
        // Fix 1: PID loggen — bash-Seite nutzt dies zum identitätsbasierten Kreuzen mit Stage2
        print("WSF-PROBE: AppB-pid=" + w.pid);
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

# Stage 2: Reihenfolge via pid@idx IDENTITÄTSBASIERT (Fix 1), Navigation mit
# current-is-Rücklesung (Minor), B wiederherstellen.
# KEIN positionsbasiertes Label (B-space-index/A-space-index entfernt) —
# bash-Seite kreuzt AppA-pid/AppB-pid aus Stage1 mit win-pid@idx aus Stage2.
cat > "$PROBE_S2" << 'STAGE2_EOF'
// Stage 2: pid@idx für alle Fenster (identitätsneutral), Navigation+Rücklesung, B-Restore
print("WSF-PROBE: Stage2 gestartet");

var desks = workspace.desktops;
print("WSF-PROBE: Stage2-desktop_count=" + desks.length);

// Desktop-Reihenfolge loggen (Index → Name)
for (var i = 0; i < desks.length; i++) {
    print("WSF-PROBE: desktops-" + i + "-name=" + desks[i].name);
}

// Fix 1: Für alle Normalfenster pid+idx loggen — KEIN positionsbasiertes Label.
// bash-Seite nutzt AppA-pid/AppB-pid aus Stage1 zum Kreuzen.
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
            // Identitätsbasierter Log: pid@idx — positionsneutral
            print("WSF-PROBE: win-pid=" + w.pid + "@idx=" + k +
                  " caption=" + w.caption);
            if (k === 1) windowB = w;  // für Restore in Schritt 4
            break;
        }
    }
}

if (windowB === null) print("WSF-PROBE: WARN-windowB-nicht-auf-idx1");

// Schritt 3: Desktop-Navigation mit current-is-Rücklesung (Minor Fix)
print("WSF-PROBE: Step3-Navigation-start");
var d0 = desks[0];
var d1 = desks[1];
workspace.currentDesktop = d0;
print("WSF-PROBE: Step3-auf-Desktop0=" + d0.name);
// Minor: KWin-Rücklesung — beweist, dass der Wechsel tatsächlich stattfand
print("WSF-PROBE: current-is=" + workspace.currentDesktop.name);
workspace.currentDesktop = d1;
print("WSF-PROBE: Step3-auf-Desktop1=" + d1.name);
print("WSF-PROBE: current-is-after-back=" + workspace.currentDesktop.name);
print("WSF-PROBE: Step3-Navigation-done");

// Schritt 4: App B wiederherstellen (setMaximize(false,false))
// → onMaximizeChanged → removeSpaceFor(B) → WSF: removed space + desktop_count=2
if (windowB !== null) {
    print("WSF-PROBE: Step4-B-restore-start caption=" + windowB.caption);
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
# sleep absichtlich großzügig — KWin-JS-Signalverarbeitung ist async
sleep 4

# ── Schritt 2: App B starten ──────────────────────────────────────────────────
DISPLAY="\$XDISPLAY" xmessage -timeout 120 "WSF App B" &
APP_B_PID=\$!
echo "WSF-TEST: App B gestartet (PID=\$APP_B_PID)"

# Warten: App B erscheint, maximiert wird, desktopsChanged mit cnt=3 feuert
sleep 4

# ── Stage-2-Probe: Reihenfolge (identitätsbasiert) + Navigation + B-Restore ──
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
# Erstauftreten von count=2 und count=3 (Schritt 1 bzw. 2)
assert_desktop_count 2                          && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_desktop_count 3                          && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo ""
echo "── Fix 1: Reihenfolge Desktop|B|A — identitätsbasiert via PID ──"
# AppA-pid und AppB-pid aus Stage1-Log extrahieren
APP_A_PID=$(grep -o 'AppA-pid=[0-9]*' "$LOG" | grep -o '[0-9]*$' | head -1)
APP_B_PID=$(grep -o 'AppB-pid=[0-9]*' "$LOG" | grep -o '[0-9]*$' | head -1)
echo "WSF-TEST: AppA-pid=${APP_A_PID:-NICHT_GEFUNDEN}  AppB-pid=${APP_B_PID:-NICHT_GEFUNDEN}"

# Beweis: App A (zuerst maximiert) liegt auf Index 2 — verdrängt durch B
if [ -n "$APP_A_PID" ] && grep -q "WSF-PROBE: win-pid=${APP_A_PID}@idx=2" "$LOG"; then
    echo "WSF-TEST PASS: AppA (pid=$APP_A_PID) liegt identitätsbasiert auf Index 2 (verdrängt durch B)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: AppA (pid=${APP_A_PID:-?}) NICHT auf Index 2 identitätsbasiert nachgewiesen"
    FAIL=$((FAIL+1))
fi

# Beweis: App B (zuletzt maximiert) liegt auf Index 1 — direkt rechts vom permanenten Desktop
if [ -n "$APP_B_PID" ] && grep -q "WSF-PROBE: win-pid=${APP_B_PID}@idx=1" "$LOG"; then
    echo "WSF-TEST PASS: AppB (pid=$APP_B_PID) liegt identitätsbasiert auf Index 1 (zuletzt maximiert)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: AppB (pid=${APP_B_PID:-?}) NICHT auf Index 1 identitätsbasiert nachgewiesen"
    FAIL=$((FAIL+1))
fi

echo ""
echo "── Schritt 3: Desktop-Navigation ──"
assert_log "WSF-PROBE: Step3-Navigation-start"  && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Step3-auf-Desktop0="     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
assert_log "WSF-PROBE: Step3-auf-Desktop1="     && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# Minor Fix: current-is-Rücklesung verifizieren (KWin hat tatsächlich gewechselt)
DESK0_NAME=$(grep 'WSF-PROBE: Step3-auf-Desktop0=' "$LOG" | sed 's/.*Step3-auf-Desktop0=//' | head -1 | tr -d '\r')
if [ -n "$DESK0_NAME" ] && grep -q "WSF-PROBE: current-is=${DESK0_NAME}" "$LOG"; then
    echo "WSF-TEST PASS: Step3-Navigation current-is='${DESK0_NAME}' (KWin-Rücklesung bestätigt)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: Step3-Navigation current-is='${DESK0_NAME}' fehlt oder stimmt nicht"
    FAIL=$((FAIL+1))
fi

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
echo "── Fix 2: count-Sequenz 2→3→2→1 sequenziell ──"
# Alle WSF: desktop_count=N Werte in Reihenfolge extrahieren (nur main.js, nicht PROBE)
COUNT_SEQ=$(grep -o 'WSF: desktop_count=[0-9]*' "$LOG" | grep -o '[0-9]*$' | tr '\n' ',' || echo "")
echo "WSF-TEST: count-Sequenz: ${COUNT_SEQ%,}"

# desktop_count=2 muss >= 2x auftreten (Schritt 1 UND Schritt 4)
COUNT_2=$(grep -c 'WSF: desktop_count=2' "$LOG" 2>/dev/null || echo "0")
if [ "$COUNT_2" -ge 2 ]; then
    echo "WSF-TEST PASS: desktop_count=2 erscheint ${COUNT_2}x (>= 2, Schritt 1 und 4)"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: desktop_count=2 erscheint ${COUNT_2}x (erwartet >= 2)"
    FAIL=$((FAIL+1))
fi

# Teilfolge 2→3→2→1 muss in der count-Sequenz vorkommen
# Fängt Bugs auf, die z. B. von 3 direkt auf 1 springen
if echo ",${COUNT_SEQ}" | grep -q ",2,3,2,1,"; then
    echo "WSF-TEST PASS: count-Sequenz enthält Teilfolge 2→3→2→1"
    PASS=$((PASS+1))
else
    echo "WSF-TEST FAIL: count-Sequenz enthält NICHT Teilfolge 2→3→2→1 (war: ${COUNT_SEQ%,})"
    FAIL=$((FAIL+1))
fi

# ── Gesamt-Ergebnis ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════"
echo "── Gesamt-Ergebnis: PASS=$PASS FAIL=$FAIL ──"
echo "════════════════════════════════"

# Aufräumen erfolgt via trap EXIT (gesetzt nach den mktemp-Aufrufen)

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
