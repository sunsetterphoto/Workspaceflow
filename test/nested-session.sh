#!/usr/bin/env bash
# Startet eine isolierte nested KWin-Wayland-Session mit eigenem Session-Bus.
# NIEMALS gegen die Live-Session laufen lassen.
#
# Verwendung:
#   ./test/nested-session.sh [SESSION-KOMMANDO...]
#
# Die nested KWin-Instanz bekommt einen eigenen D-Bus-Session-Bus via
# dbus-run-session, sodass org.kde.KWin auf diesem Bus registriert wird
# und NIEMALS der Live-Desktop berührt wird.
#
# Logging-Hinweis: KWin-Skript-print() geht an die Qt-Kategorie "js".
# Um WSF-PROBE:-Zeilen zu sehen:
#   export QT_LOGGING_RULES="js.debug=true;js=true"
#   export QT_FORCE_STDERR_LOGGING=1
set -euo pipefail

# KWin-Skript-print() -> Qt-Kategorie "js" -> sichtbar mit:
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-js.debug=true;js=true}"
export QT_FORCE_STDERR_LOGGING=1

echo "WSF-TEST: starte nested KWin --virtual (eigener Session-Bus)"
exec dbus-run-session -- kwin_wayland \
  --virtual \
  --xwayland \
  --no-lockscreen \
  --no-global-shortcuts \
  --no-kactivities \
  "${@:-sleep 3}"
