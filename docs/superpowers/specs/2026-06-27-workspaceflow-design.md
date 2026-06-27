# Workspaceflow — Design-Spec

**Datum:** 2026-06-27
**Status:** freigegeben (Design), bereit für Implementierungsplan
**Ablage:** `~/Schreibtisch/PublicGitHub/Workspaceflow`, später öffentlich auf `github.com/sunsetterphoto`

## Ziel

macOS-artiger „Spaces"-Workflow für KDE Plasma 6.7 (Wayland): Der Hauptdesktop
bleibt immer ganz links. Maximiert man ein Fenster, wandert es auf eine
dynamisch erzeugte, eigene Arbeitsfläche rechts daneben. Stellt man es wieder
her oder schließt es, löst sich diese Arbeitsfläche wieder auf. Navigation per
3-Finger-Wisch (links/rechts zwischen Spaces, hoch in eine GNOME-artige
Übersicht).

## Zielumgebung (verifiziert)

- Plasma 6.7.0 / KWin 6.7.0
- Session: Wayland, `XDG_CURRENT_DESKTOP=KDE`
- Aktuell 4 feste virtuelle Desktops (werden durch dynamische Verwaltung ersetzt)
- Keine lokalen KWin-Skripte vorhanden

## Grundmodell

- **Desktop-Index 0** = permanenter „Desktop", ganz links, wird **nie** entfernt.
  Hier leben alle **nicht-maximierten** Fenster.
- Jede **maximierte** App bekommt einen eigenen, dynamisch erzeugten
  **Vollbild-Space** rechts vom Desktop.
- Zustand wird zur Laufzeit gehalten als Mapping **Fenster → sein Space**
  (VirtualDesktop-Objekt).

## Verhalten im Detail

### Auslöser: Maximieren (macOS-grün)
Der Trigger ist das **Maximieren** eines Fensters (nicht echtes F11-Vollbild).
Halb-Snapping/Tiling (halbe Bildschirmbreite) zählt **nicht** als maximiert und
löst nichts aus.

### Space erzeugen
Beim Maximieren:
1. Neuen virtuellen Desktop an **Position 1** erzeugen (direkt rechts neben
   Desktop 0). Bestehende Vollbild-Spaces rücken dadurch nach rechts.
2. Das Fenster auf diesen neuen Space verschieben.
3. Fokus/aktiven Desktop auf den neuen Space schalten.

Resultierende Reihenfolge: `Desktop | NEU | App1 | App2 | …`
(neueste maximierte App immer direkt rechts vom Desktop).

### Space auflösen
Symmetrisch — sobald **eines** von beidem passiert:
- Fenster wird **wiederhergestellt** (Maximierung aufgehoben), **oder**
- Fenster wird **geschlossen**

…dann:
1. Den zugehörigen Vollbild-Space entfernen; restliche Spaces rücken nach.
2. Bei Wiederherstellen: Fenster landet wieder auf Desktop 0.
3. Mapping-Eintrag entfernen.

### Navigation
- **3 Finger links/rechts** → natives Desktop-Umschalten (bestehende Geste,
  bleibt unverändert).
- **3 Finger hoch** → nativer **Overview**-Effekt (Desktop-Raster +
  Fenster-Vorschauen + Suche, GNOME-artig). Wird von `install.sh` an die Geste
  gebunden.

## Architektur (Ansatz A: reines KWin-Skript)

Ein einziges KWin/Script-Paket, keine externen Daemons.

```
Workspaceflow/
├── metadata.json              # KWin/Script-Paketbeschreibung
├── contents/
│   ├── code/
│   │   └── main.js            # Kernlogik
│   └── config/                # optionale Config-UI (Ignorier-Liste)
│       ├── main.xml
│       └── config.ui
├── install.sh                 # paketieren + aktivieren + Geste setzen (ohne sudo)
├── uninstall.sh               # Skript entfernen + Timer abbauen
├── systemd/
│   ├── workspaceflow-update.service
│   └── workspaceflow-update.timer
├── README.md
└── LICENSE
```

### Komponenten

1. **`contents/code/main.js`** — die eigentliche Logik:
   - Event-Handler für Maximier-Statuswechsel pro Fenster.
   - Event-Handler für Fenster-Schließen (`windowRemoved`).
   - Desktop-Erzeugung/-Entfernung über die KWin-`workspace`-API
     (`createDesktop` / `removeDesktop`).
   - In-Memory-Mapping „Fenster ↔ Space".
   - Prüfung gegen die Ignorier-Liste vor dem Space-Erzeugen.

2. **`metadata.json`** — Paket-Metadaten für `kpackagetool6 --type KWin/Script`.

3. **`install.sh` / `uninstall.sh`** (ohne sudo):
   - `kpackagetool6 --type KWin/Script --install/--upgrade .`
   - Skript in `kwinrc` aktivieren (`kwriteconfig6 … Plugins workspaceflowEnabled true`).
   - KWin per D-Bus neu konfigurieren (`org.kde.KWin /KWin reconfigure`).
   - 3-Finger-hoch → Overview-Geste setzen.
   - Auto-Update-Timer installieren/aktivieren bzw. entfernen.

4. **Auto-Update (systemd User-Timer)** — gemäß Low-Maintenance-Prinzip:
   - `workspaceflow-update.timer` triggert periodisch `…-update.service`.
   - Service macht `git pull` im Projektordner + erneutes `install.sh` bei
     Änderungen.
   - Als **User-Unit** (`systemctl --user`), **nicht** auf /home gesymlinkt
     (Fedora/SELinux: System-Units kopieren statt symlinken — hier User-Units,
     gehen direkt).

## Konfiguration

- **Ignorier-Liste** nach Fensterklasse: Apps, die maximiert starten oder nie
  einen eigenen Space bekommen sollen, werden übersprungen. Standard: leer
  bzw. sinnvolle Defaults für bekannte „startet-maximiert"-Apps.

## Bekannte Stolpersteine

- **Maximiert startende Apps** würden je einen Space erzeugen → über
  Ignorier-Liste abfangbar. (Startup-Maximieren ist technisch nicht sicher von
  Nutzer-Maximieren unterscheidbar — daher Klassen-Blacklist statt Heuristik.)
- **Multi-Monitor**: virtuelle Desktops spannen in Plasma alle Schirme. Für v1
  akzeptiert und im README dokumentiert; kein Per-Monitor-Space.
- **Exakte KWin-6.7-API**: Signalnamen für Maximier-Statuswechsel und die
  genaue Form von `createDesktop`/`removeDesktop`/`window.desktops` werden
  **live in der nested Session verifiziert**, bevor sie im Code festgeschrieben
  werden — nicht aus dem Gedächtnis raten.

## Test-Strategie (verbindlich)

- Erprobung **ausschließlich in einer nested KWin-Session**
  (`kwin_wayland` verschachtelt), **niemals** gegen die Live-Session.
  Dynamische Desktop-Manipulation an der laufenden Sitzung ist tabu.
- Manuelle Verifikation der Kernabläufe: maximieren → Space rechts entsteht,
  wiederherstellen/schließen → Space verschwindet, Reihenfolge stimmt,
  Wische funktionieren, Overview öffnet.

## Nicht im Scope (v1, YAGNI)

- Per-Monitor-Spaces.
- Eigene QML-Übersicht (nativer Overview reicht).
- Persistenz der Space-Anordnung über Sitzungen hinweg.
- Tiling / Fensteranordnung innerhalb eines Spaces.
