#!/usr/bin/env bash
# uninstall.sh — Workspaceflow KWin-Skript entfernen (idempotent, kein sudo)
#
# Umgebungsvariablen (für Tests):
#   XDG_CONFIG_HOME   — Pfad zur Test-kwinrc statt ~/.config
#   XDG_DATA_HOME     — Pfad für kpackagetool6-Datenpfad statt ~/.local/share

set -euo pipefail
cd "$(dirname "$0")"

SCRIPT_NAME="workspaceflow"

echo "Workspaceflow: wird entfernt…"

# ── 1. Skript in kwinrc deaktivieren ──────────────────────────────────────
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_NAME}Enabled" false

# ── 2. Paket entfernen ────────────────────────────────────────────────────
# Zuerst über kpackagetool6 (offizieller Weg, Fehler toleriert):
kpackagetool6 --type KWin/Script --remove "${SCRIPT_NAME}" 2>/dev/null || true
# Als Fallback Verzeichnis direkt löschen (kpackagetool6 --remove scheitert
# manchmal bei lokal installierten Paketen, obwohl das Verzeichnis existiert):
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/${SCRIPT_NAME}"
rm -rf "$DATA_DIR" 2>/dev/null || true

# ── 3. KWin neu konfigurieren ─────────────────────────────────────────────
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null \
    || qdbus-qt6 org.kde.KWin /KWin reconfigure 2>/dev/null \
    || gdbus call --session -d org.kde.KWin -o /KWin \
         -m org.kde.KWin.reconfigure 2>/dev/null \
    || true

# ── 4. Auto-Update-Timer (Task 7, optional) ───────────────────────────────
systemctl --user disable --now workspaceflow-update.timer 2>/dev/null || true

echo "Workspaceflow: entfernt."
