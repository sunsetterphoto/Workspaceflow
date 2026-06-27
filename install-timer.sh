#!/usr/bin/env bash
# install-timer.sh — Workspaceflow Auto-Update-Timer einrichten (kein sudo)
#
# Kopiert die systemd-User-Units nach ~/.config/systemd/user/ (KEIN Symlink —
# Fedora/SELinux erlaubt keine Unit-Symlinks aus /home heraus).
# Aktiviert den Timer sofort.

set -euo pipefail
cd "$(dirname "$0")"

UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"

# Units KOPIEREN (nicht symlinken — SELinux/Fedora)
cp systemd/workspaceflow-update.service "$UNIT_DIR/"
cp systemd/workspaceflow-update.timer   "$UNIT_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now workspaceflow-update.timer
echo "Workspaceflow: Auto-Update-Timer aktiv."
