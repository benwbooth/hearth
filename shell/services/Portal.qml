pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What apps ask the desktop through xdg-desktop-portal: helpers/hearth-portal
// is hearth's portal backend (colour scheme, notifications, permissions,
// "Open with", printing, adding web apps...). Its dialogs come here: this
// runs its relay (`hearth-portal ui`) and queues the requests for
// popups/PortalDialog, which answers through reply().
//
// Request types: "access" (an app wants the camera, location, to run in the
// background...), "account" (your name and picture), "appchooser" (Open
// With), "launcher" (add a web app or app shortcut), "print".
//
// HEARTH_PORTAL=0 turns the relay off (test shells sharing the real bus:
// the real backend would send its dialogs to them). `hearth-ipc call portal
// preview access|account|appchooser|launcher|print` shows a dialog with
// made-up data; nothing is sent to an app.
Singleton {
    id: root

    readonly property bool enabled: Quickshell.env("HEARTH_PORTAL") !== "0" && !Quickshell.env("HEARTH_GREETER")
    readonly property bool running: proc.running

    // Pending requests, oldest first; the dialog shows the first.
    property var queue: []
    readonly property var request: queue.length > 0 ? queue[0] : null

    // answer: { response: 0 } plus the type's fields (see the helper), or
    // null for Cancel.
    function reply(answer) {
        const r = request;
        if (!r) return;
        queue = queue.slice(1);
        if (r.preview) return;
        const msg = Object.assign({ response: 1 }, answer || {});
        msg.id = r.id;
        proc.write(JSON.stringify(msg) + "\n");
    }

    function handle(m) {
        if (m.type === "close") {
            queue = queue.filter(q => q.id !== m.id || q.preview);
            return;
        }
        if (m.type === "update") {
            // AppChooser: the app list changed while the sheet was open.
            queue = queue.map(q => q.id === m.id && !q.preview ? Object.assign({}, q, { choices: m.choices }) : q);
            return;
        }
        queue = queue.concat([m]);
    }

    Process {
        id: proc
        command: ["hearth-portal", "ui"]
        running: root.enabled
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try { root.handle(JSON.parse(line)); }
                catch (e) { console.warn("hearth-portal: bad line", line); }
            }
        }
        onExited: (code, status) => {
            // The backend sees the relay go and cancels what was open.
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
        target: "portal"
        function preview(kind: string): void {
            const samples = {
                access: {
                    type: "access", app: "Firefox", appIcon: "firefox", icon: "camera-web",
                    title: "Allow Firefox to use the camera?",
                    subtitle: "Firefox wants to use your camera for a video call.",
                    body: "You can change this later in Settings.",
                    denyLabel: "", grantLabel: "",
                    choices: [{ id: "remember", label: "Remember for this app", options: [], initial: "true" }]
                },
                account: {
                    type: "account", app: "Fractal", appIcon: "org.gnome.Fractal",
                    reason: "Fractal wants to fill in your profile.",
                    user: "you", name: "Your Name", image: ""
                },
                appchooser: {
                    type: "appchooser", app: "Flatseal", target: "notes.html",
                    contentType: "text/html", typeName: "HTML document", lastChoice: "firefox",
                    choices: [
                        { id: "firefox", name: "Firefox", icon: "firefox", comment: "Browse the World Wide Web" },
                        { id: "brave-browser", name: "Brave Web Browser", icon: "brave-browser", comment: "Access the Internet" },
                        { id: "org.kde.kate", name: "Kate", icon: "kate", comment: "Advanced text editor" }
                    ]
                },
                launcher: {
                    type: "launcher", app: "Brave", name: "Example Web App", icon: "applications-internet",
                    webapp: true, target: "https://example.org", editableName: true
                },
                print: {
                    type: "print", app: "LibreOffice", title: "Report.odt", preparing: true, acceptLabel: "",
                    printer: "Office", copies: 1,
                    printers: [{ value: "Office", label: "Office Printer", state: "idle", media: "" },
                               { value: "Lab", label: "Lab Laser", state: "stopped", media: "" }]
                }
            };
            const p = samples[kind || "access"];
            if (!p) return;
            root.queue = root.queue.filter(q => !q.preview).concat([Object.assign({ id: -1, preview: true }, p)]);
        }
        function close(): void { root.queue = root.queue.filter(q => !q.preview); }
    }
}
