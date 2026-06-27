// WSF Probe Script – KWin 6.x API Introspection
// Lädt sich via DBus in die nested KWin-Session, listet alle verfügbaren
// API-Namen und -Typen ins KWin-Log (WSF-PROBE: Präfix → stderr/journal).
// NIEMALS in der Live-Session laden.

// ── 1. workspace-Objekt ─────────────────────────────────────────────────────
var wsKeys = Object.keys(workspace);
print("WSF-PROBE: workspace.keys = " + wsKeys.join(","));

// ── 2. Desktop-API ──────────────────────────────────────────────────────────
print("WSF-PROBE: typeof workspace.createDesktop = " + (typeof workspace.createDesktop));
print("WSF-PROBE: typeof workspace.removeDesktop = " + (typeof workspace.removeDesktop));
print("WSF-PROBE: typeof workspace.desktops = " + (typeof workspace.desktops));
print("WSF-PROBE: typeof workspace.currentDesktop = " + (typeof workspace.currentDesktop));

if (workspace.desktops !== undefined) {
    var desktops = workspace.desktops;
    print("WSF-PROBE: desktops.length = " + desktops.length);
    if (desktops.length > 0) {
        var d0 = desktops[0];
        print("WSF-PROBE: desktops[0] keys = " + Object.keys(d0).join(","));
        print("WSF-PROBE: desktops[0].id = " + d0.id);
        print("WSF-PROBE: desktops[0].name = " + d0.name);
        print("WSF-PROBE: desktops[0].x11DesktopNumber = " + d0.x11DesktopNumber);
    }
}

// currentDesktop
var cd = workspace.currentDesktop;
print("WSF-PROBE: currentDesktop type = " + typeof cd);
if (cd !== undefined && cd !== null) {
    print("WSF-PROBE: currentDesktop keys = " + Object.keys(cd).join(","));
}

// ── 3. createDesktop / removeDesktop testen ─────────────────────────────────
if (typeof workspace.createDesktop === "function") {
    try {
        var beforeCount = workspace.desktops.length;
        var newDesktop = workspace.createDesktop(
            beforeCount,
            "WSF-TEST-DESKTOP"
        );
        print("WSF-PROBE: createDesktop(pos, name) -> type = " + typeof newDesktop);
        if (newDesktop) {
            print("WSF-PROBE: newDesktop keys = " + Object.keys(newDesktop).join(","));
            print("WSF-PROBE: newDesktop.id = " + newDesktop.id);
            print("WSF-PROBE: newDesktop.name = " + newDesktop.name);
        }
        // removeDesktop direkt wieder aufräumen – ohne newDesktop-Guard,
        // da createDesktop in KWin 6.x undefined zurückgibt.
        // Stattdessen über Listenlänge prüfen, ob tatsächlich ein Desktop angelegt wurde.
        if (typeof workspace.removeDesktop === "function" && workspace.desktops.length > beforeCount) {
            workspace.removeDesktop(workspace.desktops[workspace.desktops.length - 1]);
            print("WSF-PROBE: removeDesktop(desktop) OK");
            print("WSF-PROBE: desktops.length after remove = " + workspace.desktops.length);
        }
    } catch (e) {
        print("WSF-PROBE: createDesktop ERROR = " + e);
    }
} else {
    print("WSF-PROBE: createDesktop NOT available as function");
}

// ── 4. Fenster-Liste ────────────────────────────────────────────────────────
print("WSF-PROBE: typeof workspace.windowList = " + (typeof workspace.windowList));
var ws = (typeof workspace.windowList === "function") ? workspace.windowList() : [];
print("WSF-PROBE: windowList.length = " + ws.length);

// ── 5. Fenster-spezifische API ──────────────────────────────────────────────
if (ws.length > 0) {
    var w = ws[0];
    print("WSF-PROBE: window[0].caption = " + w.caption);
    var wKeys = Object.keys(w);
    print("WSF-PROBE: window.keys = " + wKeys.join(","));

    // Kandidaten für Maximier-Erkennung
    print("WSF-PROBE: w.fullScreen = " + w.fullScreen);
    print("WSF-PROBE: typeof w.fullScreen = " + (typeof w.fullScreen));
    print("WSF-PROBE: w.maximizable = " + w.maximizable);
    print("WSF-PROBE: typeof w.maximizable = " + (typeof w.maximizable));

    // maximizeMode / maximized*
    print("WSF-PROBE: w.maximizeMode = " + w.maximizeMode);
    print("WSF-PROBE: w.maximized = " + w.maximized);
    print("WSF-PROBE: w.maximizedHorizontally = " + w.maximizedHorizontally);
    print("WSF-PROBE: w.maximizedVertically = " + w.maximizedVertically);

    // setMaximize – programmatisches Maximieren?
    print("WSF-PROBE: typeof w.setMaximize = " + (typeof w.setMaximize));
    print("WSF-PROBE: typeof w.maximize = " + (typeof w.maximize));

    // frameGeometry / size / pos
    print("WSF-PROBE: w.frameGeometry = " + JSON.stringify(w.frameGeometry));

    // tile / tiling
    print("WSF-PROBE: w.tile = " + w.tile);
    print("WSF-PROBE: typeof w.tile = " + (typeof w.tile));

    // Fenster auf Desktop(s) - welche Desktops?
    print("WSF-PROBE: typeof w.desktops = " + (typeof w.desktops));
    if (w.desktops !== undefined) {
        print("WSF-PROBE: w.desktops.length = " + w.desktops.length);
    }
    print("WSF-PROBE: w.onAllDesktops = " + w.onAllDesktops);

    // Signale/Methoden am Window-Objekt prüfen
    var sigCandidates = [
        "maximizedChanged", "maximizeableChanged",
        "fullScreenChanged", "clientMaximizedStateChanged",
        "windowMaximizedStateChanged", "frameGeometryChanged",
        "interactiveMoveResizeFinished", "interactiveMoveResizeStarted",
        "closed", "windowClosed", "deleted",
        "desktopsChanged", "activitiesChanged"
    ];
    for (var i = 0; i < sigCandidates.length; i++) {
        var sig = sigCandidates[i];
        print("WSF-PROBE: w." + sig + " type = " + (typeof w[sig]));
    }

    // Versuch: maximizedChanged Signal verbinden
    if (typeof w.maximizedChanged !== "undefined") {
        try {
            w.maximizedChanged.connect(function() {
                print("WSF-PROBE: maximizedChanged FIRED");
            });
            print("WSF-PROBE: w.maximizedChanged.connect OK");
        } catch(e) {
            print("WSF-PROBE: maximizedChanged.connect ERROR = " + e);
        }
    }

    // Versuch: setMaximize aufrufen wenn verfügbar
    if (typeof w.setMaximize === "function") {
        try {
            w.setMaximize(true, true);
            print("WSF-PROBE: setMaximize(true,true) OK -> maximizeMode = " + w.maximizeMode);
            w.setMaximize(false, false);
            print("WSF-PROBE: setMaximize(false,false) OK -> maximizeMode = " + w.maximizeMode);
        } catch(e) {
            print("WSF-PROBE: setMaximize ERROR = " + e);
        }
    }
} else {
    print("WSF-PROBE: no windows in windowList (expected if no session app)");
    // Auch ohne Fenster: workspace-Signale prüfen
    var wsSigCandidates = [
        "windowAdded", "windowRemoved", "windowActivated",
        "desktopsChanged", "currentDesktopChanged",
        "virtualScreenGeometryChanged"
    ];
    for (var k = 0; k < wsSigCandidates.length; k++) {
        var wsig = wsSigCandidates[k];
        print("WSF-PROBE: workspace." + wsig + " type = " + (typeof workspace[wsig]));
    }
}

// ── 6. workspace Signale (immer) ─────────────────────────────────────────────
print("WSF-PROBE: typeof workspace.windowAdded = " + (typeof workspace.windowAdded));
print("WSF-PROBE: typeof workspace.windowRemoved = " + (typeof workspace.windowRemoved));
print("WSF-PROBE: typeof workspace.windowActivated = " + (typeof workspace.windowActivated));
print("WSF-PROBE: typeof workspace.currentDesktopChanged = " + (typeof workspace.currentDesktopChanged));
print("WSF-PROBE: typeof workspace.desktopsChanged = " + (typeof workspace.desktopsChanged));

print("WSF-PROBE: DONE");
