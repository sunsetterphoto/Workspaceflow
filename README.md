# Workspaceflow

**macOS-artige dynamische Arbeitsflächen für KDE Plasma 6 (Wayland).**

Maximiere ein Fenster — es wandert auf eine eigene, automatisch erzeugte
Arbeitsfläche rechts neben deinem Desktop. Stelle es wiederher oder schließe es —
die Arbeitsfläche verschwindet wieder. Wie „Spaces" auf dem Mac, nur für KWin.

Workspaceflow ist ein reines KWin-Skript: kein Daemon, keine Fremd­abhängigkeiten,
kein `sudo`.

---

## Verhalten

- **Maximieren** eines Fensters → ein neuer virtueller Desktop entsteht direkt
  rechts neben dem permanenten Desktop, das Fenster wandert dorthin, der Fokus
  folgt. Reihenfolge: `Desktop │ neuestes │ … │ ältestes`.
- **Wiederherstellen** (Maximierung aufheben) **oder Schließen** → die
  Arbeitsfläche löst sich auf, das Fenster kehrt auf den permanenten Desktop
  zurück, die übrigen rücken nach.
- Der **permanente Desktop bleibt immer ganz links** und wird nie entfernt.

Nicht-maximierte Fenster leben alle zusammen auf dem permanenten Desktop — wie
gewohnt.

## Gesten

| Geste (Touchpad) | Wirkung |
|---|---|
| **3 Finger links/rechts** | Zwischen Desktop und Arbeitsflächen blättern |
| **4 Finger hoch** | Übersicht aller Flächen öffnen (Overview) |

> **Warum 4 Finger für die Übersicht?** Die Fingeranzahl dieser Gesten ist in
> KWin 6 **fest im Compositor verdrahtet** und nicht über die Konfiguration
> änderbar: Desktop-Wechsel = 3 Finger horizontal, Overview = 4 Finger hoch.
> Workspaceflow nutzt diese eingebauten Gesten unverändert (das ist auch nah an
> macOS, wo viele System­gesten 4-Finger sind). `install.sh` stellt nur sicher,
> dass der Overview-Effekt aktiv ist (`overviewEnabled=true`) — damit ist die
> 4-Finger-Geste ohne weiteren Schritt nutzbar.
>
> Eine Umlegung auf 3 Finger hoch wäre nur über einen externen Gesten-Daemon
> (z. B. `libinput-gestures`) möglich und wurde bewusst nicht aufgenommen, um
> Workspaceflow abhängigkeitsfrei und wartungsarm zu halten.

Alternativ öffnet **`Meta`+`W`** die Übersicht per Tastatur.

## Voraussetzungen

- KDE Plasma 6 / KWin 6 auf **Wayland** (entwickelt und getestet auf 6.7)
- KDE-Standardwerkzeuge: `kpackagetool6`, `kwriteconfig6`/`kreadconfig6`,
  `qdbus6` (oder `qdbus-qt6` als Fallback)

Keine weiteren Abhängigkeiten.

## Installation

```bash
git clone https://github.com/sunsetterphoto/Workspaceflow
cd Workspaceflow
./install.sh
```

Kein `sudo` nötig, idempotent (mehrfaches Ausführen ist sicher). `install.sh`:

1. installiert das KWin-Skript-Paket nach `~/.local/share/kwin/scripts/workspaceflow`,
2. aktiviert es in `~/.config/kwinrc` (`workspaceflowEnabled=true`),
3. stellt den Overview-Effekt sicher (`overviewEnabled=true`),
4. lädt die KWin-Konfiguration neu (sofort aktiv, kein Logout nötig),
5. richtet den optionalen Auto-Update-Timer ein (s. u.).

### Empfehlung: ein Basis-Desktop

Den saubersten „macOS-Flow" bekommst du mit **einem** permanenten virtuellen
Desktop — dann erzeugt jedes Maximieren genau eine Arbeitsfläche daneben.
Einstellbar unter *Systemeinstellungen → Fensterverwaltung → Virtuelle
Arbeitsflächen* (Anzahl auf 1). Mehrere feste Desktops funktionieren auch, die
dynamischen Flächen mischen sich dann aber zwischen sie.

## Deinstallation

```bash
./uninstall.sh
```

Deaktiviert das Skript, entfernt das Paket und den Auto-Update-Timer. Deine
übrigen KDE-Einstellungen bleiben unberührt.

## Konfiguration — Ignorier-Liste

Fensterklassen, die **keine** eigene Arbeitsfläche bekommen sollen (z. B. Apps,
die du lieber auf dem Hauptdesktop behältst), trägst du in `~/.config/kwinrc`
ein:

```ini
[Script-workspaceflow]
IgnoreClasses=firefox,Xmessage
```

Komma- oder zeilengetrennt. Danach KWin neu konfigurieren:

```bash
qdbus6 org.kde.KWin /KWin reconfigure   # oder qdbus-qt6
```

Die Fensterklasse einer App findest du mit `qdbus6 org.kde.KWin /KWin
queryWindowInfo` (anklicken) oder über `xprop WM_CLASS`.

> **Hinweis:** Eine grafische Settings-UI liegt bei (`contents/config/`), die
> Bindung des KDE-Einstellungsdialogs an die korrekte kwinrc-Sektion ist aber
> noch nicht abschließend verifiziert. Der direkte kwinrc-Weg oben ist der
> gesicherte.

## Persistenz & Updates

Workspaceflow lebt vollständig im Benutzerbereich
(`~/.local/share/kwin/scripts/` und `~/.config/kwinrc`). **System- und
Plasma-Updates überschreiben diese Dateien nicht.** Die genutzte 4-Finger-Geste
ist KWins eingebauter Standard und bleibt über Updates erhalten.

Sollte ein Update jemals den Overview-Effekt deaktivieren, stellt der nächste
Lauf von `install.sh` (`overviewEnabled=true`) ihn wieder her — der
Auto-Update-Timer macht das automatisch.

## Auto-Update

`install.sh` richtet einen systemd-**User**-Timer ein, der Workspaceflow
selbst aktuell hält und die Einstellungen selbstheilend wieder anwendet:

- **Zeitplan:** täglich (`OnCalendar=daily`, `Persistent=true`,
  `RandomizedDelaySec=1h`)
- **Aktion:** `git pull --ff-only` im Projektverzeichnis, danach `install.sh`
- **Voraussetzung:** Repo unter `~/Schreibtisch/PublicGitHub/Workspaceflow`
  ausgecheckt (Pfad der systemd-Unit)

Die Units werden nach `~/.config/systemd/user/` **kopiert** (kein Symlink —
Fedora/SELinux-kompatibel). Abschalten jederzeit mit
`systemctl --user disable --now workspaceflow-update.timer`.

## Bekannte Grenzen

- **Multi-Monitor:** Virtuelle Desktops spannen in Plasma alle Monitore; ein
  per-Monitor-Space (wie macOS im „Displays have separate Spaces"-Modus) ist mit
  der KWin-API nicht möglich.
- **Bereits maximiert gestartete Fenster** feuern kein `maximizedChanged`-Signal
  und bekommen keinen eigenen Space. Einmal wiederherstellen und neu maximieren
  erzeugt ihn. (Bewusste v0.1-Entscheidung.)

## Entwicklung & Tests

Die Tests laufen **ausschließlich in einer isolierten, verschachtelten
KWin-Session** mit eigenem D-Bus und eigenem `XDG_CONFIG_HOME` — die laufende
Live-Sitzung wird dabei nie berührt:

```bash
./test/task-9-e2e.sh          # End-to-End-Vollszenario
./test/invariant-desktop0.sh  # permanenter Desktop bleibt stabil
```

Die Skripte starten KWin über
`dbus-run-session -- kwin_wayland --virtual --xwayland …` und prüfen das
Verhalten gegen das echte Skript-Log.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
