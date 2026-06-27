# KWin 6.7 Scripting API — verifiziert am 2026-06-27 (nested Session)

Alle Befunde wurden live in einer isolierten KWin-6.7-nested-Session bestätigt
(`dbus-run-session -- kwin_wayland --virtual --xwayland`, eigener Session-Bus,
kein Kontakt mit dem Live-Desktop). Testfenster: `xmessage` via Xwayland.

---

## Logging / Ausgabe von print()

`print()` in KWin-JS-Skripten schreibt **NICHT** zur Kategorie `kwin_scripting`,
sondern zur Qt-Kategorie **`js`** (Standard-Level: Warning → debug unsichtbar).

Um WSF-PROBE-Zeilen zu sehen:
```bash
export QT_LOGGING_RULES="js.debug=true;js=true"
export QT_FORCE_STDERR_LOGGING=1
```
Ausgabe erscheint dann als `js: WSF-PROBE: …` auf stderr von kwin_wayland.

---

## Skript laden via D-Bus

```bash
# Skript-ID ermitteln (integer, z.B. 1)
qdbus-qt6 org.kde.KWin /Scripting loadScript /pfad/probe.js wsf-probe

# Scripting-Engine starten (alle geladenen Skripte ausführen)
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

Wichtig: Beide Aufrufe müssen auf dem **gleichen** Session-Bus laufen wie die
KWin-Instanz (also innerhalb derselben `dbus-run-session`-Umgebung).

---

## workspace-Objekt (122 Properties/Signals/Slots)

### Desktop-API

| Symbol | Typ | Beschreibung |
|--------|-----|--------------|
| `workspace.createDesktop(pos, name)` | `function` | Erzeugt neuen virtuellen Desktop. Gibt **undefined** zurück (C++ void). Desktop wird wirklich erzeugt — `workspace.desktops.length` steigt. |
| `workspace.removeDesktop(desktop)` | `function` | Entfernt VirtualDesktop-Objekt. Argument: Objekt aus `workspace.desktops`. |
| `workspace.desktops` | `object` (Array) | Array aller VirtualDesktop-Objekte. |
| `workspace.currentDesktop` | `object` | Aktives VirtualDesktop-Objekt. |
| `workspace.moveDesktop(desktop, pos)` | `function` | Verschiebt Desktop an andere Position (in workspace.keys vorhanden). |

Beispiel:
```javascript
var newDesk = workspace.createDesktop(workspace.desktops.length, "MySpace");
// newDesk === undefined (C++ void-Rückgabe), aber Desktop existiert:
var created = workspace.desktops[workspace.desktops.length - 1];
workspace.removeDesktop(created);
```

### VirtualDesktop-Objekt (keys)

```
objectName, id, x11DesktopNumber, name,
objectNameChanged, nameChanged, x11DesktopNumberChanged, aboutToBeDestroyed
```

| Property | Typ | Wert |
|----------|-----|------|
| `id` | string | UUID, z.B. `"6096883c-24e2-415d-8a69-cf6a382ae90f"` |
| `x11DesktopNumber` | number | 1-basiert (1, 2, 3, …) |
| `name` | string | Anzeigename, z.B. `"Arbeitsfläche 1"` |
| `aboutToBeDestroyed` | Signal | feuert kurz vor Löschung |

### Fenster-API

| Symbol | Typ | Beschreibung |
|--------|-----|--------------|
| `workspace.windowList()` | `function` | Gibt Array aller verwalteten Fenster zurück. |
| `workspace.windowAdded` | Signal(`Window`) | Feuert wenn neues Fenster erscheint. |
| `workspace.windowRemoved` | Signal(`Window`) | Feuert wenn Fenster geschlossen wird. |
| `workspace.windowActivated` | Signal | Feuert bei Fokus-Wechsel. |

### Desktop-Navigations-Signals

```javascript
workspace.currentDesktopChanged  // Signal
workspace.desktopsChanged        // Signal (Array geändert)
workspace.desktopLayoutChanged   // Signal
```

---

## Window-Objekt

### Maximier-Erkennung und -Steuerung (WICHTIG für Workspaceflow)

| Symbol | Typ | Beschreibung |
|--------|-----|--------------|
| `maximizeMode` | `number` | Aktueller Maximier-Status. Werte: `0`=keine, `1`=vertikal, `2`=horizontal, `3`=voll (MaximizeFull) |
| `maximizable` | `boolean` | `true` wenn Fenster maximierbar |
| `setMaximize(h, v)` | `function` | Programmatisches Maximieren — **ohne xdotool**! `h` und `v` sind booleans. |
| `maximizedAboutToChange` | Signal(`newMode: number`) | Feuert **vor** Statuswechsel. Argument: neuer maximizeMode (z.B. `3` oder `0`) |
| `maximizedChanged` | Signal(void) | Feuert **nach** Statuswechsel. Kein Argument — aktuellen Modus via `window.maximizeMode` lesen. |

**NICHT vorhanden** (in KWin 6.7):
- `window.maximize` → `undefined`
- `window.maximized` → `undefined`
- `window.maximizedHorizontally` → `undefined`
- `window.maximizedVertically` → `undefined`
- `window.clientMaximizedStateChanged` → `undefined` (nur in alten Versionen)

Beispiel — Window maximieren und Reaktion beobachten:
```javascript
workspace.windowAdded.connect(function(w) {
    w.maximizedAboutToChange.connect(function(newMode) {
        // newMode: 0=restore, 3=maximize-full
        print("Maximize about to change to: " + newMode);
    });
    w.maximizedChanged.connect(function() {
        print("Maximize changed, current mode: " + w.maximizeMode);
    });
});

// Programmatisch maximieren (beide Achsen):
w.setMaximize(true, true);   // maximizeMode wird 3
w.setMaximize(false, false); // maximizeMode wird 0
```

### Desktop-Zuweisung (Fenster → Desktop verschieben)

```javascript
// Lesen: Array von VirtualDesktop-Objekten
var currentDesktops = window.desktops; // z.B. length = 1

// Schreiben: Direkte Array-Zuweisung funktioniert!
window.desktops = [targetDesktop]; // VirtualDesktop-Objekt aus workspace.desktops
window.desktops = [workspace.desktops[2]]; // auf Desktop 3 verschieben
```

Signal: `window.desktopsChanged` feuert nach der Zuweisung.

### Weitere Window-Properties

| Symbol | Typ | Beschreibung |
|--------|-----|--------------|
| `caption` | string | Fenstertitel |
| `captionNormal` | string | Titel ohne Zusätze |
| `fullScreen` | boolean | FullScreen-Status (getrennt von Maximize!) |
| `fullScreenChanged` | Signal | feuert bei FS-Wechsel |
| `frameGeometry` | object | `{x, y, width, height}` in logischen Pixeln |
| `frameGeometryChanged` | Signal | feuert bei Größen-/Positionsänderung |
| `desktops` | writable Array | VirtualDesktop-Objekte |
| `onAllDesktops` | boolean | true = Fenster auf allen Desktops |
| `desktopsChanged` | Signal | feuert wenn Desktop-Zuordnung ändert |
| `tile` | object (null) | Kachel-Objekt oder null |
| `tileChanged` | Signal | feuert bei Kachelzuweisung |
| `closed` | Signal(void) | feuert wenn Fenster geschlossen wird |
| `pid` | number | Prozess-ID des Fenstereigentümers |
| `resourceName` | string | Fensterklasse (WM_CLASS) |
| `resourceClass` | string | WM_CLASS Instanz |
| `active` | boolean | Hat Fokus |
| `activeChanged` | Signal | |
| `minimizable` | boolean | |
| `minimized` | boolean | |
| `minimizedChanged` | Signal | |
| `closeable` | boolean | |
| `keepAbove` | boolean | |
| `keepBelow` | boolean | |
| `deleted` | boolean | true wenn schon gelöscht (kein Signal!) |

### Vollständige Window-Keys (beobachtet, xmessage auf Xwayland)

```
objectName, bufferGeometry, clientGeometry, pos, size, x, y, width, height,
opacity, output, rect, resourceName, resourceClass, windowRole, desktopWindow,
dock, toolbar, menu, normalWindow, dialog, splash, utility, dropdownMenu,
popupMenu, tooltip, notification, criticalNotification, appletPopup,
onScreenDisplay, comboBox, dndIcon, windowType, managed, deleted,
skipsCloseAnimation, popupWindow, outline, internalId, pid, stackingOrder,
fullScreen, fullScreenable, active, desktops, onAllDesktops, activities,
skipTaskbar, skipPager, skipSwitcher, closeable, icon, keepAbove, keepBelow,
minimizable, minimized, iconGeometry, specialWindow, demandsAttention, caption,
captionNormal, minSize, maxSize, wantsInput, transient, transientFor, modal,
frameGeometry, move, resize, decorationHasAlpha, noBorder, providesContextHelp,
maximizable, maximizeMode, moveable, moveableAcrossScreens, resizeable,
desktopFileName, hasApplicationMenu, applicationMenuActive, unresponsive,
colorScheme, layer, hidden, tile, inputMethod, tag, description,
excludeFromCapture,
[… Signale: …]
objectNameChanged, stackingOrderChanged, opacityChanged, damaged,
inputTransformationChanged, closed, outputChanged, skipCloseAnimationChanged,
windowRoleChanged, windowClassChanged, surfaceChanged, shadowChanged,
bufferGeometryChanged, frameGeometryChanged, clientGeometryChanged,
frameGeometryAboutToChange, tileChanged, requestedTileChanged, fullScreenChanged,
skipTaskbarChanged, skipPagerChanged, skipSwitcherChanged, iconChanged,
activeChanged, keepAboveChanged, keepBelowChanged, demandsAttentionChanged,
desktopsChanged, activitiesChanged, minimizedChanged, paletteChanged,
colorSchemeChanged, captionChanged, captionNormalChanged,
maximizedAboutToChange, maximizedChanged,
transientChanged, modalChanged, quickTileModeChanged, moveResizedChanged,
moveResizeCursorChanged, interactiveMoveResizeStarted, interactiveMoveResizeStepped,
interactiveMoveResizeFinished, closeableChanged, minimizeableChanged,
maximizeableChanged, desktopFileNameChanged, applicationMenuChanged,
hasApplicationMenuChanged, applicationMenuActiveChanged, unresponsiveChanged,
decorationChanged, hiddenChanged, hiddenByShowDesktopChanged,
lockScreenOverlayChanged, readyForPaintingChanged, maximizeGeometryRestoreChanged,
fullscreenGeometryRestoreChanged, offscreenRenderingChanged, targetScaleChanged,
nextTargetScaleChanged, tagChanged, descriptionChanged, borderRadiusChanged,
excludeFromCaptureChanged, decorationPolicyChanged,
[… Methoden: …]
closeWindow, setReadyForPainting, setMaximize, shapeChanged, updateCaption
```

---

## Zusammenfassung für nachfolgende Tasks

| Anforderung | Bestätigte Lösung |
|-------------|-------------------|
| Maximier-Erkennung (Signal) | `window.maximizedChanged` (nach-Änderung, kein Arg); `window.maximizedAboutToChange(newMode)` (vor-Änderung, arg=neuer Modus) |
| Maximize-Status lesen | `window.maximizeMode` — 0=none, 1=vert, 2=horiz, 3=full |
| Maximize programmatisch setzen | `window.setMaximize(h: bool, v: bool)` — kein xdotool nötig! |
| Desktop erzeugen | `workspace.createDesktop(pos, name)` — returns undefined, wirkt aber |
| Desktop entfernen | `workspace.removeDesktop(virtualDesktopObj)` |
| Aktueller Desktop | `workspace.currentDesktop` (VirtualDesktop-Objekt) |
| Alle Desktops | `workspace.desktops` (Array) |
| Fenster→Desktop | `window.desktops = [virtualDesktopObj]` (Array-Zuweisung) |
| Fenster-Schließ-Signal | `window.closed` (Signal, void) |
| Fenster-Liste | `workspace.windowList()` |
| Fenster erscheint | `workspace.windowAdded` (Signal, arg=Window) |
| Fenster verschwindet | `workspace.windowRemoved` (Signal, arg=Window) |

---

## Bekannte Abweichungen von der ursprünglichen Annahme

1. `createDesktop()` gibt `undefined` zurück (nicht das neue Objekt). Neuen Desktop
   via `workspace.desktops[workspace.desktops.length - 1]` holen.
2. `print()` loggt nach `js` (nicht `kwin_scripting`) — logging rule anpassen.
3. `window.maximize()` existiert nicht — nur `window.setMaximize(h, v)`.
4. `window.maximizedChanged` hat keine Argumente (neuen Modus via `window.maximizeMode` lesen).
5. `window.maximizedAboutToChange` hat 1 Argument: den neuen maximizeMode als Zahl.
