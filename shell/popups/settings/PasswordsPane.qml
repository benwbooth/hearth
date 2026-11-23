import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../.."

// Settings > Passwords & Keys: what's saved in the keyring (oo7, the Secret
// Service) and the SSH keys gcr-ssh-agent offers. helpers/hearth-keyring
// does the work; secret values are fetched only when you click Show or Copy
// and are forgotten again when the row closes.
ColumnLayout {
    id: pane
    spacing: 14

    property bool loaded: false
    property bool locked: false
    property string error: ""
    property var items: []
    property var ssh: []
    property string query: ""
    // The row whose details are open, and its shown password.
    property string open: ""
    property string revealed: ""
    property bool revealedBinary: false
    property string status: ""
    property bool statusBad: false
    property bool busy: false
    readonly property string testMode: Quickshell.env("HEARTH_TEST_PASSWORDS") || ""

    readonly property var sections: [
        { kind: "passwords", title: "Passwords", note: "Sign-ins for websites, mail and servers that apps saved here." },
        { kind: "sshpass", title: "SSH key passphrases", note: "Unlock your SSH keys without asking. Forget one and you're asked the next time the key is used." },
        { kind: "appkeys", title: "App encryption keys", note: "Apps such as your browser lock their own saved logins and cookies with these. Deleting one signs you out of everything in that app." },
        { kind: "other", title: "Other app data", note: "Tokens and settings apps keep here (accounts, sync, chat)." }
    ]

    function say(msg, bad) { status = msg; statusBad = !!bad; statusClear.restart(); }
    Timer { id: statusClear; interval: 6000; onTriggered: pane.status = "" }

    function matches(i) {
        const q = pane.query.trim().toLowerCase();
        if (!q) return true;
        return (i.title + " " + i.subtitle + " " + i.label + " " + Object.values(i.attributes).join(" ")).toLowerCase().indexOf(q) >= 0;
    }
    // One row per app or SSH key: an app saved under two names
    // (Code/code) and a passphrase saved both by gcr and by the older
    // askpass are one entry; changes and deletes go to every copy.
    function inSection(kind) {
        const rows = [];
        const byTitle = {};
        for (const i of pane.items) {
            if (i.kind !== kind || !pane.matches(i)) continue;
            const key = (kind === "appkeys" || kind === "sshpass") ? i.title.toLowerCase() : i.path;
            const r = byTitle[key];
            if (r) { r.paths.push(i.path); continue; }
            byTitle[key] = Object.assign({}, i, { paths: [i.path] });
            rows.push(byTitle[key]);
        }
        return rows;
    }
    // Sections folded away (App encryption keys starts folded: rarely needed).
    property var folded: ({ appkeys: true })
    function fold(kind, f) { const o = Object.assign({}, pane.folded); o[kind] = f; pane.folded = o; }

    // call(args, cb(result), stdinLine): one hearth-keyring run.
    function call(args, cb, input) {
        const j = jobComp.createObject(pane, { command: ["hearth-keyring"].concat(args), cb: cb || null, input: input || "" });
        j.running = true;
    }
    Component {
        id: jobComp
        Process {
            id: job
            property var cb
            property string input
            stdinEnabled: input !== ""
            onStarted: if (input !== "") { write(input + "\n"); input = ""; }
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = null;
                    try { r = JSON.parse(text.trim().split("\n").pop()); } catch (e) {}
                    if (!r) r = { ok: false, error: "hearth-keyring didn't answer." };
                    if (job.cb) job.cb(r);
                    job.destroy();
                }
            }
        }
    }

    function refresh() {
        call(["list"], r => {
            const first = !pane.loaded;
            pane.loaded = true;
            if (!r.ok) { pane.error = r.error; pane.items = []; pane.ssh = []; return; }
            pane.error = "";
            pane.locked = r.locked;
            pane.items = r.items;
            pane.ssh = r.ssh;
            // Screenshot tests: HEARTH_TEST_PASSWORDS=details opens the
            // first password with it shown.
            if (first && pane.testMode === "details" && pane.items.length) {
                const it = pane.inSection("passwords")[0] || pane.items[0];
                pane.open = it.path;
                pane.reveal(it.paths ? it.paths[0] : it.path);
            }
        });
    }
    function act(args, done, msg, input) {
        pane.busy = true;
        call(args, r => {
            pane.busy = false;
            if (r.ok) { if (msg) pane.say(msg); if (done) done(r); }
            else pane.say(r.error, true);
            pane.refresh();
        }, input);
    }
    function toggle(path) {
        pane.revealed = "";
        pane.revealedBinary = false;
        pane.open = pane.open === path ? "" : path;
    }
    function reveal(path) {
        call(["secret", path], r => {
            if (!r.ok) { pane.say(r.error, true); return; }
            pane.revealedBinary = !!r.binary;
            pane.revealed = r.binary ? r.size + " bytes of binary data" : r.secret;
            hideTimer.restart();
        });
    }
    Timer { id: hideTimer; interval: 30000; onTriggered: pane.revealed = "" }
    function fmtDate(s) { return s > 0 ? new Date(s * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat) : "—"; }

    Component.onCompleted: refresh()
    // The keyring can change underneath (apps saving, a login unlock).
    Timer { interval: 15000; running: pane.visible && pane.open === "" && !pane.busy; repeat: true; onTriggered: pane.refresh() }

    Label {
        Layout.fillWidth: true
        text: "Apps keep the passwords and sign-in keys they remember here, in your keyring. Logging in unlocks it with your login password, so you rarely need this page: it's for looking something up, changing or removing it."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    SettingsGroup {
        SettingsRow {
            label: !pane.loaded ? "Keyring" : pane.error ? "Keyring not available" : pane.locked ? "Keyring is locked" : "Keyring is unlocked"
            note: !pane.loaded ? "Looking…" : pane.error ? pane.error
                : pane.locked ? "Apps can't read their saved passwords until you unlock it."
                : "Apps can use their saved passwords. Locking asks for your password again before any app can."
            PushButton {
                visible: pane.loaded && !pane.error
                enabled: !pane.busy
                text: pane.locked ? "Unlock…" : "Lock"
                tooltip: pane.locked ? "Asks for the keyring's password (usually your login password)" : "Lock it now; it asks for the password the next time an app needs it"
                onClicked: pane.act([pane.locked ? "unlock" : "lock"], null, pane.locked ? "Unlocked." : "Locked.")
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Keyring password"
            note: "The same as your login password. Changing your password in a Terminal (passwd) changes it too."
            tip: "If they ever differ (an administrator reset your password, say), the first app that needs a saved password asks for the old one. Then run oo7-cli change-secret in a Terminal to switch the keyring to your new password. Help › Saved passwords explains more."
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: pane.loaded && !pane.error && !pane.locked
        spacing: 8
        TextBox {
            Layout.fillWidth: true
            placeholder: "Search saved passwords"
            onTextChanged: pane.query = text
        }
        PushButton {
            text: "Add Password…"
            tooltip: "Save a password for a website, router or server yourself"
            onClicked: { addBox.visible = !addBox.visible; if (addBox.visible) addName.input.forceActiveFocus(); }
        }
    }
    Label {
        Layout.fillWidth: true
        visible: pane.status !== ""
        text: pane.status
        color: pane.statusBad ? Theme.warn : Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    SettingsGroup {
        id: addBox
        visible: false
        Layout.fillWidth: true
        function reset() { addName.text = ""; addServer.text = ""; addUser.text = ""; addPass.text = ""; visible = false; }
        SettingsRow {
            label: "Name"
            note: "What to call it here, e.g. Home router."
            TextBox { id: addName; implicitWidth: 260; placeholder: "Name" }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Website or server"
            note: "Address, e.g. 192.168.1.1 or example.com."
            TextBox { id: addServer; implicitWidth: 260; placeholder: "example.com" }
        }
        SettingsDivider {}
        SettingsRow {
            label: "User name"
            note: "Optional."
            TextBox { id: addUser; implicitWidth: 260; placeholder: "User name" }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Password"
            TextBox { id: addPass; implicitWidth: 260; placeholder: "Password"; input.echoMode: TextInput.Password }
        }
        RowLayout {
            width: parent.width
            spacing: 8
            Item { Layout.fillWidth: true }
            PushButton { text: "Cancel"; onClicked: addBox.reset() }
            PushButton {
                text: "Save"
                primary: true
                enabled: addServer.text.trim() !== "" && addPass.text !== "" && !pane.busy
                onClicked: {
                    pane.act(["add", addName.text.trim(), addServer.text.trim(), addUser.text.trim()], null, "Saved.", addPass.text);
                    addBox.reset();
                }
            }
        }
        Item { width: 1; height: 8 }
    }

    Label {
        Layout.fillWidth: true
        visible: pane.loaded && pane.locked
        text: "Unlock the keyring to see what's saved."
        color: Theme.fgDim
    }

    Repeater {
        model: pane.loaded && !pane.locked && !pane.error ? pane.sections : []
        delegate: ColumnLayout {
            id: sec
            required property var modelData
            readonly property var rows: pane.inSection(modelData.kind)
            Layout.fillWidth: true
            spacing: 4
            visible: rows.length > 0
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: sec.modelData.title + "  (" + sec.rows.length + ")"
                    font.weight: Font.DemiBold
                }
                PushButton {
                    visible: sec.modelData.kind === "appkeys" || sec.modelData.kind === "other"
                    readonly property bool isFolded: !!pane.folded[sec.modelData.kind] && pane.query.trim() === ""
                    text: isFolded ? "Show" : "Hide"
                    tooltip: isFolded ? "List them" : "Fold this list away"
                    onClicked: pane.fold(sec.modelData.kind, !isFolded)
                }
            }
            Label {
                Layout.fillWidth: true
                text: sec.modelData.note
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            SettingsGroup {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !pane.folded[sec.modelData.kind] || pane.query.trim() !== ""
                Repeater {
                    model: sec.rows
                    delegate: Column {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool isOpen: pane.open === modelData.path
                        width: parent.width
                        SettingsDivider { visible: row.index > 0 }
                        SettingsRow {
                            label: row.modelData.title
                            note: row.modelData.subtitle
                            tip: row.modelData.label !== row.modelData.title ? "Saved as “" + row.modelData.label + "”" : ""
                            Row {
                                spacing: 6
                                PushButton {
                                    visible: row.modelData.kind !== "appkeys"
                                    text: "Copy"
                                    tooltip: "Copy the password; it's left out of the clipboard history and cleared after 45 seconds"
                                    onClicked: pane.act(["copy", row.modelData.paths[0]], null, "Copied. It's cleared from the clipboard in 45 seconds.")
                                }
                                PushButton {
                                    text: row.isOpen ? "Done" : "Details"
                                    tooltip: row.isOpen ? "Close" : "Show, change, rename or delete it"
                                    onClicked: pane.toggle(row.modelData.path)
                                }
                            }
                        }
                        Loader {
                            width: parent.width
                            active: row.isOpen
                            visible: active
                            sourceComponent: detailsComp
                            onLoaded: item.entry = row.modelData
                        }
                    }
                }
            }
        }
    }

    Component {
        id: detailsComp
        Column {
            id: det
            property var entry: ({})
            readonly property var attrList: Object.keys(entry.attributes || {}).sort().map(k => k + ": " + entry.attributes[k])
            width: parent ? parent.width : 400
            spacing: 6
            bottomPadding: 10

            SettingsRow {
                label: "Password"
                note: pane.revealed !== "" ? "" : "Hidden. It's hidden again after 30 seconds."
                Row {
                    spacing: 6
                    Label {
                        visible: pane.revealed !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 260)
                        text: pane.revealed
                        font.family: "monospace"
                        color: pane.revealedBinary ? Theme.fgDim : Theme.fg
                    }
                    PushButton {
                        text: pane.revealed !== "" ? "Hide" : "Show"
                        tooltip: pane.revealed !== "" ? "Hide it" : "Show the password here"
                        onClicked: pane.revealed !== "" ? pane.revealed = "" : pane.reveal(det.entry.path)
                    }
                }
            }
            SettingsRow {
                visible: (det.entry.paths || []).length === 1
                label: "Name"
                note: "Saved " + pane.fmtDate(det.entry.created) + ", changed " + pane.fmtDate(det.entry.modified)
                RowLayout {
                    spacing: 6
                    TextBox { id: nameBox; implicitWidth: 220; text: det.entry.label || "" }
                    PushButton {
                        text: "Rename"
                        enabled: nameBox.text.trim() !== "" && nameBox.text !== det.entry.label && !pane.busy
                        onClicked: pane.act(["rename", det.entry.path, nameBox.text.trim()], null, "Renamed.")
                    }
                }
            }
            SettingsRow {
                visible: det.entry.kind !== "appkeys"
                label: "New password"
                note: "Replaces the saved one."
                RowLayout {
                    spacing: 6
                    TextBox { id: newPass; implicitWidth: 220; placeholder: "New password"; input.echoMode: TextInput.Password }
                    PushButton {
                        text: "Change"
                        enabled: newPass.text !== "" && !pane.busy
                        onClicked: { pane.act(["set-secret"].concat(det.entry.paths), null, "Password changed.", newPass.text); newPass.text = ""; pane.revealed = ""; }
                    }
                }
            }
            Label {
                width: parent.width
                visible: det.attrList.length > 0
                text: ((det.entry.paths || []).length > 1 ? "Saved " + det.entry.paths.length + " times (under different names). " : "")
                    + "Looked up by: " + det.attrList.join(" · ")
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            RowLayout {
                width: parent.width
                spacing: 8
                Label {
                    Layout.fillWidth: true
                    visible: delConfirm.visible
                    text: det.entry.kind === "appkeys"
                        ? "Delete this key? " + det.entry.title + " can no longer read its saved logins and cookies: you'll be signed out everywhere in it."
                        : "Delete it? The app that saved it will ask for it again."
                    color: Theme.warn
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                Item { Layout.fillWidth: true; visible: !delConfirm.visible }
                PushButton {
                    visible: !delConfirm.visible
                    text: "Delete…"
                    destructive: true
                    tooltip: "Asks first"
                    onClicked: delConfirm.visible = true
                }
                Row {
                    id: delConfirm
                    visible: false
                    spacing: 6
                    PushButton { text: "Cancel"; onClicked: delConfirm.visible = false }
                    PushButton {
                        text: "Delete"
                        destructive: true
                        enabled: !pane.busy
                        onClicked: { pane.open = ""; pane.act(["delete"].concat(det.entry.paths), null, "Deleted."); }
                    }
                }
            }
        }
    }

    // SSH keys: what gcr-ssh-agent offers from ~/.ssh.
    Label {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: pane.loaded && pane.ssh.length > 0
        text: "SSH keys"
        font.weight: Font.DemiBold
    }
    Label {
        Layout.fillWidth: true
        Layout.topMargin: -10
        visible: pane.loaded && pane.ssh.length > 0
        text: "The keys in your .ssh folder. Each is unlocked the first time something uses it, with its saved passphrase or by asking you."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        visible: pane.loaded && pane.ssh.length > 0
        Repeater {
            model: pane.ssh
            delegate: Column {
                id: key
                required property var modelData
                required property int index
                width: parent.width
                SettingsDivider { visible: key.index > 0 }
                SettingsRow {
                    label: key.modelData.name
                    note: [key.modelData.type, key.modelData.comment,
                           key.modelData.loaded ? "unlocked now" : "locked",
                           key.modelData.saved ? "passphrase saved" : "passphrase not saved"].filter(s => s).join(" · ")
                    tip: key.modelData.fingerprint
                    Row {
                        spacing: 6
                        PushButton {
                            visible: key.modelData.loaded
                            text: "Lock"
                            tooltip: "Take it out of memory; it's unlocked again the next time it's used"
                            onClicked: pane.act(["ssh-lock", key.modelData.path], null, key.modelData.name + " locked.")
                        }
                        PushButton {
                            visible: key.modelData.saved
                            text: "Forget Passphrase"
                            tooltip: "Remove the saved passphrase; you're asked for it the next time"
                            onClicked: pane.act(["ssh-forget", key.modelData.path], null, "Passphrase for " + key.modelData.name + " forgotten.")
                        }
                    }
                }
            }
        }
    }
}
