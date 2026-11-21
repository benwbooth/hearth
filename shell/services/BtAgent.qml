pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth pairing agent: runs helpers/hearth-bt-agent (a BlueZ Agent1 that
// relays requests as JSON lines) and queues its requests for
// popups/BtPairDialog, which answers through reply().
//
// Plasma's bluedevil already is the default agent inside a KDE session, so
// the helper only runs elsewhere (Hyprland) unless HEARTH_BT_AGENT=1; set
// HEARTH_BT_AGENT=0 to never run it.
//
// `hearth-ipc call btagent preview RequestConfirmation` (or RequestPinCode,
// RequestPasskey, DisplayPasskey, AuthorizeService...) shows the dialog with
// made-up data; nothing is sent to BlueZ.
Singleton {
    id: root

    readonly property bool enabled: {
        const force = Quickshell.env("HEARTH_BT_AGENT");
        if (force === "1") return true;
        if (force === "0") return false;
        return !Compositor.underPlasma;
    }
    readonly property bool running: proc.running

    // Pending requests, oldest first; the dialog shows the first.
    property var queue: []
    readonly property var request: queue.length > 0 ? queue[0] : null

    readonly property var replyTypes: ["RequestConfirmation", "RequestPinCode", "RequestPasskey",
                                       "RequestAuthorization", "AuthorizeService"]

    function needsReply(r) { return r !== null && replyTypes.indexOf(r.type) >= 0; }

    // Answer the current request (accept or reject; value for PIN/passkey).
    // Display-only requests are just dismissed.
    function reply(accept, value) {
        const r = request;
        if (!r) return;
        if (needsReply(r) && !r.preview) {
            const msg = { id: r.id, accept: !!accept };
            if (value !== undefined && value !== null) msg.value = String(value);
            proc.write(JSON.stringify(msg) + "\n");
        }
        queue = queue.slice(1);
    }

    function handle(m) {
        switch (m.type) {
        case "Cancel":
        case "Release":
            // BlueZ cancels whatever is outstanding.
            queue = [];
            break;
        case "DisplayPasskey":
        case "DisplayPinCode": {
            // Replace an earlier display for the same device (passkey
            // displays repeat as keys are typed on the remote keyboard).
            const rest = queue.filter(q => !(q.type === m.type && q.device === m.device));
            queue = rest.concat([m]);
            break;
        }
        default:
            queue = queue.concat([m]);
        }
    }

    Process {
        id: proc
        command: ["hearth-bt-agent"]
        running: root.enabled
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try { root.handle(JSON.parse(line)); }
                catch (e) { console.warn("hearth-bt-agent: bad line", line); }
            }
        }
        onExited: (code, status) => {
            // Its pending DBus calls died with it.
            root.queue = root.queue.filter(q => q.preview);
            if (root.enabled) restart.start();
        }
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: if (root.enabled) proc.running = true
    }

    IpcHandler {
        target: "btagent"
        function preview(type: string): void {
            root.queue = root.queue.concat([{
                id: -1, preview: true, type: type || "RequestConfirmation",
                device: "/org/bluez/hci0/dev_00_11_22_33_44_55",
                name: "WH-1000XM6", address: "00:11:22:33:44:55", icon: "audio-headset",
                passkey: "123456", pincode: "0000", entered: 2,
                uuid: "0000110b-0000-1000-8000-00805f9b34fb"
            }]);
        }
        function close(): void { root.queue = []; }
    }
}
