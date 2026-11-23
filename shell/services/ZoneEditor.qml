pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The zone layout editor window (popups/ZoneEditorWindow.qml): which layout
// it's editing. The tray's zones picker (bar/indicators/Zones.qml) opens it
// and saves the result into zones.json.
//
//   hearth-ipc call zone-editor newLayout | editActive
Singleton {
    id: root

    // { id, name, zones: [{ x, y, width, height }] } being edited, or null.
    property var layout: null
    property string display: ""       // display whose shape the canvas takes
    property int serial: 0
    readonly property bool open: layout !== null

    // Built-in layouts aren't changed in place: the editor makes a copy.
    signal saved(var layout, string display)

    function edit(l, displayName) {
        const zones = (l && l.zones && l.zones.length ? l.zones : [
            { x: 0, y: 0, width: 0.5, height: 1 }, { x: 0.5, y: 0, width: 0.5, height: 1 }
        ]).map(z => ({ x: +z.x, y: +z.y, width: +z.width, height: +z.height }));
        const copy = !l || l.is_built_in;
        const next = {
            id: copy ? "" : l.id,
            name: !l ? "My Layout" : l.is_built_in ? l.name + " (Copy)" : l.name,
            zones: zones
        };
        const show = () => {
            layout = next;
            display = displayName || "";
            serial++;
        };
        // Already open (say on "My Layout" from New custom layout): the window
        // reads its layout only when it's made, so close it and open a fresh
        // one (which also brings it to the front) instead of changing the
        // layout under it with nothing to show for it.
        if (layout !== null) { layout = null; Qt.callLater(show); }
        else show();
    }
    function close() { layout = null; }

    IpcHandler {
        target: "zone-editor"
        function newLayout(): void { root.edit(null, Compositor.focusedOutput); }
        // The focused display's layout (a built-in one as a copy).
        function editActive(): void {
            const out = Compositor.focusedOutput;
            root.edit(Compositor.isArbor ? ArborZones.layoutFor(out) : null, out);
        }
    }
}
