import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// Icon-only task manager for the classic panel: pinned launchers plus
// running apps, grouped by desktop entry, like Plasma's icontasks.
Row {
    id: root
    spacing: 2

    // Super+N (Plasma's "activate task manager entry N").
    IpcHandler {
        target: !Settings.mac && ShellState.isActiveScreen(root.QsWindow.window ? root.QsWindow.window.screen : null) ? "tasks" : ""
        function activate(n: int): void {
            const item = repeater.itemAt(n - 1);
            if (item) item.trigger();
        }
    }

    Repeater {
        id: repeater
        model: ScriptModel {
            values: TaskGroups.groups
            objectProp: "key"
        }
        delegate: TaskButton {}
    }
}
