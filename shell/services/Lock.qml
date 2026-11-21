pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// hearth's lock screen (macOS 26 style; drawn by lock/LockScreen.qml with
// ext-session-lock: one surface per screen). This service holds the
// state and does the authentication; the surfaces only draw it.
//
// Locking: Super+L, the Lock Screen menu items, hot corners and the
// power button call lock("manual"); swayidle (services/Power.qml) runs
// `hearth-session lock idle` after the idle time, `hearth-session lock
// sleep --wait` before sleep and `hearth-session lock` for logind's Lock
// signal (`loginctl lock-session`, KDE Connect).
//
// Unlocking needs PAM: two conversations run side by side, the password
// one (service `hearth-lock`, else KDE's `kde`) when you press Return and
// the fingerprint one (`hearth-lock-fingerprint`, else `kde-fingerprint`)
// for as long as the lock screen is up, because pam_fprintd blocks its
// stack until a finger is read (kscreenlocker works the same way). The
// password lives only in `buffer` until it is handed to PAM, and is never
// logged or written anywhere.
//
// Only success() unlocks, and only a PAM success (or the grace period
// right after an idle lock) calls it: nothing else in the shell can, and
// a QML error elsewhere can't either. If hearth dies while locked the
// compositor keeps the session locked (ext-session-lock); the next hearth
// sees $XDG_RUNTIME_DIR/hearth-locked-$WAYLAND_DISPLAY and locks again.
//
//   hearth-ipc call lock lock [manual|idle|sleep]
//   hearth-ipc call lock isLocked | isSecure | state
//
// Tests: HEARTH_LOCK_PAM_DIR points PAM at a throwaway config directory
// (scripts can use pam_exec with a test password) and enables the
// testType/testKey/testClick IPC calls that stand in for a keyboard.
Singleton {
    id: root

    readonly property var cfg: Settings.lockScreen
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string pamDir: Quickshell.env("HEARTH_LOCK_PAM_DIR") || "/etc/pam.d"
    readonly property bool testMode: Quickshell.env("HEARTH_LOCK_PAM_DIR") !== ""
    readonly property string flagFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hearth-locked-" + (Quickshell.env("WAYLAND_DISPLAY") || "x")

    // ---- lock state
    property bool locked: false        // drives WlSessionLock.locked
    property bool secure: false        // the compositor confirmed (set by LockScreen)
    property string reason: ""         // manual | idle | sleep | restore
    property double lockedAt: 0
    property bool graceActive: false   // any input unlocks without a password
    property bool unlocking: false     // the unlock animation is running
    property string mainOutput: ""     // the screen with the clock and password field
    property double lastInput: 0

    signal unlockAnimationRequested()
    signal wrongPassword()
    signal userActivity()
    signal testShotRequested(string path)

    // ---- the password field
    property string buffer: ""
    readonly property int typed: buffer.length
    property bool fieldShown: false    // the password field is up (any key or click)
    property bool checking: false
    property string message: ""        // under the field: errors, PAM messages
    property int failures: 0
    property bool capsLock: false

    // ---- fingerprint
    // off | waiting | retry | failed | unavailable
    property string fpState: "off"
    property string fpMessage: ""
    property int fpRestarts: 0

    // ---- who
    property string realName: ""
    property string avatar: ""
    readonly property string displayName: realName || user
    readonly property string initials: {
        const parts = displayName.split(/\s+/).filter(p => p);
        return parts.length > 1 ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
                                : (parts[0] || "?").slice(0, 2).toUpperCase();
    }
    property int notificationCount: 0

    // Which PAM services exist (a missing one would fall to `other`, which
    // denies everything on NixOS).
    property string pwService: "hearth-lock"
    property string fpService: ""

    // ------------------------------------------------------------- actions

    function lock(why) {
        why = why || "manual";
        if (root.locked) {
            // Already locked: sleep (or a manual lock) ends the grace period.
            if (why !== "idle") root.graceActive = false;
            return;
        }
        probe.running = true;
        root.reason = why;
        root.lockedAt = Date.now();
        root.lastInput = Date.now();
        root.unlocking = false;
        root.buffer = "";
        root.message = "";
        root.failures = 0;
        root.fieldShown = false;
        root.checking = false;
        root.fpRestarts = 0;
        const g = Number(root.cfg.grace) || 0;
        root.graceActive = why === "idle" && g > 0;
        if (root.graceActive) { graceTimer.interval = g * 1000; graceTimer.restart(); }
        root.mainOutput = Compositor.focusedOutput || (Quickshell.screens.length ? Quickshell.screens[0].name : "");
        root.locked = true;
        secureWatch.restart();
        Quickshell.execDetached(["sh", "-c", 'umask 077; : > "$1"', "sh", root.flagFile]);
        console.info("hearth lock: locked (" + why + ")");
    }

    // Input on any lock surface: wakes the field, or unlocks in the grace
    // period.
    function activity() {
        root.lastInput = Date.now();
        root.userActivity();
        if (!root.locked || root.unlocking) return;
        if (root.graceActive) { root.success("grace"); return; }
        if (root.fpState === "unavailable" || root.fpState === "failed") fpRetry.restart();
    }
    function showField() {
        if (!root.locked || root.unlocking) return;
        root.fieldShown = true;
        hideField.restart();
    }
    function typeText(t) {
        activity();
        if (!root.locked || root.unlocking || root.graceActive) return;
        showField();
        if (root.checking) return;
        root.message = "";
        root.buffer += t;
    }
    function backspace(word) {
        activity();
        showField();
        if (root.checking) return;
        root.buffer = word ? "" : root.buffer.slice(0, -1);
    }
    function clearField() {
        activity();
        root.buffer = "";
        root.message = "";
        if (!root.checking) root.fieldShown = false;
    }
    function submit() {
        activity();
        showField();
        if (root.checking || root.unlocking || root.buffer === "") return;
        root.checking = true;
        root.message = "";
        pending.value = root.buffer;
        pw.config = root.pwService;
        if (!pw.start()) {
            root.checking = false;
            pending.value = "";
            root.message = "Can't check the password (PAM didn't start).";
        }
    }

    // The only way out. Runs the unlock animation; LockScreen calls
    // finishUnlock() when it is done.
    function success(how) {
        if (!root.locked || root.unlocking) return;
        console.info("hearth lock: unlocked (" + how + ")");
        root.unlocking = true;
        root.buffer = "";
        pending.value = "";
        root.graceActive = false;
        if (pw.active) pw.abort();
        if (fp.active) fp.abort();
        root.fpState = "off";
        root.unlockAnimationRequested();
        unlockFallback.restart();
    }
    function finishUnlock() {
        if (!root.unlocking) return;
        unlockFallback.stop();
        root.locked = false;
        root.unlocking = false;
        root.fieldShown = false;
        root.message = "";
        Quickshell.execDetached(["rm", "-f", root.flagFile]);
    }
    // The compositor never confirmed the lock, or ended it: hand over to
    // hyprlock when it is installed (the session must not stay open).
    function compositorEnded() {
        secureWatch.stop();
        root.locked = false;
        root.unlocking = false;
        root.buffer = "";
        pending.value = "";
        Quickshell.execDetached(["rm", "-f", root.flagFile]);
        fallbackLocker();
    }
    function fallbackLocker() {
        if (root.testMode || Quickshell.env("HEARTH_SESSION_DRYRUN") === "1") {
            console.warn("hearth lock: lock failed (test session: no hyprlock fallback)");
            return;
        }
        console.warn("hearth lock: lock failed, starting hyprlock if installed");
        Quickshell.execDetached(["sh", "-c", "command -v hyprlock >/dev/null && { pidof hyprlock >/dev/null || exec hyprlock; }"]);
    }
    Timer {
        id: secureWatch
        interval: 4000
        onTriggered: if (root.locked && !root.secure && !root.unlocking) root.compositorEnded()
    }
    onSecureChanged: if (secure) secureWatch.stop()

    // Should the animation not report back, unlock anyway.
    Timer { id: unlockFallback; interval: 1500; onTriggered: root.finishUnlock() }

    Timer {
        id: graceTimer
        onTriggered: root.graceActive = false
    }
    // macOS hides the field again after a while without typing.
    Timer {
        id: hideField
        interval: 60000
        onTriggered: if (!root.checking && root.buffer === "") root.fieldShown = false
    }

    // -------------------------------------------------------------- PAM

    // The password, between submit() and PAM's prompt; cleared at once.
    QtObject { id: pending; property string value: "" }

    PamContext {
        id: pw
        configDirectory: root.pamDir
        user: root.user
        onResponseRequiredChanged: {
            if (!responseRequired) return;
            if (pending.value !== "") {
                const v = pending.value;
                pending.value = "";
                respond(v);
            } else {
                // A second prompt (expired password, OTP...): not supported here.
                root.message = message || "Your password needs attention: log in on a console.";
                abort();
                root.checking = false;
            }
        }
        onPamMessage: if (messageIsError && !responseRequired) root.message = message
        onCompleted: result => {
            pending.value = "";
            root.checking = false;
            if (result === PamResult.Success) { root.success("password"); return; }
            if (result === PamResult.Error) {
                root.message = "Can't check the password (PAM error).";
                return;
            }
            root.failures++;
            root.buffer = "";
            root.message = root.failures >= 3 ? "Incorrect password. Caps Lock or the keyboard layout may be wrong." : "";
            root.wrongPassword();
        }
        onError: err => {
            pending.value = "";
            root.checking = false;
            root.message = "Can't check the password (" + PamError.toString(err) + ").";
            console.warn("hearth lock: PAM error", PamError.toString(err));
        }
    }

    readonly property bool fpWanted: root.locked && root.secure && !root.unlocking && !root.graceActive
                                     && !!root.cfg.fingerprint && root.fpService !== ""
    onFpWantedChanged: {
        if (fpWanted) { root.fpRestarts = 0; fpStart.restart(); }
        else { fpStart.stop(); fpRetry.stop(); if (fp.active) fp.abort(); root.fpState = "off"; }
    }
    Timer { id: fpStart; interval: 300; onTriggered: root.startFingerprint() }
    Timer {
        id: fpRetry
        interval: 1500
        onTriggered: if (root.fpWanted && !fp.active) root.startFingerprint()
    }
    function startFingerprint() {
        if (!root.fpWanted || fp.active) return;
        fp.config = root.fpService;
        root.fpMessage = "";
        if (fp.start()) root.fpState = "waiting";
        else root.fpState = "unavailable";
    }
    PamContext {
        id: fp
        configDirectory: root.pamDir
        user: root.user
        // The fingerprint stack never asks for text; if it falls through
        // to a password prompt (kde-fingerprint ends in pam_unix), stop.
        onResponseRequiredChanged: if (responseRequired) { abort(); root.fpFailed(true); }
        onPamMessage: {
            const m = message || "";
            if (/fail|no match|not match|didn.t match|try again/i.test(m)) {
                root.fpState = "retry";
                root.fpMessage = "Not recognised. Try again.";
                fpMsgReset.restart();
            } else if (/no devices|not available|unavailable|enrol/i.test(m)) {
                root.fpState = "unavailable";
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success) { root.success("fingerprint"); return; }
            root.fpFailed(result === PamResult.Error);
        }
        onError: err => root.fpFailed(true)
    }
    Timer { id: fpMsgReset; interval: 2500; onTriggered: if (root.fpState === "retry") { root.fpState = "waiting"; root.fpMessage = ""; } }
    function fpFailed(hard) {
        if (!root.fpWanted) return;
        root.fpRestarts++;
        // A reader that isn't there (or fprintd stopped for sleep) fails
        // straight away: try again a few times, then wait for input.
        if (root.fpRestarts > 4) { root.fpState = hard ? "unavailable" : "failed"; return; }
        root.fpState = hard ? "unavailable" : "retry";
        if (!hard) root.fpMessage = "Not recognised. Try again.";
        fpRetry.interval = hard ? 3000 : 1200;
        fpRetry.restart();
    }

    // ---------------------------------------------------- environment probes

    Process {
        id: probe
        command: ["sh", "-c", `
d="$1"
pw=""; for s in hearth-lock kde login; do [ -e "$d/$s" ] && { pw=$s; break; }; done
fp=""; if command -v fprintd-list >/dev/null 2>&1 || [ -n "$HEARTH_LOCK_PAM_DIR" ]; then
  for s in hearth-lock-fingerprint kde-fingerprint; do [ -e "$d/$s" ] && { fp=$s; break; }; done
fi
name=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)
av=""; for f in "/var/lib/AccountsService/icons/$USER" "$HOME/.face" "$HOME/.face.icon"; do [ -r "$f" ] && [ -s "$f" ] && { av=$f; break; }; done
printf '%s\\n%s\\n%s\\n%s\\n' "$pw" "$fp" "$name" "$av"`, "sh", root.pamDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                root.pwService = l[0] || "hearth-lock";
                root.fpService = l[1] || "";
                root.realName = l[2] || "";
                root.avatar = l[3] || "";
            }
        }
    }

    // Caps Lock: the keyboard LEDs (Qt doesn't report the lock state).
    Timer {
        interval: 400
        repeat: true
        running: root.locked && root.fieldShown
        onTriggered: caps.running = true
    }
    Process {
        id: caps
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.capsLock = /[1-9]/.test(text) }
    }

    Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: root.locked && !!root.cfg.showNotifications
        onTriggered: notif.running = true
    }
    Process {
        id: notif
        command: ["swaync-client", "-c"]
        stdout: StdioCollector { onStreamFinished: root.notificationCount = parseInt(text) || 0 }
    }

    // Screens off after a while without input (arbor wakes them on input).
    Timer {
        interval: 5000
        repeat: true
        running: root.locked && !root.unlocking && (Number(root.cfg.screenOff) || 0) > 0 && Compositor.isArbor
        property bool off: false
        onRunningChanged: off = false
        onTriggered: {
            const idleFor = Date.now() - root.lastInput;
            if (idleFor >= root.cfg.screenOff * 1000) {
                if (!off) { off = true; Compositor.arborAction("PowerOffMonitors", {}); }
            } else off = false;
        }
    }

    // A previous hearth died while locked: lock again.
    Component.onCompleted: {
        probe.running = true;
        restoreCheck.running = true;
    }
    Process {
        id: restoreCheck
        command: ["test", "-e", root.flagFile]
        onExited: code => { if (code === 0) root.lock("restore"); }
    }

    IpcHandler {
        target: "lock"
        function lock(why: string): void { root.lock(why || "manual"); }
        function isLocked(): bool { return root.locked; }
        function isSecure(): bool { return root.locked && root.secure; }
        function state(): string {
            return JSON.stringify({ locked: root.locked, secure: root.secure, reason: root.reason,
                                    grace: root.graceActive, field: root.fieldShown, typed: root.typed,
                                    checking: root.checking, message: root.message, failures: root.failures,
                                    fingerprint: root.fpState, fpService: root.fpService, pwService: root.pwService,
                                    mainOutput: root.mainOutput, capsLock: root.capsLock });
        }
        // Test sessions only (HEARTH_LOCK_PAM_DIR set): stand-ins for a keyboard.
        function testType(text: string): void { if (root.testMode) root.typeText(text); }
        function testKey(key: string): void {
            if (!root.testMode) return;
            if (key === "Return") root.submit();
            else if (key === "BackSpace") root.backspace(false);
            else if (key === "Escape") root.clearField();
            else root.activity();
        }
        function testShot(path: string): void { if (root.testMode) root.testShotRequested(path); }
        function testClick(): void { if (root.testMode) { root.activity(); root.showField(); } }
    }
}
