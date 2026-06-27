# Workspaceflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein KWin-Skript für KDE Plasma 6.7, das macOS-artige dynamische „Spaces" liefert — Maximieren erzeugt eine eigene Arbeitsfläche rechts vom permanenten Desktop, Wiederherstellen/Schließen löst sie wieder auf.

**Architecture:** Reines KWin/Script-Paket (JavaScript, läuft in KWins QJSEngine). Eine Logik-Datei reagiert auf Maximier-Statuswechsel und Fenster-Schließen, verwaltet virtuelle Desktops dynamisch über die `workspace`-API und hält ein In-Memory-Mapping „Fenster → Space". Paketierung/Aktivierung via `kpackagetool6`; native Overview-Geste und Auto-Update-User-Timer über `install.sh`.

**Tech Stack:** KWin 6.7 Scripting API (JavaScript), `kpackagetool6`, `kwriteconfig6`/`kreadconfig6`, D-Bus (`org.kde.KWin /Scripting`), systemd User-Units, Bash.

## Global Constraints

- **Plattform:** KDE Plasma 6.7.0 / KWin 6.7.0, Wayland. Keine Plasma-5-APIs.
- **Tests NUR in nested KWin-Session** (`dbus-run-session kwin_wayland --width … --height …`), **niemals** gegen die Live-Session. Desktop-Manipulation an der laufenden Sitzung ist tabu.
- **`install.sh` / `uninstall.sh` ohne `sudo`.** Alles im User-Scope.
- **Auto-Update via systemd *User*-Timer** (`systemctl --user`), keine Symlinks von Units nach /home (SELinux) — User-Units liegen ohnehin in `~/.config/systemd/user/`, direkt kopieren.
- **Trigger ist *Maximieren* (macOS-grün), nicht echtes F11-Vollbild.**
- **Reihenfolge:** neuer Space immer an Position 1 → `Desktop | NEU | App1 | …`.
- **Auflösen** des Space bei *Wiederherstellen ODER Schließen*.
- **Desktop-Index 0 ist permanent**, wird nie entfernt.
- Git-Identität repo-lokal = `sunsetterphoto <sunsetterphoto@gmail.com>` (bereits gesetzt). Commits **nicht** als Niesau.
- Exakte API-Namen stammen aus Task 1 (Live-Verifikation). Spätere Tasks verwenden die in `API-NOTES.md` bestätigten Namen; weichen sie vom hier angenommenen ab, gilt `API-NOTES.md`.

---

## File Structure

```
Workspaceflow/
├── metadata.json                         # KWin/Script-Paketmetadaten
├── contents/
│   ├── code/
│   │   └── main.js                       # Kernlogik (Event-Handler + Desktop-Verwaltung)
│   └── config/
│       ├── main.xml                       # Config-Schlüssel (Ignorier-Liste)
│       └── config.ui                      # einfache Settings-UI
├── install.sh                            # paketieren + aktivieren + Geste + Timer (ohne sudo)
├── uninstall.sh                          # Skript deaktivieren/entfernen + Timer abbauen
├── systemd/
│   ├── workspaceflow-update.service      # git pull + reinstall
│   └── workspaceflow-update.timer        # periodischer Trigger
├── test/
│   ├── nested-session.sh                 # nested KWin starten + Skript laden
│   ├── probe.js                          # API-Verifikationsskript (Task 1)
│   └── helpers.sh                        # Log-Assert-Funktionen
├── API-NOTES.md                          # bestätigte KWin-6.7-API (Output Task 1)
├── README.md
└── LICENSE
```

**Verantwortlichkeiten:**
- `main.js` — gesamte Laufzeitlogik, eine Datei (Skript ist klein genug; Aufteilen würde QJSEngine-Modulgrenzen erzwingen, die KWin-Skripte nicht sauber unterstützen).
- `install.sh`/`uninstall.sh` — Lifecycle, idempotent.
- `test/*` — Nested-Session-Harness; nie gegen Live-Session.

---

## Teststrategie (für alle Tasks)

KWin-Skripte haben **kein** Jest/Node-Harness. Der Testzyklus ist:

1. **Nested KWin starten** (`test/nested-session.sh`): eigene Session-Bus-Instanz, KWin in einem Fenster.
2. **Skript laden** via `org.kde.KWin /Scripting loadScript`.
3. **Aktion auslösen** (Test-App starten/maximieren via `xdotool` bzw. Skript-internes `print()`).
4. **Assert** auf KWin-Log: das Skript loggt Zustände mit `print("WSF: …")`; Assertion via `journalctl`/Log-Grep auf `WSF:`-Zeilen und Desktop-Anzahl.

`test/helpers.sh` stellt `assert_log "<regex>"` und `assert_desktop_count <n>` bereit. „Test schreiben" heißt hier: die erwartete `WSF:`-Logzeile / Desktop-Anzahl als Assertion festlegen, **bevor** die Logik existiert (sie schlägt fehl), dann implementieren bis sie greift.

---

### Task 1: API-Verifikation (Spike) + Nested-Harness

**Files:**
- Create: `test/nested-session.sh`
- Create: `test/probe.js`
- Create: `test/helpers.sh`
- Create: `API-NOTES.md`

**Interfaces:**
- Produces: `API-NOTES.md` mit bestätigten Namen für: Fenster-Maximier-Signal, `workspace`-Methoden zum Desktop-Erzeugen/-Entfernen, Property „aktueller Desktop", Fenster-Property „liegt auf Desktop(s)", Fenster-schließen-Signal. Diese Namen sind die `Interfaces.Consumes`-Quelle aller folgenden Tasks.

**Angenommene API (KWin 6, wird hier bestätigt oder korrigiert):**
- `workspace.windowList()` → Array von Fenstern; Signale `workspace.windowAdded(window)` / `workspace.windowRemoved(window)`.
- Maximieren: pro Fenster Signal `window.maximizedAboutToChange` **oder** Property-Notify auf `window.fullScreen`/Maximize-Mode — **exakt in diesem Task klären**.
- `workspace.createDesktop(position, name)` und `workspace.removeDesktop(desktop)` (Plasma 6: `desktop` = VirtualDesktop-Objekt).
- `workspace.desktops` (Array), `workspace.currentDesktop` (VirtualDesktop).
- `window.desktops` (Array von VirtualDesktop) zum Verschieben.

- [ ] **Step 1: Nested-Session-Skript schreiben**

`test/nested-session.sh`:
```bash
#!/usr/bin/env bash
# Startet eine isolierte nested KWin-Wayland-Session mit eigenem Session-Bus.
# NIEMALS gegen die Live-Session laufen lassen.
set -euo pipefail
W="${WSF_W:-1280}"; H="${WSF_H:-800}"
echo "WSF-TEST: starte nested KWin ${W}x${H} (eigener Session-Bus)"
exec dbus-run-session -- kwin_wayland --width "$W" --height "$H" --xwayland \
  "${@:-kdialog --msgbox 'Workspaceflow nested test session'}"
```

- [ ] **Step 2: Probe-Skript schreiben**

`test/probe.js` — listet die real verfügbare API ins KWin-Log:
```javascript
print("WSF-PROBE: workspace keys = " + Object.keys(workspace).join(","));
print("WSF-PROBE: has createDesktop = " + (typeof workspace.createDesktop));
print("WSF-PROBE: has removeDesktop = " + (typeof workspace.removeDesktop));
print("WSF-PROBE: desktops len = " + (workspace.desktops ? workspace.desktops.length : "n/a"));
var ws = workspace.windowList ? workspace.windowList() : [];
print("WSF-PROBE: windowList len = " + ws.length);
if (ws.length > 0) {
  var w = ws[0];
  print("WSF-PROBE: window keys = " + Object.keys(w).join(","));
  print("WSF-PROBE: fullScreen=" + w.fullScreen + " maximizable=" + w.maximizable);
}
```

- [ ] **Step 3: Helpers schreiben**

`test/helpers.sh`:
```bash
#!/usr/bin/env bash
# Assertions gegen das KWin-Log der nested Session.
# Aufruf: LOG=/pfad/zum/journal assert_log "<regex>"
assert_log() {
  local pat="$1"
  if grep -qE "$pat" "${LOG:?LOG nicht gesetzt}"; then
    echo "WSF-TEST PASS: /$pat/ gefunden"
  else
    echo "WSF-TEST FAIL: /$pat/ NICHT gefunden"; return 1
  fi
}
assert_desktop_count() {
  local want="$1"
  grep -qE "WSF: desktop_count=$want" "${LOG:?}" \
    && echo "WSF-TEST PASS: desktop_count=$want" \
    || { echo "WSF-TEST FAIL: desktop_count=$want erwartet"; return 1; }
}
```

- [ ] **Step 4: Nested Session starten und Probe laden**

```bash
chmod +x test/nested-session.sh
# In der nested Session (eigener Bus) das Probe-Skript laden:
WSF_W=1280 WSF_H=800 ./test/nested-session.sh bash -c '
  qdbus-qt6 org.kde.KWin /Scripting loadScript "'"$PWD"'/test/probe.js" wsf-probe
  qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
  sleep 2
'
```
Erwartet: im KWin-Log (journalctl bzw. nested stderr) erscheinen `WSF-PROBE:`-Zeilen.

- [ ] **Step 5: Befunde in API-NOTES.md festschreiben**

`API-NOTES.md` füllen mit den real beobachteten Namen, mindestens:
```markdown
# KWin 6.7 API — bestätigt am 2026-06-27 (nested Session)
- Maximier-Erkennung: <exaktes Signal/Property>
- createDesktop(pos, name): <Signatur/Rückgabe>
- removeDesktop(...): <erwartetes Argument: VirtualDesktop>
- aktueller Desktop: <workspace.currentDesktop Typ>
- Fenster→Desktop verschieben: <window.desktops Schreibweise>
- Fenster-schließen-Signal: <Name>
```

- [ ] **Step 6: Commit**

```bash
git add test/ API-NOTES.md
git commit -m "Task 1: Nested-Test-Harness + verifizierte KWin-6.7-API"
```

---

### Task 2: Paketgerüst (metadata.json) — lädt als No-Op-Skript

**Files:**
- Create: `metadata.json`
- Create: `contents/code/main.js`

**Interfaces:**
- Produces: installierbares KWin/Script-Paket `workspaceflow`, das beim Laden eine Startzeile loggt. Spätere Tasks erweitern `main.js`.

- [ ] **Step 1: Erwartung festlegen (Assertion zuerst)**

Test: nach Laden des Pakets muss `WSF: loaded v…` im Log stehen.
```bash
# (wird in Step 4 ausgeführt) erwartet: assert_log "WSF: loaded"
```

- [ ] **Step 2: metadata.json schreiben**

`metadata.json`:
```json
{
  "KPlugin": {
    "Id": "workspaceflow",
    "Name": "Workspaceflow",
    "Description": "macOS-artige dynamische Spaces: Maximieren erzeugt eine eigene Arbeitsfläche.",
    "Authors": [{ "Name": "sunsetterphoto", "Email": "sunsetterphoto@gmail.com" }],
    "Version": "0.1.0",
    "License": "MIT",
    "Category": "Window Management",
    "EnabledByDefault": false
  },
  "X-Plasma-API": "javascript",
  "X-Plasma-MainScript": "code/main.js"
}
```

- [ ] **Step 3: main.js Minimalfassung**

`contents/code/main.js`:
```javascript
// Workspaceflow — dynamische macOS-artige Spaces für KWin 6.7
const WSF_VERSION = "0.1.0";
print("WSF: loaded v" + WSF_VERSION);
```

- [ ] **Step 4: Installieren in nested Session und Log prüfen**

```bash
kpackagetool6 --type KWin/Script --install . 2>/dev/null \
  || kpackagetool6 --type KWin/Script --upgrade .
# in nested Session aktivieren + reconfigure, dann:
assert_log "WSF: loaded v0\.1\.0"
```
Erwartet: PASS.

- [ ] **Step 5: Commit**

```bash
git add metadata.json contents/code/main.js
git commit -m "Task 2: KWin-Script-Paketgerüst, lädt als No-Op"
```

---

### Task 3: Space erzeugen beim Maximieren

**Files:**
- Modify: `contents/code/main.js`

**Interfaces:**
- Consumes: Maximier-Signal + `createDesktop` + `window.desktops` + `currentDesktop` (Namen aus `API-NOTES.md`).
- Produces: Funktionen `onMaximizeChanged(window)`, Mapping `spaceForWindow` (Map Fenster→VirtualDesktop), Helfer `logDesktopCount()`.

- [ ] **Step 1: Assertion zuerst**

Erwartetes Verhalten: Test-App starten → maximieren → `desktop_count` steigt um 1, neuer Desktop sitzt an Index 1, App liegt dort.
```bash
# erwartet nach Maximieren: assert_desktop_count 2  (Desktop + 1 Space)
#                           assert_log "WSF: created space at index 1"
```

- [ ] **Step 2: Logik implementieren**

In `contents/code/main.js` ergänzen (Namen ggf. an API-NOTES.md anpassen):
```javascript
const spaceForWindow = new Map();   // window -> VirtualDesktop

function logDesktopCount() {
  print("WSF: desktop_count=" + workspace.desktops.length);
}

function isMaximized(window) {
  // gemäß API-NOTES.md: Maximize-Mode == voll (H+V). Platzhalter-Property unten
  // wird in Task 1 bestätigt; hier die bestätigte Schreibweise einsetzen.
  return window.maximizedFull === true;
}

function createSpaceFor(window) {
  if (spaceForWindow.has(window)) return;
  // Position 1 = direkt rechts neben permanentem Desktop 0
  const desk = workspace.createDesktop(1, "WSF:" + (window.caption || "app"));
  const target = (workspace.desktops[1] !== undefined) ? workspace.desktops[1] : desk;
  window.desktops = [target];
  spaceForWindow.set(window, target);
  workspace.currentDesktop = target;
  print("WSF: created space at index 1");
  logDesktopCount();
}

function onMaximizeChanged(window) {
  if (isMaximized(window) && !isIgnored(window)) {
    createSpaceFor(window);
  }
}

function isIgnored(window) {
  return IGNORE_CLASSES.indexOf((window.resourceClass || "").toString()) !== -1;
}
var IGNORE_CLASSES = [];   // wird in Task 6 aus Config befüllt

function track(window) {
  // an Maximier-Signal binden (exakter Name aus API-NOTES.md)
  if (window.maximizedChanged && window.maximizedChanged.connect) {
    window.maximizedChanged.connect(function() { onMaximizeChanged(window); });
  }
}

workspace.windowList().forEach(track);
workspace.windowAdded.connect(track);
```

- [ ] **Step 3: Reinstall + Test in nested Session**

```bash
kpackagetool6 --type KWin/Script --upgrade .
# in nested Session: App starten, via xdotool maximieren
xdotool search --sync --name "." windowactivate key super+Up 2>/dev/null || true
assert_log "WSF: created space at index 1"
assert_desktop_count 2
```
Erwartet: PASS.

- [ ] **Step 4: Commit**

```bash
git add contents/code/main.js
git commit -m "Task 3: Space-Erzeugung bei Maximieren an Position 1"
```

---

### Task 4: Space auflösen bei Wiederherstellen ODER Schließen

**Files:**
- Modify: `contents/code/main.js`

**Interfaces:**
- Consumes: `spaceForWindow` (Task 3), `removeDesktop`, `windowRemoved`-Signal, Maximier-Signal.
- Produces: `removeSpaceFor(window)`, Erweiterung von `onMaximizeChanged`.

- [ ] **Step 1: Assertion zuerst**

Erwartet: wiederhergestellte ODER geschlossene App → `desktop_count` sinkt um 1, Mapping leer.
```bash
# nach Wiederherstellen: assert_log "WSF: removed space"; assert_desktop_count 1
# nach Schließen (anderer Lauf): identisch
```

- [ ] **Step 2: Logik implementieren**

In `main.js` ergänzen/anpassen:
```javascript
function removeSpaceFor(window) {
  const desk = spaceForWindow.get(window);
  if (!desk) return;
  spaceForWindow.delete(window);
  // Fenster zurück auf permanenten Desktop 0
  if (workspace.desktops[0]) window.desktops = [workspace.desktops[0]];
  workspace.removeDesktop(desk);
  workspace.currentDesktop = workspace.desktops[0];
  print("WSF: removed space");
  logDesktopCount();
}

// onMaximizeChanged erweitern: Wiederherstellen löst auf
function onMaximizeChanged(window) {
  if (isIgnored(window)) return;
  if (isMaximized(window)) {
    createSpaceFor(window);
  } else if (spaceForWindow.has(window)) {
    removeSpaceFor(window);
  }
}

// Schließen löst ebenfalls auf
workspace.windowRemoved.connect(function(window) {
  if (spaceForWindow.has(window)) removeSpaceFor(window);
});
```

- [ ] **Step 3: Reinstall + zwei Testläufe in nested Session**

```bash
kpackagetool6 --type KWin/Script --upgrade .
# Lauf A: maximieren -> wiederherstellen (super+Down)
# Lauf B: maximieren -> Fenster schließen
assert_log "WSF: removed space"
assert_desktop_count 1
```
Erwartet: PASS in beiden Läufen.

- [ ] **Step 4: Commit**

```bash
git add contents/code/main.js
git commit -m "Task 4: Space-Auflösung bei Wiederherstellen oder Schließen"
```

---

### Task 5: install.sh / uninstall.sh + Overview-Geste

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`

**Interfaces:**
- Consumes: Paket aus Task 2.
- Produces: idempotente Lifecycle-Skripte; aktiviert Skript in `kwinrc`, bindet 3-Finger-hoch an Overview.

- [ ] **Step 1: Assertion zuerst**

Nach `install.sh` (gegen nested/Test-config): `kreadconfig6 … Plugins workspaceflowEnabled` == `true`.

- [ ] **Step 2: install.sh schreiben (ohne sudo)**

`install.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "Workspaceflow: installiere KWin-Skript…"
if kpackagetool6 --type KWin/Script --list 2>/dev/null | grep -q '^workspaceflow$'; then
  kpackagetool6 --type KWin/Script --upgrade .
else
  kpackagetool6 --type KWin/Script --install .
fi
kwriteconfig6 --file kwinrc --group Plugins --key workspaceflowEnabled true
# 3-Finger-hoch -> Overview
kwriteconfig6 --file kwinrc --group Effect-overview --key TouchBorderActivate ""
kwriteconfig6 --file kwinrc --group TouchpadGestures --key SwipeUp3 "Overview"
# KWin neu konfigurieren
qdbus-qt6 org.kde.KWin /KWin reconfigure 2>/dev/null \
  || gdbus call --session -d org.kde.KWin -o /KWin -m org.kde.KWin.reconfigure
echo "Workspaceflow: aktiv."
./install-timer.sh 2>/dev/null || true   # Auto-Update (Task 7), optional
```

- [ ] **Step 3: uninstall.sh schreiben**

`uninstall.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
kwriteconfig6 --file kwinrc --group Plugins --key workspaceflowEnabled false
kpackagetool6 --type KWin/Script --remove workspaceflow 2>/dev/null || true
qdbus-qt6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
systemctl --user disable --now workspaceflow-update.timer 2>/dev/null || true
echo "Workspaceflow: entfernt."
```

- [ ] **Step 4: Test gegen isolierte Config**

```bash
chmod +x install.sh uninstall.sh
XDG_CONFIG_HOME="$PWD/test/cfg" ./install.sh || true
test "$(XDG_CONFIG_HOME="$PWD/test/cfg" kreadconfig6 --file kwinrc --group Plugins --key workspaceflowEnabled)" = "true" \
  && echo "WSF-TEST PASS: enabled" || { echo "WSF-TEST FAIL"; exit 1; }
```
Erwartet: PASS.

- [ ] **Step 5: Commit**

```bash
git add install.sh uninstall.sh
git commit -m "Task 5: install/uninstall + Overview-Geste (ohne sudo, idempotent)"
```

---

### Task 6: Konfigurierbare Ignorier-Liste

**Files:**
- Create: `contents/config/main.xml`
- Create: `contents/config/config.ui`
- Modify: `contents/code/main.js`

**Interfaces:**
- Consumes: `isIgnored`/`IGNORE_CLASSES` (Task 3).
- Produces: aus Config gelesene `IGNORE_CLASSES`.

- [ ] **Step 1: Assertion zuerst**

App, deren Fensterklasse in der Ignorier-Liste steht, erzeugt beim Maximieren **keinen** Space.
```bash
# erwartet: assert_log "WSF: ignored <class>"; desktop_count unverändert
```

- [ ] **Step 2: main.xml (Config-Schema)**

`contents/config/main.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0">
  <kcfgfile name=""/>
  <group name="Workspaceflow">
    <entry name="IgnoreClasses" type="StringList">
      <label>Fensterklassen, die keinen eigenen Space bekommen</label>
      <default></default>
    </entry>
  </group>
</kcfg>
```

- [ ] **Step 3: config.ui (Minimal-UI)**

`contents/config/config.ui` — ein Mehrzeilen-Eingabefeld (`kcfg_IgnoreClasses`, eine Klasse pro Zeile). (Vollständige Qt-Designer-XML im Implementierungsschritt erzeugen; Feldname muss exakt `kcfg_IgnoreClasses` lauten.)

- [ ] **Step 4: main.js Config-Anbindung**

```javascript
function loadConfig() {
  // KWin: readConfig(key, default)
  var raw = readConfig("IgnoreClasses", "").toString();
  IGNORE_CLASSES = raw.split(/[\n,]+/).map(function(s){return s.trim();}).filter(Boolean);
  print("WSF: ignore=" + IGNORE_CLASSES.join("|"));
}
loadConfig();

function isIgnored(window) {
  var cls = (window.resourceClass || "").toString();
  if (IGNORE_CLASSES.indexOf(cls) !== -1) { print("WSF: ignored " + cls); return true; }
  return false;
}
```

- [ ] **Step 5: Reinstall + Test**

```bash
kpackagetool6 --type KWin/Script --upgrade .
# IgnoreClasses=testapp setzen, testapp maximieren
assert_log "WSF: ignored testapp"
```
Erwartet: PASS, Desktop-Anzahl unverändert.

- [ ] **Step 6: Commit**

```bash
git add contents/config/ contents/code/main.js
git commit -m "Task 6: konfigurierbare Ignorier-Liste nach Fensterklasse"
```

---

### Task 7: Auto-Update (systemd User-Timer)

**Files:**
- Create: `systemd/workspaceflow-update.service`
- Create: `systemd/workspaceflow-update.timer`
- Create: `install-timer.sh`

**Interfaces:**
- Consumes: `install.sh` (Task 5).
- Produces: User-Timer, der `git pull` + Reinstall fährt.

- [ ] **Step 1: Assertion zuerst**

Nach `install-timer.sh`: `systemctl --user is-enabled workspaceflow-update.timer` == `enabled`.

- [ ] **Step 2: service-Unit**

`systemd/workspaceflow-update.service`:
```ini
[Unit]
Description=Workspaceflow Auto-Update (git pull + reinstall)

[Service]
Type=oneshot
WorkingDirectory=%h/Schreibtisch/PublicGitHub/Workspaceflow
ExecStart=/usr/bin/git pull --ff-only
ExecStartPost=%h/Schreibtisch/PublicGitHub/Workspaceflow/install.sh
```

- [ ] **Step 3: timer-Unit**

`systemd/workspaceflow-update.timer`:
```ini
[Unit]
Description=Workspaceflow täglicher Auto-Update-Check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: install-timer.sh (kopieren, nicht symlinken)**

`install-timer.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p "$HOME/.config/systemd/user"
# Units KOPIEREN (kein Symlink nach /home — SELinux/Fedora)
cp systemd/workspaceflow-update.service "$HOME/.config/systemd/user/"
cp systemd/workspaceflow-update.timer   "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now workspaceflow-update.timer
echo "Workspaceflow: Auto-Update-Timer aktiv."
```

- [ ] **Step 5: Test**

```bash
chmod +x install-timer.sh
./install-timer.sh
systemctl --user is-enabled workspaceflow-update.timer
```
Erwartet: `enabled`.

- [ ] **Step 6: Commit**

```bash
git add systemd/ install-timer.sh
git commit -m "Task 7: Auto-Update via systemd User-Timer (Units kopiert, nicht gesymlinkt)"
```

---

### Task 8: README + LICENSE + Live-Aktivierung dokumentieren

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: alle vorigen Tasks.
- Produces: Nutzerdoku inkl. Multi-Monitor-Hinweis und „nur nach erfolgreichem nested Test live aktivieren".

- [ ] **Step 1: README schreiben**

`README.md` mit: Zweck, Verhalten (Maximieren→Space, Wiederherstellen/Schließen→weg, 3-Finger-Gesten), `install.sh`/`uninstall.sh`, Ignorier-Liste, **Bekannte Grenze: virtuelle Desktops spannen alle Monitore (kein Per-Monitor-Space)**, und der Hinweis: erst nach grünem nested Test live aktivieren.

- [ ] **Step 2: LICENSE (MIT, sunsetterphoto)**

```
MIT License
Copyright (c) 2026 sunsetterphoto
[Standard-MIT-Text]
```

- [ ] **Step 3: Commit**

```bash
git add README.md LICENSE
git commit -m "Task 8: README + MIT-LICENSE"
```

---

### Task 9: End-to-End-Verifikation in nested Session

**Files:** keine (reiner Testlauf)

- [ ] **Step 1: Vollszenario in nested Session**

Ablauf in `test/nested-session.sh`:
1. App A starten, maximieren → Space an Index 1 (`desktop_count=2`).
2. App B starten, maximieren → neuer Space an Index 1, A rückt nach Index 2 (`desktop_count=3`, Reihenfolge `Desktop | B | A`).
3. 3 Finger links/rechts simuliert (Desktop-Wechsel) → landet auf Desktop 0 bzw. Spaces.
4. App B wiederherstellen → Space weg (`desktop_count=2`), B zurück auf Desktop 0.
5. App A schließen → Space weg (`desktop_count=1`).
6. Overview-Geste prüfen: `kreadconfig6 … TouchpadGestures SwipeUp3` == `Overview`.

- [ ] **Step 2: Assertions**

```bash
assert_log "WSF: created space at index 1"   # zweimal
assert_log "WSF: removed space"              # zweimal
assert_desktop_count 1                        # Endzustand
```
Erwartet: alle PASS.

- [ ] **Step 3: Abschluss-Commit**

```bash
git commit --allow-empty -m "Task 9: End-to-End in nested Session grün"
```

---

## Hinweis zur Live-Aktivierung

Erst **nachdem Task 9 in der nested Session grün** ist, darf `install.sh` gegen die echte Session laufen. Davor: ausschließlich nested. (Live-Desktop-Manipulation ist tabu.)
