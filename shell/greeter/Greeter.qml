pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// The login screen's state (hearth's greeter, README "Login screen"): who
// can log in, which sessions there are, the chosen user and session, and
// the greetd conversation. Runs as the `greeter` user inside its own arbor
// (nix/greeter.nix), so it reads nothing from anyone's home: users come
// from AccountsService / passwd and sessions from the .desktop files
// (helpers/hearth-greeter-info); the wallpaper from /var/lib/hearth/wallpaper.
//
// Logging in: the password goes to greetd only when you press Return
// (createSession, then the answer to PAM's password prompt). A success
// launches the chosen session with XDG_SESSION_TYPE=wayland and its
// DesktopNames as XDG_CURRENT_DESKTOP, then the greeter quits and its
// arbor with it; greetd starts the session.
Singleton {
    id: root

    property var users: []          // [{ name, realName, icon }]
    property var sessions: []       // [{ id, name, exec, desktopNames, comment }]
    property bool loaded: false
    property int userIndex: -1      // -1: several users and none picked yet
    readonly property var user: userIndex >= 0 && userIndex < users.length ? users[userIndex] : null
    property string sessionId: ""
    readonly property var session: sessions.find(s => s.id === sessionId) || sessions[0] || null

    // The conversation.
    property bool checking: false
    property bool launching: false
    property string message: ""     // plain-language problem under the field
    property bool capsLock: false
    property bool answered: false
    property string pending: ""     // the password, only until greetd asks for it
    signal wrongPassword()
    signal launchAnimationRequested()

    readonly property string stateDir: Quickshell.env("HEARTH_GREETER_STATE_DIR") || "/var/cache/hearth-greeter"
    readonly property string defaultSession: Quickshell.env("HEARTH_GREETER_DEFAULT_SESSION") || "arbor"
    // Test hook: never actually start a session (the VM test sets it to
    // check the flow up to "ready to launch").
    readonly property bool dryRun: Quickshell.env("HEARTH_GREETER_DRYRUN") === "1"
    property var saved: ({})        // state.json: { lastUser, sessions: { user: id } }

    function initials(u) {
        const n = (u && (u.realName || u.name)) || "?";
        const parts = n.trim().split(/\s+/);
        return ((parts[0] || "?")[0] + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase();
    }
    function displayName(u) { return u ? (u.realName || u.name) : ""; }

    // ------------------------------------------------------------ loading

    Process {
        id: info
        running: true
        command: ["hearth-greeter-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                let j = {};
                try { j = JSON.parse(text); } catch (e) { console.warn("greeter: bad info", e); }
                root.users = j.users || [];
                root.sessions = j.sessions || [];
                root.loaded = true;
                root.pickDefaults();
            }
        }
    }
    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: { try { root.saved = JSON.parse(text()) || {}; } catch (e) { root.saved = {}; } }
    }
    function pickDefaults() {
        const last = root.saved.lastUser || "";
        const i = root.users.findIndex(u => u.name === last);
        root.userIndex = root.users.length === 1 ? 0 : i;
        root.pickSession();
    }
    // The session this user used last, else the system default (arbor).
    function pickSession() {
        const per = root.saved.sessions || {};
        const want = (root.user && per[root.user.name]) || root.defaultSession;
        const s = root.sessions.find(x => x.id === want) || root.sessions.find(x => x.id === root.defaultSession) || root.sessions[0];
        root.sessionId = s ? s.id : "";
    }
    function selectUser(i) {
        if (root.checking || root.launching) return;
        root.cancel();
        root.userIndex = i;
        root.message = "";
        root.pickSession();
    }
    function backToUsers() {
        if (root.users.length < 2 || root.launching) return;
        root.cancel();
        root.userIndex = -1;
        root.message = "";
    }
    function save() {
        if (!root.user) return;
        const s = JSON.parse(JSON.stringify(root.saved || {}));
        s.lastUser = root.user.name;
        s.sessions = s.sessions || {};
        if (root.session) s.sessions[root.user.name] = root.session.id;
        root.saved = s;
        stateFile.setText(JSON.stringify(s, null, 2) + "\n");
    }

    // ------------------------------------------------------- logging in

    function submit(password) {
        if (!root.user || root.checking || root.launching) return;
        if (!root.session) { root.message = "There's no desktop session to start. Ask whoever set up this computer."; return; }
        if (!Greetd.available) { root.message = "The login service (greetd) isn't running, so you can't log in from here."; return; }
        root.message = "";
        root.checking = true;
        root.answered = false;
        root.pending = password;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Greetd.createSession(root.user.name);
    }
    function cancel() {
        root.pending = "";
        root.checking = false;
        if (Greetd.available && Greetd.state !== GreetdState.Inactive && Greetd.state !== GreetdState.Launching
                && Greetd.state !== GreetdState.Launched)
            Greetd.cancelSession();
    }
    function failed(msg) {
        root.pending = "";
        root.checking = false;
        root.message = msg;
        root.wrongPassword();
        // Quickshell ends the greetd session itself after an auth error;
        // cancelling again would earn an error reply from greetd.
    }
    // What PAM says, in plain words where we know it.
    function plain(m) {
        const s = String(m || "");
        if (/locked|faillock|too many/i.test(s)) return "Too many wrong passwords: this account is locked for a while. Try again later.";
        if (/expired/i.test(s)) return "Your password has expired. Log in on a text console (Ctrl+Alt+F2) to choose a new one.";
        return s;
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (!root.checking) return;
            if (responseRequired && !echoResponse && !root.answered) {
                root.answered = true;
                const p = root.pending;
                root.pending = "";
                Greetd.respond(p);
            } else if (responseRequired) {
                // A second question (new password, one-time code): this screen can't ask it.
                Greetd.cancelSession();
                root.failed(root.plain(message) || "The login needs more than a password, which this screen can't ask for. Use a text console (Ctrl+Alt+F2).");
            } else if (error && message) {
                root.message = root.plain(message);
            }
        }
        function onAuthFailure(message) {
            root.failed(/locked|expired|faillock/i.test(message) ? root.plain(message) : "That password isn't right. Try again.");
        }
        function onReadyToLaunch() {
            root.checking = false;
            root.launching = true;
            root.save();
            root.launchAnimationRequested();
            launchTimer.restart();
        }
        function onError(error) {
            // Quickshell cancels the greetd session after a wrong password
            // and greetd answers that cancel with an error: not news.
            if (!root.checking && !root.launching) { console.log("greeter: greetd:", error); return; }
            root.pending = "";
            root.checking = false;
            root.launching = false;
            root.message = "Something went wrong talking to the login service: " + error;
        }
    }
    // Let the fade-out play, then hand over to greetd.
    Timer {
        id: launchTimer
        interval: 450
        onTriggered: {
            const s = root.session;
            if (root.dryRun) { console.log("greeter: would launch", s.exec, JSON.stringify(root.environment(s))); return; }
            Greetd.launch([root.command(s)], root.environment(s), true);
        }
    }
    // greetd runs the command through `sh -c` after sourcing /etc/profile;
    // strip the .desktop field codes.
    function command(s) { return s.exec.replace(/\s+%[a-zA-Z]/g, "").trim(); }
    function environment(s) {
        const names = (s.desktopNames && s.desktopNames.length) ? s.desktopNames.join(":") : s.id;
        return ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=" + names,
                "XDG_SESSION_DESKTOP=" + s.id, "DESKTOP_SESSION=" + s.id];
    }

    // ------------------------------------------------------------- power

    // Through logind (systemctl), which polkit allows for the active local
    // session, the greeter's included. Refused (someone else still logged
    // in, an inhibitor) means a message, not a password prompt.
    function power(what) {
        if (root.dryRun) { console.log("greeter: would", what); return; }
        powerProc.what = what;
        powerProc.command = ["systemctl", what];
        powerProc.running = true;
    }
    Process {
        id: powerProc
        property string what: ""
        stderr: StdioCollector { id: powerErr }
        onExited: code => {
            if (code === 0) return;
            const verb = powerProc.what === "suspend" ? "go to sleep" : powerProc.what === "reboot" ? "restart" : "shut down";
            root.message = /interactive authentication|Access denied|logged in/i.test(powerErr.text)
                ? "The computer can't " + verb + " from here while someone else is still logged in."
                : "The computer couldn't " + verb + ": " + powerErr.text.trim();
        }
    }

    // Caps Lock: the keyboard LEDs (Qt doesn't report the lock state).
    Timer {
        interval: 400
        repeat: true
        running: root.user !== null && !root.launching
        onTriggered: caps.running = true
    }
    Process {
        id: caps
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.capsLock = /[1-9]/.test(text) }
    }

    // Test hooks (`quickshell ipc -p .../greeter.qml call greeter ...`):
    // only with HEARTH_GREETER_TEST=1.
    readonly property bool testMode: Quickshell.env("HEARTH_GREETER_TEST") === "1"
    signal testShotRequested(string path)
    IpcHandler {
        target: "greeter"
        function state(): string {
            return JSON.stringify({ users: root.users.map(u => u.name), user: root.user ? root.user.name : "",
                                    session: root.sessionId, checking: root.checking, launching: root.launching,
                                    message: root.message, greetd: Greetd.available ? GreetdState.toString(Greetd.state) : "unavailable" });
        }
        function shot(path: string): void { if (root.testMode) root.testShotRequested(path); }
    }
}
