# Workspaceflow

macOS-artige dynamische Arbeitsflächen für KDE Plasma 6.7 / KWin 6.7 (Wayland).

## Verhalten

Workspaceflow ist ein KWin-Skript, das virtuelle Desktops automatisch erzeugt und wieder abbaut:

- **Maximieren** eines Fensters → neuer virtueller Desktop direkt rechts neben dem permanenten Desktop 0, das Fenster wird dorthin verschoben, der Fokus folgt.  
  Reihenfolge: `Desktop | NEU | …`
- **Wiederherstellen** (Maximierung aufheben) **oder Schließen** des Fensters → Space wird aufgelöst, Fenster kehrt auf Desktop 0 zurück.
- Der permanente Desktop 0 bleibt immer an erster Position.

## Navigation / Gesten

| Geste | Wirkung |
|---|---|
| 3 Finger links/rechts (Touchpad) | Zwischen Desktop und Spaces blättern |
| 3 Finger hoch (Touchpad) | Overview aller Flächen öffnen |

Die 3-Finger-Wischgeste nach oben für den Overview ist **in KWin 6 fest eingebaut** (`addTouchpadSwipeGesture` in der OverviewEffect-Klasse). `install.sh` setzt `overviewEnabled=true`, wodurch die Geste automatisch aktiv ist — kein manueller Konfigurationsschritt in den Systemeinstellungen erforderlich, solange der Effekt nicht zuvor deaktiviert wurde.

## Installation

```bash
git clone https://github.com/sunsetterphoto/Workspaceflow
cd Workspaceflow
./install.sh
```

Kein `sudo` erforderlich. Das Skript ist idempotent (wiederholtes Ausführen sicher).

`install.sh` führt folgende Schritte aus:

1. Installiert das KWin-Skript-Paket via `kpackagetool6` (Update bei bereits vorhandener Installation).
2. Aktiviert das Skript in `~/.config/kwinrc` (`workspaceflowEnabled=true`).
3. Setzt `overviewEnabled=true` (stellt Overview-Geste sicher).
4. Ruft `qdbus6`/`gdbus` auf, damit KWin die neue Konfiguration sofort einliest.
5. Richtet den Auto-Update-Timer ein (s. u.).

## Deinstallation

```bash
./uninstall.sh
```

Deaktiviert das Skript, entfernt das Paket und stoppt den Auto-Update-Timer.

## Auto-Update

`install.sh` ruft `install-timer.sh` auf, der einen systemd-User-Timer einrichtet:

- **Zeitplan**: täglich (`OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=1h`)
- **Aktion**: `git pull --ff-only` im Projektverzeichnis, danach `install.sh`
- **Voraussetzung**: Das Repository muss unter `~/Schreibtisch/PublicGitHub/Workspaceflow` ausgecheckt sein (Pfad der systemd-Unit).

Die Units werden nach `~/.config/systemd/user/` **kopiert** (kein Symlink — Fedora/SELinux-Kompatibilität).

## Konfiguration — Ignorier-Liste

Fensterklassen, die keinen eigenen Space erhalten sollen, werden in `~/.config/kwinrc` eingetragen:

```ini
[Script-workspaceflow]
IgnoreClasses=firefox,Xmessage
```

Komma- oder zeilengetrennte Einträge sind möglich. KWin muss danach neu konfiguriert werden:

```bash
qdbus6 org.kde.KWin /KWin reconfigure
```

**Hinweis (Config-UI):** Eine Settings-Dialog-UI ist beigelegt (`contents/config/`), aber die Bindung des KDE-Einstellungsdialogs an die korrekte kwinrc-Sektion `[Script-workspaceflow]` ist noch nicht abschließend verifiziert. Um selbst zu prüfen: *System Settings → KWin Scripts → Workspaceflow → Configure* aufrufen, einen Wert eintragen, speichern, dann `kreadconfig6 --file kwinrc --group Script-workspaceflow --key IgnoreClasses` prüfen. Der direkte kwinrc-Weg oben ist in jedem Fall der gesicherte Pfad.

## Bekannte Grenzen

**Multi-Monitor:** Virtuelle Desktops spannen in Plasma alle angeschlossenen Monitore. Ein per-Monitor-Space (wie bei macOS Spaces im „Displays have separate Spaces"-Modus) ist mit der KWin-API nicht realisierbar.

**Bereits maximiert gestartete Fenster:** Fenster, die beim Start schon im maximierten Zustand erscheinen, feuern kein `maximizedChanged`-Signal und bekommen daher keinen eigenen Space. Einmal kurz wiederherstellen und erneut maximieren erzeugt den Space wie gewohnt. (Bewusste v0.1-Entscheidung — ein Startup-Scan wäre möglich, ist aber nicht implementiert.)

## Live-Aktivierung

Tests laufen ausschließlich in einer **isolierten** nested KWin-Session mit eigenem D-Bus und eigenem `XDG_CONFIG_HOME` (damit die Live-`~/.config/kwinrc` unberührt bleibt). Das Test-Harness in `test/` startet diese Session automatisch:

```bash
# Alle Tests in isolierter nested Session ausführen:
./test/task-9-e2e.sh        # End-to-End-Vollszenario
./test/invariant-desktop0.sh  # Desktop-0-Identitäts-Invariante
```

Intern nutzt jedes Testskript das Muster:
```bash
dbus-run-session -- bash -c "kwin_wayland --virtual --xwayland ... &"
```

Nach erfolgreichem Abschluss aller Tests live aktivieren:

```bash
./install.sh
```

## Plattform

- KDE Plasma 6.7 / KWin 6.7
- Wayland
- Keine Abhängigkeiten außer den KDE-Standardwerkzeugen (`kpackagetool6`, `kwriteconfig6`, `qdbus6` bzw. `qdbus-qt6` als Fallback)

## Lizenz

MIT — siehe [LICENSE](LICENSE).
