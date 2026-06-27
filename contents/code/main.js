// Workspaceflow — dynamische macOS-artige Spaces für KWin 6.7
const WSF_VERSION = "0.1.0";
print("WSF: loaded v" + WSF_VERSION);

// ── Konfiguration ────────────────────────────────────────────────────────────
// wird in Task 6 aus Config befüllt
var IGNORE_CLASSES = [];

// ── State ────────────────────────────────────────────────────────────────────
// Mapping: window -> VirtualDesktop (der für dieses Fenster erzeugte Space)
var spaceForWindow = new Map();

// ── Hilfsfunktionen ──────────────────────────────────────────────────────────

/**
 * Gibt die aktuelle Desktop-Anzahl ins Log aus.
 * Format: "WSF: desktop_count=<n>"
 */
function logDesktopCount() {
    print("WSF: desktop_count=" + workspace.desktops.length);
}

/**
 * Prüft, ob ein Fenster auf der Ignorier-Liste steht.
 * Task 6 befüllt IGNORE_CLASSES aus der Konfiguration.
 */
function isIgnored(window) {
    return IGNORE_CLASSES.indexOf((window.resourceClass || "").toString()) !== -1;
}

/**
 * Erzeugt einen neuen virtuellen Desktop an Position 1 (direkt rechts neben
 * dem permanenten Desktop 0), verschiebt das Fenster dorthin und wechselt den
 * Fokus. Idempotent: jedes Fenster bekommt maximal einen Space.
 */
function createSpaceFor(window) {
    if (spaceForWindow.has(window)) return;

    // Position 1 = direkt rechts neben permanentem Desktop 0.
    // createDesktop() gibt undefined zurück (C++ void) — neuen Desktop
    // anschließend via workspace.desktops[1] holen. (Bestätigt: API-NOTES.md)
    workspace.createDesktop(1, "WSF:" + (window.caption || "app"));
    var target = workspace.desktops[1];

    window.desktops = [target];
    spaceForWindow.set(window, target);
    workspace.currentDesktop = target;

    print("WSF: created space at index 1");
    logDesktopCount();
}

/**
 * Signal-Handler für window.maximizedChanged (kein Argument — Modus via
 * window.maximizeMode lesen). Wert 3 = MaximizeFull (H+V). (API-NOTES.md)
 */
function onMaximizeChanged(window) {
    if (window.maximizeMode === 3 && !isIgnored(window)) {
        createSpaceFor(window);
    }
}

/**
 * Verbindet ein Fenster mit dem maximizedChanged-Signal.
 * Wird für vorhandene und neu erscheinende Fenster aufgerufen.
 */
function track(window) {
    if (window.maximizedChanged &&
            typeof window.maximizedChanged.connect === "function") {
        window.maximizedChanged.connect(function() {
            onMaximizeChanged(window);
        });
    }
}

// ── Initialisierung ──────────────────────────────────────────────────────────
// Vorhandene Fenster tracken
workspace.windowList().forEach(track);

// Neue Fenster tracken sobald sie erscheinen
workspace.windowAdded.connect(track);
