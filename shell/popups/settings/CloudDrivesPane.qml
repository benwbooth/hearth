import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../.."
import "RcloneGuides.js" as Guides
import "CloudIcons.js" as CloudIcons

// Settings > Accounts > Cloud Drives: the drives set up in rclone (Google
// Drive, OneDrive, Dropbox, S3, SFTP... every kind rclone knows), shared by
// every app that uses rclone (grove, mounts, backups). Add one with a guided
// wizard (CloudDriveWizard.qml): pick the kind, follow the
// steps on its website (pictures of the pages, opened for you), answer
// rclone's questions. Check or remove a drive here.
// Self-contained: fills its parent's width; sits as a section inside the
// Accounts pane or works on its own. Talks to helpers/hearth-rclone.
ColumnLayout {
    id: pane
    Layout.fillWidth: true
    width: parent ? parent.width : 600
    spacing: 10

    property string mode: "list"            // list | pick | wizard
    property var drives: []
    property bool loaded: false
    property var providers: []
    property var provider: null
    property string status: ""
    property bool statusBad: false
    property var tests: ({})                 // name -> { ok, text }
    property string confirmRemove: ""
    property string renaming: ""
    readonly property bool testMode: Quickshell.env("HEARTH_RCLONE_TEST") !== ""

    function say(msg, bad) { status = msg; statusBad = !!bad; }

    // ---------------------------------------------------------------- helper
    // call(args, cb(result), stdinLine): one hearth-rclone run.
    function call(args, cb, input) {
        const j = jobComp.createObject(pane, { command: ["hearth-rclone"].concat(args), cb: cb, input: input || "" });
        j.running = true;
        return j;
    }
    Component {
        id: jobComp
        Process {
            id: job
            property var cb
            property string input
            stdinEnabled: input !== ""
            onStarted: if (input !== "") write(input + "\n")
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = null;
                    try { r = JSON.parse(text.trim().split("\n").pop()); } catch (e) {}
                    if (!r) r = { ok: false, error: "hearth-rclone didn't answer (is rclone installed?)." };
                    if (job.cb) job.cb(r);
                    job.destroy();
                }
            }
        }
    }
    // Guides open their page in the browser (not in tests: logged instead).
    function openUrl(u) {
        if (testMode) { console.log("hearth-rclone test: would open " + u); return; }
        Qt.openUrlExternally(u);
    }
    function refresh() {
        call(["drives"], r => {
            pane.loaded = true;
            if (r.ok) pane.drives = r.drives; else pane.say(r.error, true);
        });
    }
    Component.onCompleted: refresh()

    // A kind's logo (CloudIcons.js, built into $HEARTH_CLOUD_ICONS), else a
    // theme icon. `key` is the guide key: the rclone type, or "s3:<provider>".
    readonly property string logoDir: Quickshell.env("HEARTH_CLOUD_ICONS") || ""
    function iconFor(key) {
        key = String(key || "");
        if (logoDir && CloudIcons.icons[key]) return logoDir + "/" + CloudIcons.file(key);
        const type = key.split(":")[0];
        if (type !== key && logoDir && CloudIcons.icons[type]) return logoDir + "/" + CloudIcons.file(type);
        if (["sftp", "ftp", "smb", "webdav", "http", "hdfs", "filescom"].indexOf(type) >= 0) return "network-server";
        if (type === "crypt") return "folder-locked";
        if (type === "local" || type === "alias" || type === "memory") return "folder";
        if (["union", "combine", "chunker", "hasher", "compress", "cache", "archive"].indexOf(type) >= 0) return "folder-cloud";
        if (type === "drive" || type === "google photos" || type === "google cloud storage") return "folder-gdrive";
        if (type === "dropbox") return "folder-dropbox";
        return "folder-cloud";
    }
    function typeTitle(type, summary) {
        const g = Guides.guides[type];
        if (type === "s3" && summary) {
            const sg = Guides.guides["s3:" + summary.split(" · ")[0]];
            if (sg) return sg.title;
        }
        return g ? g.title : type;
    }

    // Where to start, for Settings links: "" (the list), "add" (the
    // kinds), "add:<key>" (that kind's wizard, e.g. add:drive,
    // add:s3:Cloudflare, add:sftp), "edit:<drive name>".
    property string pendingKey: ""
    function open(arg) {
        arg = String(arg || "");
        if (arg.startsWith("add")) { pendingKey = arg.slice(4); startAdd(); }
        else if (arg.startsWith("edit:")) {
            const n = arg.slice(5);
            const go = () => { const d = pane.drives.find(x => x.name === n); if (d) pane.edit(d); };
            if (loaded) go(); else call(["drives"], r => { pane.loaded = true; if (r.ok) pane.drives = r.drives; go(); });
        } else { mode = "list"; wizLoader.active = false; }
    }
    function takePending() {
        if (!pendingKey) return;
        const p = providers.find(x => x.key === pendingKey);
        pendingKey = "";
        if (p) pick(p);
    }
    function startAdd() {
        mode = "pick"; say("", false);
        search.text = "";
        Qt.callLater(() => search.input.forceActiveFocus());
        if (!providers.length)
            call(["providers"], r => { if (r.ok) pane.providers = r.providers.filter(p => !(p.name === "s3" && !p.preset.provider)); else pane.say(r.error, true); pane.takePending(); });
        else takePending();
    }
    // Sibling files aren't types in Quickshell: the wizard loads by file.
    function pick(p) {
        provider = p; mode = "wizard";
        wizLoader.active = true;
        wizLoader.setSource("CloudDriveWizard.qml", { host: pane, provider: p });
    }
    // Every setting of a drive, rclone's advanced ones included.
    function edit(d) {
        const preset = {};
        provider = { key: d.type, name: d.type, title: typeTitle(d.type, d.summary), preset: preset };
        mode = "wizard";
        wizLoader.active = true;
        wizLoader.setSource("CloudDriveWizard.qml", { host: pane, provider: provider, editName: d.name });
    }
    function test(name) {
        const t = Object.assign({}, tests); t[name] = { ok: true, text: "Checking…" }; tests = t;
        call(["test", name], r => { const t2 = Object.assign({}, pane.tests); t2[name] = { ok: !!r.ok, text: r.ok ? r.summary : r.error }; pane.tests = t2; });
    }
    function remove(name) {
        confirmRemove = "";
        call(["delete", name], r => { if (r.ok) pane.say("Removed “" + name + "”.", false); else pane.say(r.error, true); pane.refresh(); });
    }
    function rename(old, nw) {
        renaming = "";
        if (!nw.trim() || nw.trim() === old) return;
        call(["rename", old, nw.trim()], r => { if (r.ok) pane.say("Renamed to “" + r.name + "”. Apps that remembered the old name need it picked again.", false); else pane.say(r.error, true); pane.refresh(); });
    }

    // ---------------------------------------------------------------- list
    RowLayout {
        visible: pane.mode === "list"
        Layout.fillWidth: true
        Label { text: "Cloud Drives"; font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold; Layout.fillWidth: true }
        PushButton {
            text: "Add Cloud Drive…"
            tooltip: "Google Drive, OneDrive, Dropbox, iCloud, S3, SFTP and about 70 more, with step-by-step help"
            onClicked: pane.startAdd()
        }
    }
    Label {
        visible: pane.mode === "list"
        Layout.fillWidth: true
        text: "Drives set up here are rclone's: the Files app and anything else that uses rclone can open them."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        visible: pane.mode === "list"
        Label {
            visible: pane.drives.length === 0
            width: parent.width
            height: 44
            text: pane.loaded ? "No cloud drives yet." : "Loading…"
            color: Theme.fgDim
        }
        Repeater {
            model: pane.drives
            Item {
                id: dr
                required property var modelData
                required property int index
                width: parent.width
                height: 54 + (testLine.visible ? testLine.implicitHeight + 4 : 0)
                readonly property var t: pane.tests[modelData.name]
                SettingsDivider { visible: dr.index > 0 }
                RowLayout {
                    x: 0
                    y: 9
                    width: parent.width
                    height: 36
                    spacing: 10
                    Icon { implicitSize: 28; name: pane.iconFor(dr.modelData.type === "s3" && dr.modelData.summary ? "s3:" + dr.modelData.summary.split(" · ")[0] : dr.modelData.type); fallback: "folder-cloud" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        visible: pane.renaming !== dr.modelData.name
                        Label { Layout.fillWidth: true; text: dr.modelData.name }
                        Label {
                            Layout.fillWidth: true
                            text: pane.typeTitle(dr.modelData.type, dr.modelData.summary) + (dr.modelData.summary ? "  ·  " + dr.modelData.summary : "")
                            color: Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                    TextBox {
                        id: renameBox
                        visible: pane.renaming === dr.modelData.name
                        Layout.fillWidth: true
                        onVisibleChanged: if (visible) { text = dr.modelData.name; input.forceActiveFocus(); input.selectAll(); }
                        onAccepted: pane.rename(dr.modelData.name, text)
                        input.Keys.onEscapePressed: pane.renaming = ""
                    }
                    PushButton {
                        visible: pane.renaming === dr.modelData.name
                        text: "Save"; primary: true
                        onClicked: pane.rename(dr.modelData.name, renameBox.text)
                    }
                    PushButton {
                        visible: pane.confirmRemove !== dr.modelData.name && pane.renaming !== dr.modelData.name
                        text: "Check"
                        tooltip: "See that the drive answers (and how full it is)"
                        onClicked: pane.test(dr.modelData.name)
                    }
                    PushButton {
                        visible: pane.confirmRemove !== dr.modelData.name && pane.renaming !== dr.modelData.name
                        text: "Settings…"
                        tooltip: "Change any of its settings (address, password, rclone's advanced options)"
                        onClicked: pane.edit(dr.modelData)
                    }
                    PushButton {
                        visible: pane.confirmRemove !== dr.modelData.name && pane.renaming !== dr.modelData.name
                        text: "Rename"
                        tooltip: "Change the name apps show for it"
                        onClicked: pane.renaming = dr.modelData.name
                    }
                    PushButton {
                        visible: pane.confirmRemove !== dr.modelData.name && pane.renaming !== dr.modelData.name
                        text: "Remove…"
                        destructive: true
                        tooltip: "Forget this drive on this computer (its files stay where they are)"
                        onClicked: pane.confirmRemove = dr.modelData.name
                    }
                    Label { visible: pane.confirmRemove === dr.modelData.name; text: "Remove it? Files stay online."; color: Theme.fgDim }
                    PushButton { visible: pane.confirmRemove === dr.modelData.name; text: "Keep"; onClicked: pane.confirmRemove = "" }
                    PushButton { visible: pane.confirmRemove === dr.modelData.name; text: "Remove"; destructive: true; onClicked: pane.remove(dr.modelData.name) }
                }
                Label {
                    id: testLine
                    visible: !!dr.t
                    x: 38
                    y: 48
                    width: parent.width - 38
                    text: dr.t ? dr.t.text : ""
                    color: !dr.t || dr.t.text === "Checking…" ? Theme.fgDim : dr.t.ok ? Theme.good : Theme.bad
                    font.pointSize: Theme.smallFontSize
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
            }
        }
    }

    // ---------------------------------------------------------------- pick
    RowLayout {
        visible: pane.mode === "pick"
        Layout.fillWidth: true
        spacing: 8
        Label { text: "Add a Cloud Drive"; font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold; Layout.fillWidth: true }
        PushButton { text: "Cancel"; onClicked: pane.mode = "list" }
    }
    TextBox {
        id: search
        visible: pane.mode === "pick"
        Layout.fillWidth: true
        placeholder: "Search: google, s3, nextcloud, sftp…"
        onAccepted: { const f = plist.model.find(p => !p.header); if (f) pane.pick(f); }
    }
    Rectangle {
        visible: pane.mode === "pick"
        Layout.fillWidth: true
        implicitHeight: 380
        radius: Theme.popupRadius
        color: Theme.bgAlt
        border.color: Theme.border
        clip: true
        Label {
            anchors.centerIn: parent
            visible: pane.providers.length === 0
            text: "Asking rclone which kinds it knows…"
            color: Theme.fgDim
        }
        ScrollAssist { flickable: plist }
        ListView {
            id: plist
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: {
                const q = search.text.trim().toLowerCase();
                const m = pane.providers.filter(p => {
                    if (!q) return true;
                    const g = Guides.guides[p.key] || {};
                    return (p.title + " " + p.description + " " + p.key + " " + (g.title || "")).toLowerCase().indexOf(q) >= 0;
                });
                const pop = m.filter(p => p.popular), rest = m.filter(p => !p.popular);
                return (pop.length ? [{ header: "Popular" }].concat(pop) : [])
                    .concat(rest.length ? [{ header: pop.length ? "Everything else" : "Matches" }] : []).concat(rest);
            }
            delegate: MouseArea {
                id: pr
                required property var modelData
                width: plist.width
                height: modelData.header ? 28 : 40
                hoverEnabled: !modelData.header
                cursorShape: modelData.header ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: if (!modelData.header) pane.pick(modelData)
                readonly property var g: modelData.header ? null : (Guides.guides[modelData.key] || null)
                Rectangle { anchors.fill: parent; radius: Theme.radius; color: pr.containsMouse ? Theme.hover : "transparent" }
                Label {
                    visible: !!pr.modelData.header
                    x: 8
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: pr.modelData.header || ""
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    visible: !pr.modelData.header
                    x: 8
                    width: parent.width - 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Icon { implicitSize: 22; name: pane.iconFor(pr.modelData.key || pr.modelData.name || ""); fallback: "folder-cloud" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label { Layout.fillWidth: true; text: pr.g && pr.g.title ? pr.g.title : (pr.modelData.title || "") }
                        Label {
                            Layout.fillWidth: true
                            text: pr.g && pr.g.need ? pr.g.need : (pr.modelData.description || "")
                            color: Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                    Label { text: pr.modelData.key || ""; color: Theme.fgDim; font.pointSize: Theme.smallFontSize }
                }
            }
        }
    }

    // ---------------------------------------------------------------- wizard
    // The wizard, made fresh for each drive.
    Loader {
        id: wizLoader
        Layout.fillWidth: true
        active: false
    }
    Connections {
        target: wizLoader.item
        ignoreUnknownSignals: true
        function onFinished(created) {
            const edited = wizLoader.item && wizLoader.item.editName !== "";
            pane.mode = "list";
            wizLoader.active = false;
            if (created) pane.say((edited ? "Saved “" : "Added “") + created + "”.", false);
            pane.refresh();
        }
    }

    Label {
        Layout.fillWidth: true
        visible: pane.status !== "" && pane.mode === "list"
        text: pane.status
        color: pane.statusBad ? Theme.bad : Theme.good
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // Test hooks (HEARTH_RCLONE_TEST=1, with RCLONE_CONFIG on a scratch
    // file): stand-ins for clicks.
    IpcHandler {
        target: "clouddrives-test"
        enabled: pane.testMode
        function add(): void { pane.startAdd(); }
        function find(q: string): void { search.text = q; }
        function pick(key: string): void { const p = pane.providers.find(x => x.key === key); if (p) pane.pick(p); }
        function next(): void { if (wizLoader.item) wizLoader.item.next(); }
        function back(): void { if (wizLoader.item) wizLoader.item.back(); }
        function set(name: string, value: string): void { if (wizLoader.item) wizLoader.item.setValue(name, value); }
        function answer(v: string): void { if (wizLoader.item) wizLoader.item.answer = v; }
        function advanced(): void { if (wizLoader.item) wizLoader.item.showAdvanced = !wizLoader.item.showAdvanced; }
        function signinPreview(): void { if (wizLoader.item) { wizLoader.item.lastAsked = "config_is_local"; wizLoader.item.busy = true; wizLoader.item.waitingLong = true; } }
        function cancel(): void { if (wizLoader.item) wizLoader.item.cancel(); else pane.mode = "list"; }
        function check(name: string): void { pane.test(name); }
        function edit(name: string): void { const d = pane.drives.find(x => x.name === name); if (d) pane.edit(d); }
        function page(): string { return pane.mode + (wizLoader.item ? ":" + wizLoader.item.page + ":" + wizLoader.item.stepIndex + ":" + wizLoader.item.error : ""); }
        function refresh(): void { pane.refresh(); }
        function open(arg: string): void { pane.open(arg); }
    }
}
