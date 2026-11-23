import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../.."
import "RcloneGuides.js" as Guides

// Add Cloud Drive, one page at a time:
//   name  -> what it is, what you need, a name for the drive
//   step  -> the guide's website chores (make a key, an app password...):
//            plain instruction, a drawn picture of the page with what to
//            use ringed, its page opened once when shown
//   form  -> rclone's questions for this kind of drive as form rows (the
//            guide's hint under each), advanced ones folded away with
//            their defaults
//   ask   -> the drive's own follow-up questions (rclone's config state
//            machine), one at a time; a browser sign-in shows a picture
//            of that page while rclone waits for it
//   done  -> checks the drive answers
// Everything goes through helpers/hearth-rclone (rclone's own config).
ColumnLayout {
    id: wiz
    required property var host          // CloudDrivesPane: call(), openUrl()
    required property var provider      // { key, name, title, preset }
    property string editName: ""        // change this drive's settings instead
    signal finished(string created)     // "" when cancelled
    spacing: 12

    readonly property var guide: Guides.guides[provider.key] || Guides.guides[provider.name] || ({})
    // Koofr and S3 ask for a provider first; its guide adds hints.
    readonly property string providerValue: values.provider || (provider.preset || {}).provider || ""
    readonly property var subGuide: provider.name === "s3" && providerValue ? (Guides.guides["s3:" + providerValue] || {}) : {}
    readonly property var fields: Object.assign({}, guide.fields || {}, subGuide.fields || {})
    readonly property var steps: guide.steps || []

    property string page: "name"
    property int stepIndex: 0
    property var options: []
    property var values: ({})
    property var original: ({})         // edit: the settings as they were
    property var secrets: []            // edit: passwords/keys already set
    property bool showAdvanced: false
    property bool busy: false
    property bool waitingLong: false
    property bool created: false
    property string error: ""
    property var step: ({})             // {state, option} from rclone
    property string answer: ""
    property string lastAsked: ""
    property string testResult: ""
    property bool testOk: false
    property var opened: ({})

    function hintFor(n) { return fields[n] || ""; }
    function matches(p) {
        if (!p) return true;
        const neg = p.startsWith("!");
        const has = (neg ? p.slice(1) : p).split(",").indexOf(providerValue) >= 0;
        return neg ? !has : has;
    }
    // rclone's questions for this drive and provider: first of each name
    // that applies (Koofr has three "password" questions, one per provider).
    function shown(advanced) {
        const seen = {}, res = [];
        for (const o of options) {
            if (!!o.Advanced !== advanced || seen[o.Name] || !matches(o.Provider)) continue;
            if ((provider.preset || {})[o.Name] !== undefined) continue;
            seen[o.Name] = true;
            res.push(o);
        }
        return res;
    }
    readonly property var basicOptions: { void values; return shown(false); }
    readonly property var advancedOptions: { void values; return shown(true); }
    readonly property var missing: basicOptions.filter(o => o.Required && !(values[o.Name] || o.DefaultStr))
    function valueOf(o) { return values[o.Name] !== undefined ? values[o.Name] : (o.IsPassword ? "" : (o.DefaultStr || "")); }
    function hintFor2(o) {
        const h = hintFor(o.Name);
        return editName !== "" && secrets.indexOf(o.Name) >= 0 ? "Already set; leave empty to keep it. " + h : h;
    }
    function setValue(n, v) { const c = Object.assign({}, values); c[n] = v; values = c; }

    Component.onCompleted: {
        if (editName !== "") {
            nameField.text = editName;
            page = "form";
            host.call(["get", editName], r => {
                if (!r.ok) { wiz.error = r.error; return; }
                wiz.original = r.values; wiz.values = Object.assign({}, r.values); wiz.secrets = r.secrets;
            });
            host.call(["options", provider.name], r => { if (r.ok) wiz.options = r.options; else wiz.error = r.error; });
            return;
        }
        nameField.text = (guide.title || provider.title).replace(/[:\/\\,]/g, " ").replace(/\s+/g, " ").trim();
        nameField.input.forceActiveFocus();
        nameField.input.selectAll();
        host.call(["options", provider.name], r => { if (r.ok) wiz.options = r.options; else wiz.error = r.error; });
    }

    // The page for a guide step opens once, as the step is first shown.
    function showStep(i) {
        page = "step"; stepIndex = i; error = "";
        const s = steps[i];
        if (s && s.url && !opened[i]) { const o = Object.assign({}, opened); o[i] = true; opened = o; host.openUrl(s.url); }
    }
    function next() {
        error = "";
        if (page === "name") {
            const n = nameField.text.trim();
            if (!n || /[:\/\\]/.test(n) || n.startsWith("-")) { error = "Give the drive a name without “:”, “/” or “\\”."; return; }
            if (host.drives.some(d => d.name === n)) { error = "There's already a drive called “" + n + "”."; return; }
            if (steps.length) showStep(0); else page = "form";
        } else if (page === "step") {
            if (stepIndex + 1 < steps.length) showStep(stepIndex + 1); else page = "form";
        } else if (page === "form") {
            connect();
        } else if (page === "ask") {
            send(answer);
        }
    }
    function back() {
        error = "";
        if (page === "step") { if (stepIndex > 0) showStep(stepIndex - 1); else page = "name"; }
        else if (page === "form") { if (steps.length) showStep(steps.length - 1); else page = "name"; }
    }

    // ---- talking to rclone
    Timer { id: longWait; interval: 1500; onTriggered: wiz.waitingLong = true }
    function run(req) {
        busy = true; waitingLong = false; error = ""; longWait.restart();
        host.call(["step"], r => {
            wiz.busy = false; wiz.waitingLong = false; longWait.stop();
            if (!r.ok) { wiz.error = r.error; return; }
            wiz.created = true;
            if (r.done) { wiz.page = "done"; wiz.error = r.error || ""; wiz.test(); return; }
            // A desktop has a browser: sign in there without asking.
            if (r.option && r.option.Name === "config_is_local") { wiz.step = r; wiz.send("true"); return; }
            wiz.step = r;
            wiz.error = r.error || "";
            wiz.answer = r.option ? (r.option.IsPassword ? "" : (r.option.ValueStr || r.option.DefaultStr || "")) : "";
            wiz.page = "ask";
        }, JSON.stringify(req));
    }
    function connect() {
        if (editName !== "") {
            const changed = {}, pw = [];
            for (const o of options) {
                const v = values[o.Name];
                if (v === undefined || v === (original[o.Name] !== undefined ? original[o.Name] : "")) continue;
                if (o.IsPassword && v === "") continue;      // empty: keep the old one
                if (v === o.DefaultStr && original[o.Name] === undefined) continue;
                changed[o.Name] = v;
                if (o.IsPassword) pw.push(o.Name);
            }
            created = true;
            run({ name: editName, type: provider.name, update: true, params: changed, passwords: pw });
            return;
        }
        if (missing.length) { error = "Fill in: " + missing.map(o => o.Name).join(", ") + "."; return; }
        const params = Object.assign({}, provider.preset || {}), pw = [];
        for (const o of options) {
            const v = values[o.Name];
            if (v === undefined || v === "" || (v === o.DefaultStr && !o.IsPassword)) continue;
            if (!matches(o.Provider)) continue;
            params[o.Name] = v;
            if (o.IsPassword) pw.push(o.Name);
        }
        run({ name: nameField.text.trim(), type: provider.name, params: params, passwords: pw });
    }
    function send(result) {
        const o = step.option || {};
        lastAsked = o.Name || "";
        run({ name: nameField.text.trim(), type: provider.name, state: step.state || "", result: String(result), password: !!o.IsPassword, started: true });
    }
    function test() {
        testResult = "Checking that it answers…"; testOk = false;
        host.call(["test", nameField.text.trim()], r => { wiz.testOk = !!r.ok; wiz.testResult = r.ok ? r.summary : r.error; });
    }
    function cancel() {
        if (busy) host.call(["cancel"], () => {});
        if (created && page !== "done" && editName === "") host.call(["delete", nameField.text.trim()], () => host.refresh());
        finished("");
    }

    readonly property bool signingIn: busy && waitingLong && (lastAsked === "config_is_local" || !!guide.signin)
    readonly property var signin: guide.signin || { address: "the sign-in page", heading: "Allow rclone to access your account", allow: "Allow" }

    // ---------------------------------------------------------------- header
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Icon { implicitSize: 32; name: wiz.host.iconFor(wiz.provider.name); fallback: "folder-cloud" }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { text: wiz.editName !== "" ? "“" + wiz.editName + "”: " + (wiz.guide.title || wiz.provider.title) : "Add " + (wiz.guide.title || wiz.provider.title); font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold }
            Label {
                Layout.fillWidth: true
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
                text: wiz.page === "name" ? "Name the drive"
                    : wiz.page === "step" ? "Step " + (wiz.stepIndex + 1) + " of " + wiz.steps.length + ": " + (wiz.steps[wiz.stepIndex].title || "")
                    : wiz.page === "form" ? (wiz.editName !== "" ? "All of its settings" : "Details for rclone")
                    : wiz.signingIn ? "Signing in"
                    : wiz.page === "ask" ? "One more question"
                    : "Ready"
            }
        }
    }

    // ---------------------------------------------------------------- name
    ColumnLayout {
        visible: wiz.page === "name"
        Layout.fillWidth: true
        spacing: 8
        Label {
            Layout.fillWidth: true
            visible: !!wiz.guide.need
            text: wiz.guide.need || ""
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        Label {
            Layout.fillWidth: true
            text: wiz.steps.length
                ? "First " + (wiz.steps.length === 1 ? "one step" : wiz.steps.length + " steps") + " on the website (each opens the page for you), then a few questions."
                : "Next, a few questions rclone needs answered. Most can stay as they are."
            color: Theme.fgDim
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        RowLayout {
            spacing: 8
            Label { text: "Name:" }
            TextBox {
                id: nameField
                implicitWidth: 280
                placeholder: "e.g. My Google Drive"
                onAccepted: wiz.next()
                HoverHandler { id: nHov }
                Tooltip { anchorItem: nameField; hovered: nHov.hovered; text: "How apps show this drive. Letters, numbers, spaces, - _ . (no “:” or “/”)." }
            }
        }
    }

    // ---------------------------------------------------------------- website step
    ColumnLayout {
        visible: wiz.page === "step"
        Layout.fillWidth: true
        spacing: 10
        readonly property var s: wiz.steps[wiz.stepIndex] || ({})
        Label {
            Layout.fillWidth: true
            text: parent.s.say || ""
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        Picture {
            visible: !!(parent.s.rows && parent.s.rows.length)
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            address: parent.s.address || ""
            heading: parent.s.heading || ""
            rows: parent.s.rows || []
        }
        PushButton {
            visible: !!parent.s.url
            text: "Open This Page Again"
            tooltip: parent.s.url || ""
            onClicked: wiz.host.openUrl(parent.s.url)
        }
    }

    // ---------------------------------------------------------------- form
    ColumnLayout {
        visible: wiz.page === "form"
        Layout.fillWidth: true
        spacing: 10
        Label {
            Layout.fillWidth: true
            visible: wiz.options.length === 0 && wiz.error === ""
            text: "Asking rclone what it needs…"
            color: Theme.fgDim
        }
        Label {
            Layout.fillWidth: true
            visible: wiz.options.length > 0 && wiz.basicOptions.length === 0
            text: "Nothing to fill in here. Press Connect."
            color: Theme.fgDim
        }
        SettingsGroup {
            visible: wiz.basicOptions.length > 0
            Repeater {
                model: wiz.page === "form" ? wiz.basicOptions : []
                Item {
                    id: fr
                    required property var modelData
                    required property int index
                    width: parent.width
                    implicitHeight: orow.implicitHeight + 20
                    height: implicitHeight
                    SettingsDivider { visible: fr.index > 0 }
                    OptionRow {
                        id: orow
                        y: 10
                        width: parent.width
                        opt: fr.modelData
                        hint: wiz.hintFor2(fr.modelData)
                        providerValue: wiz.providerValue
                        value: wiz.valueOf(fr.modelData)
                        onEdited: v => wiz.setValue(fr.modelData.Name, v)
                        onSubmitted: wiz.next()
                    }
                }
            }
        }
        MouseArea {
            visible: wiz.advancedOptions.length > 0
            Layout.fillWidth: true
            implicitHeight: 26
            cursorShape: Qt.PointingHandCursor
            onClicked: wiz.showAdvanced = !wiz.showAdvanced
            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                Icon { implicitSize: 12; name: wiz.showAdvanced ? "arrow-down" : "arrow-right"; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Advanced settings (" + wiz.advancedOptions.length + "): leave them as they are unless you know you need one"; color: Theme.fgDim }
            }
        }
        SettingsGroup {
            visible: wiz.showAdvanced && wiz.advancedOptions.length > 0
            Repeater {
                model: wiz.showAdvanced && wiz.page === "form" ? wiz.advancedOptions : []
                Item {
                    id: ar
                    required property var modelData
                    required property int index
                    width: parent.width
                    implicitHeight: arow.implicitHeight + 20
                    height: implicitHeight
                    SettingsDivider { visible: ar.index > 0 }
                    OptionRow {
                        id: arow
                        y: 10
                        width: parent.width
                        opt: ar.modelData
                        hint: wiz.hintFor2(ar.modelData)
                        providerValue: wiz.providerValue
                        value: wiz.valueOf(ar.modelData)
                        onEdited: v => wiz.setValue(ar.modelData.Name, v)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- follow-up questions
    SettingsGroup {
        visible: wiz.page === "ask" && !wiz.signingIn
        Repeater {
            model: wiz.page === "ask" && wiz.step.option ? [wiz.step] : []
            Item {
                id: qr
                required property var modelData
                width: parent.width
                implicitHeight: qrow.implicitHeight + 20
                height: implicitHeight
                OptionRow {
                    id: qrow
                    y: 10
                    width: parent.width
                    opt: qr.modelData.option
                    hint: wiz.hintFor(qr.modelData.option.Name)
                    providerValue: wiz.providerValue
                    value: wiz.answer
                    onEdited: v => wiz.answer = v
                    onSubmitted: wiz.next()
                    onLoaded: focusField()
                }
            }
        }
    }

    // ---------------------------------------------------------------- waiting / signing in
    ColumnLayout {
        visible: wiz.busy && wiz.waitingLong
        Layout.fillWidth: true
        spacing: 10
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: wiz.signingIn
                ? "Your browser opened " + wiz.signin.address + ". Sign in there and click " + wiz.signin.allow
                  + ". (The page names rclone: that's the tool hearth uses for cloud drives.) When it says Success, come back here."
                : "Waiting for rclone…"
        }
        Picture {
            visible: wiz.signingIn
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            address: wiz.signin.address
            heading: wiz.signin.heading
            rows: [{ kind: "text", label: "Signed in as you@example.com" },
                   { kind: "text", label: "rclone wants to see, edit, create and delete your files." },
                   { kind: "button", label: wiz.signin.allow, hot: true }]
        }
    }

    // ---------------------------------------------------------------- done
    ColumnLayout {
        visible: wiz.page === "done"
        Layout.fillWidth: true
        spacing: 6
        Label { text: "“" + nameField.text.trim() + "” is saved."; font.weight: Font.DemiBold }
        Label {
            Layout.fillWidth: true
            text: wiz.testResult
            color: wiz.testResult.startsWith("Checking") ? Theme.fgDim : wiz.testOk ? Theme.good : Theme.bad
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        Label {
            Layout.fillWidth: true
            text: wiz.testOk || wiz.testResult.startsWith("Checking") ? "Apps that use rclone (Files, backups) can open it now."
                : "If a detail was wrong, remove the drive in the list and add it again; if the server is just off, it works once it's back."
            color: Theme.fgDim
            wrapMode: Text.Wrap
        }
    }

    Label {
        Layout.fillWidth: true
        visible: wiz.error !== ""
        text: wiz.error
        color: Theme.bad
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // ---------------------------------------------------------------- buttons
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        PushButton {
            visible: wiz.page !== "done"
            text: "Cancel"
            tooltip: wiz.editName !== "" ? "Close without changing anything" : wiz.created ? "Stop; the half-made drive is removed" : "Stop without adding a drive"
            onClicked: wiz.cancel()
        }
        Item { Layout.fillWidth: true }
        PushButton {
            visible: wiz.page === "step" || (wiz.page === "form" && wiz.editName === "")
            enabled: !wiz.busy
            text: "Back"
            onClicked: wiz.back()
        }
        PushButton {
            visible: wiz.page !== "done" && !wiz.signingIn
            enabled: !wiz.busy && !(wiz.page === "form" && wiz.options.length === 0)
            primary: true
            text: wiz.page === "form" ? (wiz.editName !== "" ? "Save" : "Connect") : "Next"
            tooltip: wiz.page === "form" ? "Save the drive in rclone's settings (signing in opens your browser when needed)" : ""
            onClicked: wiz.next()
        }
        PushButton {
            visible: wiz.page === "done"
            text: "Check Again"
            onClicked: wiz.test()
        }
        PushButton {
            visible: wiz.page === "done"
            primary: true
            text: "Done"
            onClicked: wiz.finished(nameField.text.trim())
        }
    }

    // Sibling files aren't types in Quickshell: load them by file.
    component Picture: Loader {
        id: pic
        property string address
        property string heading
        property var rows: []
        Layout.preferredHeight: item ? item.implicitHeight : 0
        source: "StepPicture.qml"
        Binding { target: pic.item; property: "address"; value: pic.address; when: !!pic.item }
        Binding { target: pic.item; property: "heading"; value: pic.heading; when: !!pic.item }
        Binding { target: pic.item; property: "rows"; value: pic.rows; when: !!pic.item }
    }
    component OptionRow: Loader {
        id: ol
        property var opt: ({})
        property string hint
        property string value
        property string providerValue
        signal edited(string v)
        signal submitted()
        function focusField() { if (item) item.focusField(); }
        height: item ? item.implicitHeight : 0
        source: "CloudDriveOption.qml"
        Binding { target: ol.item; property: "width"; value: ol.width; when: !!ol.item }
        Binding { target: ol.item; property: "opt"; value: ol.opt; when: !!ol.item }
        Binding { target: ol.item; property: "hint"; value: ol.hint; when: !!ol.item }
        Binding { target: ol.item; property: "value"; value: ol.value; when: !!ol.item }
        Binding { target: ol.item; property: "providerValue"; value: ol.providerValue; when: !!ol.item }
        Connections {
            target: ol.item
            function onEdited(v) { ol.edited(v); }
            function onSubmitted() { ol.submitted(); }
        }
    }
}
