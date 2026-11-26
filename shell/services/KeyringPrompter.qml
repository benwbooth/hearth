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

    // sudo's dialog opens as soon as sudo waits for a fingerprint
    // (popups/FingerprintPrompt calls sudoWaiting), not 30 s later when
    // pam_fprintd gives up and sudo runs hearth-askpass: an "early" entry
    // with the reader's state. A finger closes it; a password typed there
    // is held, the reader released (fprintd restarted: pam_fprintd stops
    // the moment fprintd goes away), and the held answer goes to the
    // askpass prompt sudo then sends, which takes the early entry's place.
    // A prompt that arrives with nothing held takes its place too, keeping
    // what was typed.
    property string fingerMessage: ""
    property bool fingerMatched: false
    property var held: ({})          // sudo pid -> { accept, password }

    function earlyId(pid) { return "sudo-" + pid; }
    // pam_fprintd starts a new verify after each miss: the same sudo
    // keeps its dialog and the "not recognized" line.
    function sudoWaiting(pid, command, preview) {
        if ((!enabled && !preview) || !pid) return;
        if (queue.some(q => q.id === earlyId(pid) || (q.kind === "sudo" && q.sudoPid === pid))) return;
        fingerMessage = "";
        fingerMatched = false;
        queue = queue.concat([{
            id: earlyId(pid), early: true, preview: !!preview, sudoPid: pid, kind: "sudo", type: "password",
            title: "Administrator password",
            message: "Touch the fingerprint reader or type your password to allow this.",
            description: command ? "To run: " + command : "A program asks to run something as the administrator (root).",
            warning: "", passwordNew: false, choiceLabel: "", choiceChosen: false,
            continueLabel: "Allow", cancelLabel: "Cancel"
        }]);
    }
    function fingerStatus(pid, result) {
        if (!queue.some(q => q.id === earlyId(pid))) return;
        switch (result) {
        case "verify-match":
            fingerMatched = true;
            fingerMessage = "";
            earlyClose.pid = pid;
            earlyClose.restart();
            break;
        case "verify-no-match": fingerMessage = "Fingerprint not recognized. Try again."; break;
        case "verify-retry-scan": fingerMessage = "Try again."; break;
        case "verify-swipe-too-short": fingerMessage = "Too short. Try again."; break;
        case "verify-finger-not-centered": fingerMessage = "Center your finger and try again."; break;
        case "verify-remove-and-retry": fingerMessage = "Lift your finger and try again."; break;
        case "verify-disconnected": fingerMessage = "The fingerprint reader was disconnected."; break;
        }
    }
    // sudo stopped waiting for the finger: gone, or its askpass prompt is
    // on the way (it replaces the early entry). Give it a moment, then drop
    // an early entry nothing replaced.
    function sudoDone(pid) {
        if (!queue.some(q => q.id === earlyId(pid))) return;
        orphanCheck.pid = pid;
        orphanCheck.restart();
    }
    function dropEarly(pid) {
        const id = earlyId(pid);
        if (request && request.id === id) busy = false;
        queue = queue.filter(q => q.id !== id);
    }
    Timer { id: earlyClose; property int pid: 0; interval: 700; onTriggered: root.dropEarly(pid) }
    Timer {
        id: orphanCheck
        property int pid: 0
        interval: 4000
        onTriggered: {
            root.dropEarly(pid);
            const h = Object.assign({}, root.held);
            delete h[pid];
            root.held = h;
        }
    }
    Process {
        id: release
        command: ["systemctl", "--no-ask-password", "restart", "fprintd.service"]
    }

    function reply(accept, password, choice) {
        const r = request;
        if (!r || busy) return;
        if (r.preview) {
            queue = queue.slice(1);
            return;
        }
        if (r.early) {
            const h = Object.assign({}, held);
            h[r.sudoPid] = { accept: !!accept, password: accept ? String(password ?? "") : "" };
            held = h;
            if (accept) busy = true;               // "Checking…" until sudo asks
            else queue = queue.slice(1);           // the dialog goes now
            release.running = true;
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
        let i = queue.findIndex(q => q.id === m.id);
        if (i < 0 && m.kind === "sudo" && m.sudoPid) {
            // sudo's askpass prompt: answer it with what was typed into the
            // early dialog, or take that dialog's place.
            const e = queue.findIndex(q => q.id === earlyId(m.sudoPid));
            const h = held[m.sudoPid];
            if (h !== undefined) {
                const rest = Object.assign({}, held);
                delete rest[m.sudoPid];
                held = rest;
                const msg = { id: m.id, accept: h.accept };
                if (h.accept) msg.password = h.password;
                proc.write(JSON.stringify(msg) + "\n");
                if (!h.accept) return;              // its close comes back; nothing to show
                m.answered = true;                  // stays "Checking…"
            }
            if (e >= 0) {
                orphanCheck.stop();
                m.continuesEarly = true;
                const q = queue.slice();
                q[e] = m;
                queue = q;
                if (e === 0 && !m.answered) busy = false;
                return;
            }
            if (m.answered) {
                queue = queue.concat([m]);
                if (queue.length === 1) busy = true;
                return;
            }
        }
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
