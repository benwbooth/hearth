pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The keyring's password prompts: runs helpers/hearth-keyring-prompter (the
// "system prompter" the oo7 / gnome-keyring keyring asks through, which only
// GNOME Shell provides otherwise) and queues its prompts for
// popups/KeyringDialog, which answers through reply().
//
// The keyring asks when it is locked and an app wants a saved password: the
// login screen normally unlocks it, so this shows up only if the keyring's
// password differs from the login password (e.g. after a password change).
//
// HEARTH_KEYRING_PROMPTER=0 turns it off (test sessions sharing the real
// bus). `hearth-ipc call keyring preview` shows the dialog with made-up
// data; nothing is sent to the keyring.
Singleton {
    id: root

    readonly property bool enabled: Quickshell.env("HEARTH_KEYRING_PROMPTER") !== "0" && !Quickshell.env("HEARTH_GREETER")
    readonly property bool running: proc.running

    // Pending prompts, oldest first; the dialog shows the first.
    property var queue: []
    readonly property var request: queue.length > 0 ? queue[0] : null
    // The answer to the shown prompt went out; waiting for the keyring.
    property bool busy: false
    // The keyring asked again for the shown prompt (wrong password).
    signal retry()

    function reply(accept, password, choice) {
        const r = request;
        if (!r || busy) return;
        if (r.preview) {
            queue = queue.slice(1);
            return;
        }
        const msg = { id: r.id, accept: !!accept };
        if (accept && r.type === "password") msg.password = String(password ?? "");
        if (r.choiceLabel) msg.choice = !!choice;
        proc.write(JSON.stringify(msg) + "\n");
        // A cancel ends the prompt here; an answer waits for the keyring's
        // verdict (close, or the same prompt again with a warning).
        if (accept) busy = true;
        else queue = queue.slice(1);
    }

    function handle(m) {
        if (m.type === "close") {
            if (request && request.id === m.id) busy = false;
            queue = queue.filter(q => q.id !== m.id);
            return;
        }
        const i = queue.findIndex(q => q.id === m.id);
        if (i < 0) {
            queue = queue.concat([m]);
            return;
        }
        const q = queue.slice();
        q[i] = m;
        queue = q;
        if (i === 0) {
            busy = false;
            retry();
        }
    }

    Process {
        id: proc
        command: ["hearth-keyring-prompter"]
        running: root.enabled
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try { root.handle(JSON.parse(line)); }
                catch (e) { console.warn("hearth-keyring-prompter: bad line", line); }
            }
        }
        onExited: (code, status) => {
            // The keyring sees the prompts end with the helper.
            root.queue = root.queue.filter(q => q.preview);
            root.busy = false;
            if (root.enabled) restart.start();
        }
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: if (root.enabled) proc.running = true
    }

    IpcHandler {
        target: "keyring"
        // preview [unlock|wrong|new|confirm]
        function preview(kind: string): void {
            const k = kind || "unlock";
            const p = {
                id: -1, preview: true, type: k === "confirm" ? "confirm" : "password",
                title: k === "new" ? "New Keyring Password" : "Unlock Keyring",
                message: k === "new" ? "Choose password for new keyring" : "Authentication required",
                description: k === "new" ? "An application wants to create a new keyring called “Work”. Choose the password you want to use for it."
                                         : "An application wants access to the keyring “Login”, but it is locked",
                warning: k === "wrong" ? "The unlock password was incorrect" : "",
                passwordNew: k === "new", choiceLabel: "", choiceChosen: false,
                continueLabel: k === "new" ? "Create" : "Unlock", cancelLabel: "Cancel"
            };
            root.queue = root.queue.filter(q => !q.preview).concat([p]);
            if (k === "wrong") root.retry();
        }
        function close(): void { root.queue = root.queue.filter(q => !q.preview); }
    }
}
