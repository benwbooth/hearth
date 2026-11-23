import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../../services"
import "../.."
import "AccountSetups.js" as Setups

// Settings > Accounts: your online accounts, set up once for every app
// (mail, calendars and contacts in almanac; servers and Google documents in
// grove; …). Kept by the accounts service (helpers/hearth-accounts: D-Bus
// io.github.benwbooth.Accounts, passwords and sign-ins in the keyring).
// Google, Microsoft, Yahoo, AOL, Dropbox and Box first need a one-time app
// registration on their developer site: a step-by-step guide opens each
// page, shows a drawing of it with what to use ringed, and says what to do.
// Cloud drives (rclone) are their own section below (CloudDrivesPane.qml).
ColumnLayout {
    id: pane
    spacing: 14
    // Where to start (Settings opened as "accounts:<arg>"): "add",
    // "setup:<provider>[:<step>]", "mail:<preset>", "server", "nextcloud",
    // "signin:<provider>", or an account's id (shown first).
    property string arg: ""
    onArgChanged: Qt.callLater(applyArg)
    function applyArg() {
        const a = arg.split(":");
        if (a[0] === "add") page = "add";
        else if (a[0] === "setup") { provider = a[1]; againId = ""; step = parseInt(a[2]) || 0; page = "setup"; showStep(); }
        else if (a[0] === "mail") newMail(presets.find(p => p.id === a[1]) || { id: "other", name: "Other mail account", detail: "" });
        else if (a[0] === "server") edit({ kind: "server", protocol: "sftp" });
        else if (a[0] === "nextcloud") page = "nextcloud";
        else if (a[0] === "signin") { provider = a[1]; page = "signin"; busy = true; }
    }

    // ---------------------------------------------------------------- state

    property var accounts: []
    property var registrations: ({})
    property var presets: []
    property bool loaded: false
    property string loadError: ""
    // "list" | "add" | "mail" | "server" | "nextcloud" | "setup" | "signin"
    property string page: "list"
    property string provider: ""        // the sign-in provider being set up / signed in
    property string againId: ""         // signing in again to this account
    property int step: 0                // setup guide step (0-based)
    property var opened: ({})           // guide pages already opened (provider:step)
    property string status: ""
    property bool statusBad: false
    property bool busy: false
    property string signInUrl: ""
    property var preset: null           // the mail service picked
    property string editId: ""          // the account a form changes ("" = new)

    readonly property string browser: Quickshell.env("HEARTH_ACCOUNTS_BROWSER") || "xdg-open"
    readonly property var kindNames: ({ google: "Google", microsoft: "Microsoft", yahoo: "Yahoo", aol: "AOL", dropbox: "Dropbox", box: "Box",
                                        nextcloud: "Nextcloud", mail: "Mail", server: "Server" })
    readonly property var kindColors: ({ google: "#4285f4", microsoft: "#00a4ef", yahoo: "#6001d2", aol: "#3d6fe0", dropbox: "#0061fe", box: "#0061d5",
                                         nextcloud: "#0082c9", mail: "#8e8e93", server: "#5b6370" })
    readonly property var useNames: ({ mail: "Mail", calendar: "Calendars", contacts: "Contacts", drive: "Attachments as links", files: "Files" })

    function say(msg, bad) { status = msg; statusBad = !!bad; }
    function openUrl(url) { if (url) run([browser, url], null, null); }
    function reg(p) { return registrations[p] || {}; }

    // ---------------------------------------------------------------- helper

    // One helper call: cmd, extra environment, done(result object).
    Component {
        id: runner
        Process {
            id: proc
            property var done: null
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = null;
                    const lines = text.trim().split("\n").filter(l => l.trim() !== "");
                    try { r = JSON.parse(lines[lines.length - 1]); } catch (e) {}
                    if (proc.done) proc.done(r || { ok: false, error: "The accounts service didn't answer." });
                    proc.destroy();
                }
            }
        }
    }
    function run(cmd, env, done) {
        const p = runner.createObject(pane, { command: cmd, done: done });
        if (env) p.environment = env;
        p.running = true;
    }

    function refresh() {
        run(["hearth-accounts", "list"], null, r => {
            pane.loaded = true;
            if (!r.ok) { pane.loadError = r.error || "The accounts service isn't running."; return; }
            pane.loadError = "";
            pane.accounts = r.accounts;
            pane.registrations = r.registrations;
        });
    }
    Component.onCompleted: {
        refresh();
        run(["hearth-accounts", "presets"], null, r => { if (r.ok) { pane.presets = r.presets; if (pane.arg.indexOf("mail:") === 0) pane.applyArg(); } });
    }
    // Changes made anywhere (apps, a sign-in finishing) show at once.
    Process {
        running: true
        command: ["hearth-accounts", "watch"]
        stdout: SplitParser { onRead: line => { if (line.indexOf("changed") >= 0) pane.refresh(); } }
    }

    // ---------------------------------------------------------------- actions

    function startProvider(p, aid) {
        provider = p; againId = aid || ""; say("", false);
        if (reg(p).ready) signIn();
        else { step = 0; page = "setup"; showStep(); }
    }
    function showStep() {
        const s = Setups.steps(provider, reg(provider).project)[step];
        const key = provider + ":" + step;
        if (s && s.url && !opened[key]) { const o = opened; o[key] = true; opened = o; openUrl(s.url); }
    }
    function signIn() {
        page = "signin"; busy = true; signInUrl = ""; say("", false);
        const arg = provider === "nextcloud" ? ncServer.text.trim() : againId;
        // The service opens the page itself; this waits for the outcome.
        run(["hearth-accounts", "sign-in", provider, arg], { HEARTH_ACCOUNTS_BROWSER: browser }, r => {
            pane.busy = false;
            if (r.ok && r.id) {
                pane.page = "list";
                pane.say((pane.againId ? "Signed in again" : "Added") + (r.email ? " " + r.email : "") + ". Your apps use it from now on.", false);
                pane.refresh();
            } else if (r.cancelled) {
                pane.page = "list";
            } else {
                pane.say(r.error || "Sign-in failed.", true);
            }
        });
    }
    function saveRegistration(values) {
        const p = provider;
        run(["hearth-accounts", "registration", p, JSON.stringify(values)], null, r => {
            if (!r.ok) { pane.say(r.error, true); return; }
            pane.refresh();
            Qt.callLater(() => pane.signIn());
        });
    }
    function remove(a) {
        run(["hearth-accounts", "remove", a.id], null, r => {
            pane.say(r.ok ? a.name + " was removed. Apps stop using it; what they downloaded stays." : r.error, !r.ok);
            pane.refresh();
        });
    }
    function test(a) {
        say("Trying " + a.name + "…", false);
        run(["hearth-accounts", "test", a.id], null, r => pane.say(r.ok ? (r.detail || "It works.") : r.error, !r.ok));
    }
    function saveRecord(rec, done) {
        busy = true;
        run(["hearth-accounts", "save", "-"], { HEARTH_ACCOUNTS_INPUT: JSON.stringify(rec) }, r => {
            pane.busy = false;
            if (!r.ok) { pane.say(r.error, true); return; }
            pane.refresh();
            if (done) done(r.id);
        });
    }

    // ---------------------------------------------------------------- list

    Label {
        Layout.fillWidth: true
        visible: pane.page === "list"
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        color: Theme.fgDim
        text: "Set up an account once here and every app uses it: mail, calendars and contacts in your mail app, servers and Google documents in the file manager. Passwords and sign-ins are kept in your keyring."
    }

    Label {
        visible: pane.loadError !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        color: Theme.bad
        text: pane.loadError
    }

    SettingsGroup {
        visible: pane.page === "list" && pane.accounts.length > 0
        Repeater {
            model: pane.accounts
            SettingsRow {
                id: arow
                required property var modelData
                label: modelData.name + (modelData.email && modelData.email !== modelData.name ? "  ·  " + modelData.email : "")
                note: modelData.signed_out ? "Signed out — " + (pane.kindNames[modelData.kind] || "") + " ended the sign-in. Sign in again; nothing is lost."
                    : (pane.kindNames[modelData.kind] || modelData.kind) + (modelData.kind === "server" ? " (" + (modelData.protocol || "").toUpperCase() + ", " + modelData.host + ")" : "")
                      + ((modelData.uses || []).length ? " · " + modelData.uses.map(u => pane.useNames[u] || u).join(", ") : "")
                Row {
                    spacing: 6
                    PushButton {
                        visible: arow.modelData.kind in pane.registrations
                        text: arow.modelData.signed_out ? "Sign In Again" : "Sign In Again…"
                        primary: !!arow.modelData.signed_out
                        tooltip: "Sign in on " + (pane.kindNames[arow.modelData.kind] || "") + "'s page again (to allow more, or after it signed you out)"
                        onClicked: pane.startProvider(arow.modelData.kind, arow.modelData.id)
                    }
                    PushButton {
                        visible: arow.modelData.kind === "mail" || arow.modelData.kind === "server"
                        text: "Edit…"
                        onClicked: pane.edit(arow.modelData)
                    }
                    PushButton { text: "Try"; tooltip: "Check that it signs in"; onClicked: pane.test(arow.modelData) }
                    PushButton { text: "Remove"; destructive: true; onClicked: confirm.ask(arow.modelData) }
                }
            }
        }
    }
    // Remove: asked once, in place.
    SettingsGroup {
        id: confirm
        property var acct: null
        function ask(a) { acct = a; }
        visible: pane.page === "list" && acct !== null
        SettingsRow {
            label: confirm.acct ? "Remove " + confirm.acct.name + "?" : ""
            note: "Your apps stop using it. Nothing is deleted on the server; mail and files the apps downloaded stay until you remove them there."
            Row {
                spacing: 6
                PushButton { text: "Cancel"; onClicked: confirm.acct = null }
                PushButton { text: "Remove"; destructive: true; onClicked: { pane.remove(confirm.acct); confirm.acct = null; } }
            }
        }
    }
    Label {
        visible: pane.page === "list" && pane.loaded && pane.accounts.length === 0 && pane.loadError === ""
        color: Theme.fgDim
        text: "No accounts yet."
    }
    RowLayout {
        visible: pane.page === "list"
        PushButton { text: "Add Account…"; primary: true; enabled: pane.loadError === ""; onClicked: { pane.page = "add"; pane.say("", false); } }
        Item { Layout.fillWidth: true }
    }
    Label {
        visible: pane.status !== "" && pane.page !== "signin"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        color: pane.statusBad ? Theme.bad : Theme.good
        text: pane.status
    }

    // Cloud drives (rclone): their own section.
    Loader {
        Layout.fillWidth: true
        Layout.topMargin: 10
        visible: pane.page === "list" && status === Loader.Ready
        source: "CloudDrivesPane.qml"
    }

    // ---------------------------------------------------------------- add

    component Choice: MouseArea {
        id: ch
        property string title
        property string detail
        property string kind
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 52
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: picked()
        Rectangle { anchors.fill: parent; radius: Theme.radius; color: ch.containsMouse ? Theme.hover : "transparent"; border.color: Theme.border }
        Rectangle {
            id: badge
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            color: pane.kindColors[ch.kind] || Theme.accent
            Label { x: (parent.width - implicitWidth) / 2; anchors.verticalCenter: parent.verticalCenter; text: ch.title.charAt(0); color: "white"; font.weight: Font.Bold }
        }
        Column {
            anchors.left: badge.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            Label { text: ch.title; font.weight: Font.DemiBold; width: parent.width }
            Label { text: ch.detail; color: Theme.fgDim; font.pointSize: Theme.smallFontSize; width: parent.width }
        }
    }

    ColumnLayout {
        visible: pane.page === "add"
        Layout.fillWidth: true
        spacing: 8
        Label { text: "Mail, calendars and contacts"; font.weight: Font.DemiBold }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: pane.presets
                Choice {
                    required property var modelData
                    title: modelData.name
                    detail: modelData.detail + (modelData.how === "oauth" && !pane.reg(modelData.id).ready ? " (one-time setup first)" : "")
                    kind: modelData.how === "oauth" ? modelData.id : "mail"
                    onPicked: modelData.how === "oauth" ? pane.startProvider(modelData.id, "") : pane.newMail(modelData)
                }
            }
        }
        Label { Layout.topMargin: 6; text: "Files"; font.weight: Font.DemiBold }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Choice { title: "File Server"; detail: "SFTP (SSH), Windows share (SMB) or WebDAV"; kind: "server"; onPicked: pane.edit({ kind: "server", protocol: "sftp" }) }
            Choice { title: "Nextcloud"; detail: "Your Nextcloud or ownCloud server"; kind: "nextcloud"; onPicked: { pane.page = "nextcloud"; pane.say("", false); } }
            Choice { title: "Dropbox"; detail: "Big mail attachments sent as links" + (pane.reg("dropbox").ready ? "" : " (one-time setup first)"); kind: "dropbox"; onPicked: pane.startProvider("dropbox", "") }
            Choice { title: "Box"; detail: "Big mail attachments sent as links" + (pane.reg("box").ready ? "" : " (one-time setup first)"); kind: "box"; onPicked: pane.startProvider("box", "") }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
            text: "Google Drive and OneDrive come with your Google or Microsoft account. Other cloud drives (pCloud, MEGA, S3, …) are under Cloud Drives."
        }
        RowLayout { PushButton { text: "Back"; onClicked: pane.page = "list" } }
    }

    // ---------------------------------------------------------------- setup guide

    ColumnLayout {
        id: guide
        visible: pane.page === "setup"
        Layout.fillWidth: true
        spacing: 10
        readonly property var steps: Setups.steps(pane.provider, pane.reg(pane.provider).project)
        readonly property var cur: steps[pane.step] || null
        readonly property bool last: pane.step === steps.length - 1
        readonly property var fields: Setups.fields(pane.provider)
        property var values: ({})
        Label {
            text: "Set up " + (pane.kindNames[pane.provider] || "") + " sign-in — step " + (pane.step + 1) + " of " + guide.steps.length
            font.pointSize: Theme.fontSize + 2
            font.weight: Font.Bold
        }
        Label {
            visible: pane.step === 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            color: Theme.fgDim
            text: (pane.kindNames[pane.provider] || "") + " only lets an app sign in with an app registration from its own developer site. Apps like Thunderbird come with one; here you make your own, once (a few minutes, free), and every app uses it. Each step opens its page in your browser."
        }
        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; text: guide.cur ? guide.cur.say : "" }
        // (Sibling files load through a Loader in Quickshell, not as types.)
        Loader {
            id: picture
            Layout.fillWidth: true
            Layout.preferredHeight: item ? item.implicitHeight : 0
            source: "StepPicture.qml"
            Binding { target: picture.item; property: "address"; value: guide.cur ? guide.cur.address : ""; when: !!picture.item }
            Binding { target: picture.item; property: "heading"; value: guide.cur ? guide.cur.heading : ""; when: !!picture.item }
            Binding { target: picture.item; property: "rows"; value: guide.cur ? guide.cur.rows : []; when: !!picture.item }
        }
        GridLayout {
            visible: guide.last
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 6
            Repeater {
                model: guide.last ? guide.fields.length * 2 : 0
                Item {
                    required property int index
                    readonly property var f: guide.fields[Math.floor(index / 2)]
                    Layout.fillWidth: index % 2 === 1
                    implicitHeight: 28
                    implicitWidth: index % 2 === 0 ? lab.implicitWidth : 200
                    Label { id: lab; visible: index % 2 === 0; anchors.verticalCenter: parent.verticalCenter; text: parent.f.label; color: Theme.fgDim }
                    TextBox {
                        visible: index % 2 === 1
                        anchors.fill: parent
                        placeholder: parent.f.placeholder || ""
                        input.echoMode: parent.f.secret ? TextInput.Password : TextInput.Normal
                        onTextChanged: { const v = Object.assign({}, guide.values); v[parent.f.key] = text; guide.values = v; }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            PushButton { text: "Back"; onClicked: { if (pane.step > 0) { pane.step--; pane.showStep(); } else pane.page = "add"; } }
            PushButton { visible: !!(guide.cur && guide.cur.url); text: "Open This Page Again"; tooltip: guide.cur ? guide.cur.url : ""; onClicked: pane.openUrl(guide.cur.url) }
            PushButton { visible: guide.last && pane.provider === "google"; text: "Load File…"; tooltip: "The client_secret_….json file from Download JSON"; onClicked: clientFile.open() }
            Item { Layout.fillWidth: true }
            PushButton { visible: !guide.last; text: "Next"; primary: true; onClicked: { pane.step++; pane.showStep(); } }
            PushButton {
                visible: guide.last
                text: "Save and Sign In"
                primary: true
                enabled: Setups.valid(pane.provider, guide.values)
                onClicked: {
                    const v = {};
                    for (const f of guide.fields) v[f.key] = (guide.values[f.key] || "").trim();
                    pane.saveRegistration(v);
                }
            }
        }
        Label { visible: pane.status !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: pane.statusBad ? Theme.bad : Theme.good; text: pane.status }
    }
    FileDialog {
        id: clientFile
        title: "Load the downloaded client file"
        nameFilters: ["Google client file (*.json)", "All files (*)"]
        onAccepted: pane.run(["hearth-accounts", "load-registration", pane.provider, decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))], null, r => {
            if (!r.ok) { pane.say(r.error, true); return; }
            pane.refresh();
            Qt.callLater(() => pane.signIn());
        })
    }

    // ---------------------------------------------------------------- signing in

    SettingsGroup {
        visible: pane.page === "signin"
        Column {
            width: parent.width
            spacing: 10
            topPadding: 12
            bottomPadding: 12
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                font.weight: Font.DemiBold
                text: pane.busy ? "Sign in on " + (pane.kindNames[pane.provider] || "the") + "'s page in your browser…" : "Sign-in didn't finish"
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                color: Theme.fgDim
                text: pane.provider === "google" ? "Choose the account you added as a test user. Google says “Google hasn't verified this app”: it's your own, so click Continue. Allow everything on the next page, so every app can use it."
                    : pane.provider === "yahoo" || pane.provider === "aol" ? "Sign in and press Agree. The page then shows a short code: copy it into the box below."
                    : pane.provider === "nextcloud" ? "Log in on your Nextcloud's page and grant access. Settings carries on by itself."
                    : "Sign in and allow access. Settings carries on by itself when you're done."
            }
            Row {
                visible: pane.busy && (pane.provider === "yahoo" || pane.provider === "aol")
                spacing: 6
                TextBox { id: codeBox; width: 260; placeholder: "Code from the sign-in page"; onAccepted: codeOk.clicked(null) }
                PushButton { id: codeOk; text: "Continue"; primary: true; enabled: codeBox.text.trim() !== ""; onClicked: pane.run(["hearth-accounts", "code", codeBox.text.trim()], null, null) }
            }
            Label { visible: pane.status !== ""; width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone; color: pane.statusBad ? Theme.bad : Theme.good; text: pane.status }
            Row {
                spacing: 6
                PushButton { visible: pane.busy; text: "Cancel"; onClicked: pane.run(["hearth-accounts", "cancel"], null, null) }
                PushButton { visible: !pane.busy; text: "Try Again"; primary: true; onClicked: pane.signIn() }
                PushButton {
                    visible: !pane.busy && pane.provider !== "nextcloud"
                    text: "Set Up Again…"
                    tooltip: "Go through the developer site steps again (wrong ID, or a new registration)"
                    onClicked: { pane.step = 0; pane.page = "setup"; pane.showStep(); }
                }
                PushButton { visible: !pane.busy; text: "Back"; onClicked: pane.page = "list" }
            }
        }
    }

    // ---------------------------------------------------------------- mail form

    function newMail(p) {
        preset = p; editId = "";
        for (const f of [mName, mEmail, mPassword, mUser, mImapHost, mImapPort, mSmtpHost, mSmtpPort, mCaldav, mCarddav]) f.text = "";
        mIncoming.value = p.incoming || "";
        if (p.imap) { mImapHost.text = p.imap[0]; mImapPort.text = String(p.imap[1]); }
        if (p.smtp) { mSmtpHost.text = p.smtp[0]; mSmtpPort.text = String(p.smtp[1]); }
        mCaldav.text = p.caldav || ""; mCarddav.text = p.carddav || "";
        mAdvanced.shown = p.id === "other" || p.id === "exchange";
        say("", false);
        page = "mail";
    }
    function edit(a) {
        say("", false);
        editId = a.id || "";
        if (a.kind === "server") {
            sProto.value = a.protocol || "sftp";
            sName.text = a.id ? a.name : ""; sHost.text = a.host || ""; sPort.text = a.port ? String(a.port) : "";
            sUser.text = a.user || ""; sPath.text = a.path || ""; sPassword.text = "";
            page = "server";
            return;
        }
        preset = { id: "other", name: "Mail", detail: "" };
        const m = a.mail || {};
        mName.text = a.full_name || ""; mEmail.text = a.email || ""; mPassword.text = ""; mUser.text = a.username || "";
        mIncoming.value = m.incoming || "";
        mImapHost.text = m.imap_host || ""; mImapPort.text = m.imap_port ? String(m.imap_port) : "";
        mSmtpHost.text = m.smtp_host || ""; mSmtpPort.text = m.smtp_port ? String(m.smtp_port) : "";
        mCaldav.text = a.caldav_url || ""; mCarddav.text = a.carddav_url || "";
        mAdvanced.shown = true;
        page = "mail";
    }
    function discover() {
        if (mEmail.text.indexOf("@") < 1 || (preset && preset.imap)) return;
        say("Looking up " + mEmail.text.split("@")[1] + "'s servers…", false);
        run(["hearth-accounts", "discover", mEmail.text.trim()], null, r => {
            if (!r.ok) { pane.say(r.error, true); mAdvanced.shown = true; return; }
            if (!mImapHost.text) { mImapHost.text = r.imap[0]; mImapPort.text = String(r.imap[1]); }
            if (!mSmtpHost.text && r.smtp) { mSmtpHost.text = r.smtp[0]; mSmtpPort.text = String(r.smtp[1]); }
            if (r.incoming !== undefined && mIncoming.value === "") mIncoming.value = r.incoming;
            if (r.username === "local" && !mUser.text) mUser.text = mEmail.text.split("@")[0];
            pane.say("Found " + r.imap[0] + ".", false);
        });
    }

    component FormRow: RowLayout {
        property alias label: fl.text
        default property alias content: holder.data
        Layout.fillWidth: true
        spacing: 10
        Label { id: fl; Layout.preferredWidth: 150; color: Theme.fgDim; horizontalAlignment: Text.AlignRight }
        RowLayout { id: holder; Layout.fillWidth: true; spacing: 6 }
    }

    ColumnLayout {
        visible: pane.page === "mail"
        Layout.fillWidth: true
        spacing: 8
        Label { text: pane.editId ? "Change " + mEmail.text : "Add " + (pane.preset ? pane.preset.name : "Mail"); font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold }
        Label {
            visible: !!(pane.preset && pane.preset.detail)
            Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: Theme.fgDim
            text: pane.preset ? pane.preset.detail : ""
        }
        PushButton { visible: !!(pane.preset && pane.preset.help); text: "Open the Page for an App Password"; onClicked: pane.openUrl(pane.preset.help) }
        FormRow { label: "Your name"; TextBox { id: mName; Layout.fillWidth: true; placeholder: "as people see it on your mail" } }
        FormRow { label: "Email address"; TextBox { id: mEmail; Layout.fillWidth: true; placeholder: "you@example.com"; input.onEditingFinished: pane.discover() } }
        FormRow { label: "Password"; TextBox { id: mPassword; Layout.fillWidth: true; input.echoMode: TextInput.Password; placeholder: pane.editId ? "leave empty to keep it" : (pane.preset && pane.preset.help ? "the app password" : "") } }
        PushButton { text: mAdvanced.shown ? "Hide Servers" : "Servers…"; onClicked: mAdvanced.shown = !mAdvanced.shown }
        ColumnLayout {
            id: mAdvanced
            property bool shown: false
            visible: shown
            Layout.fillWidth: true
            spacing: 8
            FormRow {
                label: "Incoming"
                Segmented {
                    id: mIncoming
                    value: ""
                    options: [{ label: "IMAP", value: "" }, { label: "POP", value: "pop" }, { label: "Exchange", value: "ews" }]
                    onPicked: v => value = v
                }
            }
            FormRow {
                label: mIncoming.value === "ews" ? "Exchange (EWS) address" : "Incoming server"
                TextBox { id: mImapHost; Layout.fillWidth: true; placeholder: mIncoming.value === "ews" ? "empty: found from your address" : "imap.example.com" }
                TextBox { id: mImapPort; visible: mIncoming.value !== "ews"; implicitWidth: 70; placeholder: mIncoming.value === "pop" ? "995" : "993" }
            }
            FormRow {
                visible: mIncoming.value !== "ews"
                label: "Outgoing server"
                TextBox { id: mSmtpHost; Layout.fillWidth: true; placeholder: "smtp.example.com" }
                TextBox { id: mSmtpPort; implicitWidth: 70; placeholder: "465" }
            }
            FormRow { label: "User name"; TextBox { id: mUser; Layout.fillWidth: true; placeholder: "empty: your email address" } }
            FormRow { visible: mIncoming.value !== "ews"; label: "Calendars (CalDAV)"; TextBox { id: mCaldav; Layout.fillWidth: true; placeholder: "optional" } }
            FormRow { visible: mIncoming.value !== "ews"; label: "Contacts (CardDAV)"; TextBox { id: mCarddav; Layout.fillWidth: true; placeholder: "optional" } }
        }
        Label { visible: pane.status !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: pane.statusBad ? Theme.bad : Theme.good; text: pane.status }
        RowLayout {
            PushButton { text: "Cancel"; onClicked: pane.page = pane.editId ? "list" : "add" }
            Item { Layout.fillWidth: true }
            PushButton {
                text: pane.editId ? "Save" : "Add Account"
                primary: true
                enabled: !pane.busy && mEmail.text.indexOf("@") > 0 && (pane.editId !== "" || mPassword.text !== "")
                         && (mIncoming.value === "ews" || mImapHost.text.trim() !== "")
                onClicked: {
                    const rec = { kind: "mail", email: mEmail.text.trim(), name: mEmail.text.trim(), full_name: mName.text.trim(),
                                  username: mUser.text.trim() || mEmail.text.trim(),
                                  mail: { incoming: mIncoming.value, imap_host: mImapHost.text.trim(), imap_port: parseInt(mImapPort.text) || (mIncoming.value === "pop" ? 995 : 993),
                                          smtp_host: mSmtpHost.text.trim(), smtp_port: parseInt(mSmtpPort.text) || 465 },
                                  caldav_url: mCaldav.text.trim(), carddav_url: mCarddav.text.trim() };
                    if (pane.editId) rec.id = pane.editId;
                    if (mPassword.text !== "") rec.password = mPassword.text;
                    pane.saveRecord(rec, id => {
                        mPassword.text = "";
                        pane.page = "list";
                        pane.test({ id: id, name: rec.email });
                    });
                }
            }
        }
    }

    // ---------------------------------------------------------------- server form

    ColumnLayout {
        visible: pane.page === "server"
        Layout.fillWidth: true
        spacing: 8
        Label { text: pane.editId ? "Change " + sName.text : "Add a File Server"; font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: Theme.fgDim
            text: "A computer or NAS your file manager connects to. SFTP is SSH (Linux, Macs with Remote Login, most NAS boxes), SMB is a Windows or Samba share, WebDAV a web folder."
        }
        FormRow {
            label: "Kind"
            Segmented { id: sProto; value: "sftp"; options: [{ label: "SFTP", value: "sftp" }, { label: "SMB", value: "smb" }, { label: "WebDAV", value: "webdav" }]; onPicked: v => value = v }
        }
        FormRow {
            label: sProto.value === "webdav" ? "Address" : "Server"
            TextBox { id: sHost; Layout.fillWidth: true; placeholder: sProto.value === "webdav" ? "https://dav.example.com/files" : "nas.local or 192.168.1.10" }
            TextBox { id: sPort; visible: sProto.value !== "webdav"; implicitWidth: 70; placeholder: sProto.value === "sftp" ? "22" : "445" }
        }
        FormRow { label: "User name"; TextBox { id: sUser; Layout.fillWidth: true } }
        FormRow { label: "Password"; TextBox { id: sPassword; Layout.fillWidth: true; input.echoMode: TextInput.Password; placeholder: pane.editId ? "leave empty to keep it" : (sProto.value === "sftp" ? "empty: use your SSH key" : "") } }
        FormRow { label: sProto.value === "smb" ? "Share and folder" : "Folder"; TextBox { id: sPath; Layout.fillWidth: true; placeholder: sProto.value === "smb" ? "share/folder (optional)" : "optional" } }
        FormRow { label: "Name"; TextBox { id: sName; Layout.fillWidth: true; placeholder: "as it shows in the sidebar" } }
        Label { visible: pane.status !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: pane.statusBad ? Theme.bad : Theme.good; text: pane.status }
        RowLayout {
            PushButton { text: "Cancel"; onClicked: pane.page = pane.editId ? "list" : "add" }
            Item { Layout.fillWidth: true }
            PushButton {
                text: pane.editId ? "Save" : "Add Server"
                primary: true
                enabled: !pane.busy && sHost.text.trim() !== ""
                onClicked: {
                    const rec = { kind: "server", protocol: sProto.value, host: sHost.text.trim(), port: parseInt(sPort.text) || 0,
                                  user: sUser.text.trim(), path: sPath.text.trim(), name: sName.text.trim() || sHost.text.trim() };
                    if (pane.editId) rec.id = pane.editId;
                    if (sPassword.text !== "") rec.password = sPassword.text;
                    pane.saveRecord(rec, id => { sPassword.text = ""; pane.page = "list"; pane.test({ id: id, name: rec.name }); });
                }
            }
        }
    }

    // ---------------------------------------------------------------- Nextcloud

    ColumnLayout {
        visible: pane.page === "nextcloud"
        Layout.fillWidth: true
        spacing: 8
        Label { text: "Add Nextcloud"; font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: Theme.fgDim
            text: "Type your Nextcloud's address. Its login page opens in your browser; once you grant access, Nextcloud hands over an app password of its own (your real password is never stored)."
        }
        FormRow { label: "Server"; TextBox { id: ncServer; Layout.fillWidth: true; placeholder: "cloud.example.com"; onAccepted: ncGo.clicked(null) } }
        RowLayout {
            PushButton { text: "Cancel"; onClicked: pane.page = "add" }
            Item { Layout.fillWidth: true }
            PushButton { id: ncGo; text: "Sign In"; primary: true; enabled: ncServer.text.trim() !== ""; onClicked: { pane.provider = "nextcloud"; pane.againId = ""; pane.signIn(); } }
        }
    }
}
