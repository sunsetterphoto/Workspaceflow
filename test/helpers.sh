#!/usr/bin/env bash
# WSF Testhelfer – Assertions gegen das KWin-Log der nested Session.
#
# Verwendung:
#   source test/helpers.sh
#   LOG=/pfad/zum/kwin-log.txt
#   assert_log "WSF-PROBE: DONE"
#   assert_desktop_count 2
#
# Alle Funktionen geben 0 bei Erfolg, 1 bei Fehler zurück.
# Ausgabe-Präfix: WSF-TEST PASS / WSF-TEST FAIL

set -euo pipefail

# ── Basisfunktionen ──────────────────────────────────────────────────────────

# assert_log <regex>
# Prueft ob <regex> im LOG vorkommt (extended-regex, grep -qE).
assert_log() {
    local pat="$1"
    if grep -qE "$pat" "${LOG:?LOG nicht gesetzt}"; then
        echo "WSF-TEST PASS: /$pat/ gefunden"
    else
        echo "WSF-TEST FAIL: /$pat/ NICHT gefunden"
        return 1
    fi
}

# assert_log_not <regex>
# Prueft ob <regex> im LOG NICHT vorkommt.
assert_log_not() {
    local pat="$1"
    if grep -qE "$pat" "${LOG:?LOG nicht gesetzt}"; then
        echo "WSF-TEST FAIL: /$pat/ sollte NICHT vorkommen, aber gefunden"
        return 1
    else
        echo "WSF-TEST PASS: /$pat/ korrekt abwesend"
    fi
}

# assert_desktop_count <anzahl>
# Prueft ob "WSF: desktop_count=<anzahl>" im LOG vorkommt.
assert_desktop_count() {
    local want="$1"
    if grep -qE "WSF: desktop_count=$want" "${LOG:?}"; then
        echo "WSF-TEST PASS: desktop_count=$want"
    else
        echo "WSF-TEST FAIL: desktop_count=$want erwartet"
        return 1
    fi
}

# assert_probe_done
# Prueft ob die Probe vollstaendig durchgelaufen ist.
assert_probe_done() {
    assert_log "WSF-PROBE: DONE"
}

# assert_api_available <symbol>
# Prueft ob "WSF-PROBE: <symbol> type = function" oder "typeof <symbol> = function"
# im LOG vorkommt.
assert_api_available() {
    local sym="$1"
    if grep -qE "WSF-PROBE: .*${sym}.*function" "${LOG:?}"; then
        echo "WSF-TEST PASS: API $sym verfuegbar"
    else
        echo "WSF-TEST FAIL: API $sym NICHT als function bestaetigt"
        return 1
    fi
}

# ── Hilfsfunktionen ──────────────────────────────────────────────────────────

# run_probe <probe_js_path> [timeout_sek]
# Startet eine nested KWin-Session, ladet das Probe-Skript, und schreibt
# das Log nach $LOG (Standard: /tmp/wsf-probe-$$.log).
# Gibt Rueckgabewert 0 wenn WSF-PROBE: DONE im Log erscheint.
run_probe() {
    local probe_js="${1:?probe_js Pfad fehlt}"
    local timeout_sek="${2:-30}"
    LOG="${LOG:-/tmp/wsf-probe-$$.log}"
    local bus_ready_tries=20

    (
        # KWin-Skript-print() loggt zur Qt-Kategorie "js", NICHT "kwin_scripting"
        export QT_LOGGING_RULES="js.debug=true;js=true"
        export QT_FORCE_STDERR_LOGGING=1

        dbus-run-session -- bash -c "
            # QT_LOGGING_RULES erbt aus der Eltern-Shell
            # KWin im Hintergrund starten (virtual = kein echter Display noetig)
            kwin_wayland --virtual --xwayland --no-lockscreen --no-global-shortcuts --no-kactivities &
            KWIN_PID=\$!

            # Warten bis org.kde.KWin auf dem Bus erscheint
            for i in \$(seq 1 $bus_ready_tries); do
                qdbus-qt6 org.kde.KWin /Scripting > /dev/null 2>&1 && break
                sleep 0.5
            done

            # Probe laden und starten
            qdbus-qt6 org.kde.KWin /Scripting loadScript '$probe_js' wsf-probe > /dev/null
            qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start > /dev/null

            # Probe laufen lassen
            sleep 3

            kill \$KWIN_PID 2>/dev/null || true
            wait \$KWIN_PID 2>/dev/null || true
        "
    ) 2>"$LOG"

    grep -qE "WSF-PROBE: DONE" "$LOG"
}

# show_probe_lines
# Gibt alle WSF-PROBE: Zeilen aus dem LOG aus.
show_probe_lines() {
    grep "WSF-PROBE:" "${LOG:?}" || echo "(keine WSF-PROBE: Zeilen gefunden)"
}
