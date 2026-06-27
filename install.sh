#!/usr/bin/env bash
# install.sh — Workspaceflow KWin-Skript installieren (idempotent, kein sudo)
#
# Geste-Hinweis:
#   Die 3-Finger-Wischgeste nach oben für den Overview-Effekt ist in KWin 6
#   FEST EINGEBAUT (via addTouchpadSwipeGesture in der OverviewEffect-Klasse).
#   Es gibt KEINEN kwinrc-Key dafür — der Effekt aktiviert die Geste automatisch,
#   sobald overviewEnabled=true gilt (was der Default ist). Kein manueller Schritt
#   in System Settings nötig, solange der Effekt nicht deaktiviert wurde.
#
# Umgebungsvariablen (für Tests):
#   XDG_CONFIG_HOME   — Pfad zur Test-kwinrc statt ~/.config
#   XDG_DATA_HOME     — Pfad für kpackagetool6-Datenpfad statt ~/.local/share

set -euo pipefail
cd "$(dirname "$0")"

SCRIPT_NAME="workspaceflow"

echo "Workspaceflow: installiere KWin-Skript…"

# ── 1. Paket installieren oder aktualisieren ───────────────────────────────
# Robuste Idempotenz via Verzeichnisprüfung: kpackagetool6 --list/--show/--upgrade
# haben im isolierten XDG_DATA_HOME-Modus Inkonsistenzen; die Verzeichnislösung
# funktioniert zuverlässig in Live- und Testumgebung.
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/${SCRIPT_NAME}"
if [ -d "$DATA_DIR" ]; then
    echo "Workspaceflow: vorhandene Installation gefunden – aktualisiere."
    rm -rf "$DATA_DIR"
else
    echo "Workspaceflow: Erstinstallation."
fi
kpackagetool6 --type KWin/Script --install .

# ── 2. Skript in kwinrc aktivieren ─────────────────────────────────────────
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_NAME}Enabled" true

# ── 3. Overview-Effekt sicherstellen ──────────────────────────────────────
# Der Overview-Effekt ist EnabledByDefault=true. Falls er manuell deaktiviert
# wurde, reaktivieren wir ihn hier, damit die eingebaute 3-Finger-Geste
# (hardcoded in KWin via addTouchpadSwipeGesture) wieder funktioniert.
kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true

# ── 4. KWin neu konfigurieren ─────────────────────────────────────────────
# Fehler werden toleriert: Im Test-Kontext ohne D-Bus läuft dies sauber durch.
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null \
    || qdbus-qt6 org.kde.KWin /KWin reconfigure 2>/dev/null \
    || gdbus call --session -d org.kde.KWin -o /KWin \
         -m org.kde.KWin.reconfigure 2>/dev/null \
    || true

echo "Workspaceflow: aktiv."
echo "Info: 3-Finger-Wischgeste nach oben → Overview ist in KWin 6 eingebaut"
echo "      (kein Extra-Config-Key nötig, overviewEnabled=true gesetzt)."

# ── 5. Auto-Update-Timer (Task 7, optional) ───────────────────────────────
./install-timer.sh 2>/dev/null || true
