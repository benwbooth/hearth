import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../widgets"
import "../../services"
import "../.."

// Settings > Users & Accounts, like macOS's: your picture and name on top,
// then a grid of built-in pictures by category (avatars/, see its
// CREDITS.md), monograms of your initials, your own photo (round crop and
// zoom) or one from the webcam. Saved through AccountsService
// (helpers/hearth-user: the login and lock screens read it) and ~/.face.
ColumnLayout {
    id: pane
    spacing: 14

    // ---------------------------------------------------------------- state

    // Built-in pictures: the package installs them next to the shell
    // ($out/share/hearth/avatars); a checkout has them at the repo root.
    readonly property string avatarDir: Quickshell.env("HEARTH_AVATAR_DIR")
        || String(Quickshell.shellDir).replace(/\/shell\/?$/, "") + "/avatars"
    property var pictures: []           // index.json entries
    readonly property var categories: {
        const seen = [];
        for (const p of pictures) if (seen.indexOf(p.category) < 0) seen.push(p.category);
        return seen;
    }

    property string user: Quickshell.env("USER") || ""
    property string realName: ""
    property string icon: ""
    property int iconRev: 0             // bumps after a save so Images reload
    property bool mock: false
    property bool busy: false
    property string status: ""
    property bool statusBad: false
    property string chosen: ""          // id of the picture picked in this session

    // "" (grid) | "crop" | "camera"
    property string mode: ""
    property string cropSource: ""

    readonly property string displayName: realName || user
    readonly property string initials: {
        const parts = displayName.split(/\s+/).filter(p => p);
        return parts.length > 1 ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
                                : (parts[0] || "?").slice(0, 2).toUpperCase();
    }
    // Monogram backgrounds: macOS's grey first, then colours.
    readonly property var monograms: [
        { id: "mono-grey", top: "#a8aeb8", bottom: "#6f7682" },
        { id: "mono-blue", top: "#6cb6ff", bottom: "#2f6fd6" },
        { id: "mono-purple", top: "#c49bff", bottom: "#7a4bd6" },
        { id: "mono-pink", top: "#ff9cc2", bottom: "#e0507f" },
        { id: "mono-orange", top: "#ffc27a", bottom: "#f07a2e" },
        { id: "mono-green", top: "#8fe0a0", bottom: "#2fa65a" },
        { id: "mono-teal", top: "#7fe3e0", bottom: "#1f9aa6" },
        { id: "mono-graphite", top: "#5a606b", bottom: "#24272d" }
    ]

    function fileUrl(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""; }
    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")); }
    function say(msg, bad) { status = msg; statusBad = !!bad; }

    // ---------------------------------------------------------------- helper

    Process {
        id: infoProc
        running: true
        command: ["hearth-user", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.ok) {
                        pane.user = r.user; pane.realName = r.realName; pane.icon = r.icon;
                        pane.mock = !!r.mock; nameField.text = r.realName; pane.iconRev++;
                    }
                } catch (e) {
                    pane.say("Couldn't read your account (hearth-user didn't answer).", true);
                }
            }
        }
    }

    Process {
        id: setProc
        property string what: ""
        property string chosenId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                pane.busy = false;
                let r = null;
                try { r = JSON.parse(text.trim().split("\n").pop()); } catch (e) {}
                if (!r) { pane.say("Something went wrong saving that; nothing was changed.", true); return; }
                if (!r.ok) { pane.say(r.error, true); infoProc.running = true; return; }
                if (setProc.what === "icon") {
                    pane.icon = r.icon; pane.iconRev++; pane.chosen = setProc.chosenId;
                    pane.say(r.warning ? "Picture changed, but " + r.warning + "." : "Picture changed. The login and lock screens use it from now on.", !!r.warning);
                } else {
                    pane.realName = r.realName;
                    pane.say("Name changed.", false);
                }
            }
        }
    }

    function setIcon(path, id) {
        if (busy) return;
        busy = true;
        say("Saving…", false);
        setProc.what = "icon";
        setProc.chosenId = id || "";
        setProc.command = ["hearth-user", "set-icon", path];
        setProc.running = true;
    }
    function setName(name) {
        name = name.trim();
        if (busy || name === realName) return;
        if (name === "") { say("The name can't be empty.", true); nameField.text = realName; return; }
        busy = true;
        setProc.what = "name";
        setProc.command = ["hearth-user", "set-name", name];
        setProc.running = true;
    }

    // Rendered pictures (crops, monograms) go to the cache before saving.
    Process { running: true; command: ["mkdir", "-p", Quickshell.cachePath("avatars")] }
    function newCachePath() { return Quickshell.cachePath("avatars/avatar-" + Date.now() + ".png"); }
    function saveRendered(item, id, done) {
        // grabToImage multiplies the size by the screen's scale itself.
        const w = item.QsWindow.window;
        const n = Math.round(512 / ((w && w.devicePixelRatio) || 1));
        item.grabToImage(res => {
            const f = pane.newCachePath();
            if (done) done();   // after the grab: the item must stay visible until then
            if (res.saveToFile(f)) pane.setIcon(f, id);
            else pane.say("Couldn't write the picture to " + f + ".", true);
        }, Qt.size(n, n));
    }

    FileView {
        path: pane.avatarDir + "/index.json"
        onLoaded: { try { pane.pictures = JSON.parse(text()); } catch (e) { pane.pictures = []; } }
        onLoadFailed: pane.pictures = []
    }

    // ---------------------------------------------------------------- header

    SettingsGroup {
        Item {
            width: parent.width
            height: 112
            RowLayout {
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 18

                Avatar {
                    id: bigAvatar
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    source: pane.icon
                    rev: pane.iconRev
                    fallbackText: pane.initials
                    HoverHandler { id: bigHov }
                    Tooltip { anchorItem: bigAvatar; hovered: bigHov.hovered; text: "Your picture on the login and lock screens. Pick a new one below." }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        spacing: 8
                        TextBox {
                            id: nameField
                            implicitWidth: 260
                            placeholder: "Your full name"
                            enabled: !pane.busy
                            onAccepted: pane.setName(text)
                            input.onActiveFocusChanged: if (!input.activeFocus && text.trim() !== pane.realName && text.trim() !== "") pane.setName(text)
                            HoverHandler { id: nameHov }
                            Tooltip { anchorItem: nameField; hovered: nameHov.hovered; text: "The name shown on the login and lock screens. Press Return to save it. Your login name stays " + pane.user + "." }
                        }
                        PushButton {
                            visible: nameField.text.trim() !== pane.realName
                            text: "Save Name"
                            primary: true
                            onClicked: pane.setName(nameField.text)
                        }
                    }
                    Label {
                        text: "Login name: " + pane.user + (pane.mock ? "   (test mode: nothing is saved to the system)" : "")
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                    RowLayout {
                        spacing: 8
                        PushButton {
                            text: "Choose a Photo…"
                            tooltip: "Use a picture of your own; you can move and zoom it to fit the circle."
                            enabled: !pane.busy
                            onClicked: photoDialog.open()
                        }
                        PushButton {
                            text: "Take a Photo…"
                            tooltip: "Take a picture with your webcam."
                            enabled: !pane.busy
                            onClicked: pane.mode = "camera"
                        }
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: pane.status !== ""
        text: pane.status
        color: pane.statusBad ? Theme.bad : Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // ---------------------------------------------------------------- crop editor

    SettingsGroup {
        visible: pane.mode === "crop"
        Item {
            width: parent.width
            height: cropCol.implicitHeight + 28
            ColumnLayout {
                id: cropCol
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                spacing: 12
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Drag to move the picture, scroll or use the slider to zoom."
                    color: Theme.fgDim
                }
                AvatarCrop {
                    id: cropper
                    Layout.alignment: Qt.AlignHCenter
                    source: pane.mode === "crop" ? pane.cropSource : ""
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    Icon { implicitSize: 16; name: "zoom-out" }
                    ValueSlider {
                        implicitWidth: 220
                        from: 1; to: 4; step: 0.01; decimals: 1; suffix: "×"
                        value: cropper.zoom
                        onMoved: v => cropper.setZoom(v)
                    }
                    Icon { implicitSize: 16; name: "zoom-in" }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    PushButton { text: "Cancel"; onClicked: pane.mode = "" }
                    PushButton {
                        text: "Save"
                        primary: true
                        enabled: cropper.ready && !pane.busy
                        tooltip: "Use this as your picture."
                        onClicked: { pane.saveRendered(cropper.renderItem, "", () => pane.mode = ""); }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- camera

    SettingsGroup {
        visible: pane.mode === "camera"
        Item {
            width: parent.width
            height: camLoader.implicitHeight + 28
            Loader {
                id: camLoader
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                active: pane.mode === "camera"
                source: "AvatarCamera.qml"
                onStatusChanged: if (status === Loader.Error) { pane.mode = ""; pane.say("The camera can't be used here (Qt Multimedia didn't load).", true); }
            }
            Connections {
                target: camLoader.item
                ignoreUnknownSignals: true
                function onCaptured(path) { pane.cropSource = path; pane.mode = "crop"; }
                function onCancelled() { pane.mode = ""; }
            }
        }
    }

    // ---------------------------------------------------------------- built-in pictures

    Label {
        Layout.fillWidth: true
        visible: pane.mode === "" && pane.pictures.length === 0
        text: "The built-in pictures weren't found in " + pane.avatarDir + "."
        color: Theme.fgDim
        wrapMode: Text.Wrap
    }

    Repeater {
        model: pane.mode === "" ? pane.categories : []
        ColumnLayout {
            id: catCol
            required property string modelData
            Layout.fillWidth: true
            spacing: 8
            Label { text: catCol.modelData; font.weight: Font.DemiBold }
            Flow {
                Layout.fillWidth: true
                spacing: 12
                Repeater {
                    model: pane.pictures.filter(p => p.category === catCol.modelData)
                    Tile {
                        required property var modelData
                        source: pane.avatarDir + "/" + modelData.file
                        selected: pane.chosen === modelData.id
                        tip: modelData.title + "  ·  " + modelData.author + ", " + modelData.licence
                        onPicked: pane.setIcon(pane.avatarDir + "/" + modelData.file, modelData.id)
                    }
                }
            }
        }
    }

    ColumnLayout {
        visible: pane.mode === ""
        Layout.fillWidth: true
        spacing: 8
        Label { text: "Monograms"; font.weight: Font.DemiBold }
        Flow {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: pane.monograms
                Tile {
                    id: monoTile
                    required property var modelData
                    selected: pane.chosen === modelData.id
                    tip: "Your initials (" + pane.initials + ")"
                    Monogram {
                        parent: monoTile.face
                        anchors.fill: parent
                        topColor: monoTile.modelData.top
                        bottomColor: monoTile.modelData.bottom
                        text: pane.initials
                    }
                    onPicked: {
                        monoRender.topColor = modelData.top;
                        monoRender.bottomColor = modelData.bottom;
                        pane.saveRendered(monoRender, modelData.id);
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: pane.mode === ""
        text: "Pictures are Fluent Emoji (Microsoft, MIT), public-domain NASA images and CC0 photos from Wikimedia Commons; "
              + "credits are in " + pane.avatarDir + "/CREDITS.md."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // A full-size monogram for saving: off to the side, rendered only by grabToImage.
    Item {
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0
        Monogram {
            id: monoRender
            x: -4000
            width: 512
            height: 512
            text: pane.initials
        }
    }

    // Test hooks (only with HEARTH_USER_MOCK_DIR, which also keeps
    // hearth-user off the system bus): stand-ins for clicks.
    IpcHandler {
        target: "users-test"
        enabled: pane.mock || Quickshell.env("HEARTH_USER_MOCK_DIR") !== ""
        function pick(id: string): void {
            const p = pane.pictures.find(x => x.id === id);
            if (p) pane.setIcon(pane.avatarDir + "/" + p.file, p.id);
        }
        function monogram(i: int): void {
            const m = pane.monograms[i];
            monoRender.topColor = m.top; monoRender.bottomColor = m.bottom;
            pane.saveRendered(monoRender, m.id);
        }
        function crop(path: string): void { pane.cropSource = path; pane.mode = "crop"; }
        function zoom(z: real): void { cropper.setZoom(z); }
        function pan(x: real, y: real): void { cropper.cx = x; cropper.cy = y; cropper.clamp(); }
        function saveCrop(): void { pane.saveRendered(cropper.renderItem, "", () => pane.mode = ""); }
        function camera(): void { pane.mode = "camera"; }
        function grid(): void { pane.mode = ""; }
        function setName(n: string): void { nameField.text = n; pane.setName(n); }
        function status(): string { return pane.status; }
    }

    FileDialog {
        id: photoDialog
        title: "Choose a photo"
        currentFolder: "file://" + (Quickshell.env("HOME") || "") + "/Pictures"
        nameFilters: ["Pictures (*.jpg *.jpeg *.png *.webp *.avif *.heic *.jxl *.bmp)", "All files (*)"]
        onAccepted: { pane.cropSource = pane.localPath(selectedFile); pane.mode = "crop"; }
    }

    // ---------------------------------------------------------------- pieces

    // A round picture with an initials fallback.
    component Avatar: ClippingRectangle {
        id: av
        property string source
        property int rev
        property string fallbackText
        radius: width / 2
        color: Theme.dark ? "#4a4f57" : "#c5cad2"
        Image {
            id: avImg
            anchors.fill: parent
            source: av.source ? pane.fileUrl(av.source) + "?r=" + av.rev : ""
            cache: false
            sourceSize: Qt.size(av.width * 2, av.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
        }
        Label {
            anchors.centerIn: parent
            visible: avImg.status !== Image.Ready
            text: av.fallbackText
            color: "white"
            font.family: Theme.displayFontFamily
            font.pointSize: Math.max(6, 0.75 * av.width * 0.36)
            font.weight: Font.Medium
        }
    }

    // Initials on a gradient, like macOS's monogram pictures.
    component Monogram: Rectangle {
        id: mono
        property color topColor: "#a8aeb8"
        property color bottomColor: "#6f7682"
        property string text
        gradient: Gradient {
            GradientStop { position: 0; color: mono.topColor }
            GradientStop { position: 1; color: mono.bottomColor }
        }
        Label {
            anchors.centerIn: parent
            text: mono.text
            color: "white"
            font.family: Theme.displayFontFamily
            font.pointSize: Math.max(6, 0.75 * mono.height * 0.4)
            font.weight: Font.Medium
            font.letterSpacing: mono.height * 0.01
        }
    }

    // A pickable round picture in the grid.
    component Tile: MouseArea {
        id: tile
        property string source
        property bool selected: false
        property string tip
        property alias face: faceBox
        signal picked()
        width: 64
        height: 64
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !pane.busy
        onClicked: picked()
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 6
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: tile.selected ? Theme.accent : tile.containsMouse ? Theme.border : "transparent"
        }
        ClippingRectangle {
            id: faceBox
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            color: Theme.bgRaised
            scale: tile.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Image {
                anchors.fill: parent
                visible: tile.source !== ""
                source: tile.source ? pane.fileUrl(tile.source) : ""
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
        Tooltip { anchorItem: tile; hovered: tile.containsMouse; text: tile.tip }
    }
}
