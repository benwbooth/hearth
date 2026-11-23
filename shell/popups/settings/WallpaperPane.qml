import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// Settings > Wallpaper, laid out like macOS System Settings: the current
// wallpaper on top (with its credit, next/previous and history), then a
// grid of everything you can pick, grouped by kind, then options.
// Everything here goes through services/Wallpaper.qml.
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var cfg: Wallpaper.cfg
    readonly property var screens: Quickshell.screens
    // "*" (all displays) or an output name.
    property string display: "*"
    readonly property string viewOutput: display === "*" ? (screens.length ? screens[0].name : "") : display
    readonly property var view: Wallpaper.views[viewOutput] || null
    readonly property var spec: Wallpaper.specFor(viewOutput)
    readonly property var srcInfo: spec.type === "potd" ? Wallpaper.sourceInfo(spec.source) : null
    readonly property var srcOpts: { void pane.cfg; return spec.type === "potd" ? Wallpaper.srcOpts(spec.source) : {}; }

    function choose(s) { Wallpaper.setSpec(s, pane.display); }
    function setSrcOpt(k, v) {
        const all = JSON.parse(JSON.stringify(pane.cfg.sources || {}));
        all[spec.source] = Object.assign({}, all[spec.source] || {}, { [k]: v });
        Settings.set("wallpaper.sources", all);
    }
    function isCurrent(s) { return Wallpaper.sameSpec(s, pane.spec); }
    function baseName(p) { return (p || "").split("/").pop().replace(/\.[^.]+$/, ""); }

    Component.onCompleted: Wallpaper.scanCatalog()

    // ---------------------------------------------------------------- current wallpaper

    RowLayout {
        Layout.fillWidth: true
        spacing: 18
        Rectangle {
            id: previewBox
            Layout.preferredWidth: 360
            Layout.preferredHeight: Math.round(360 * (pane.screens.length ? pane.screens[0].height / pane.screens[0].width : 0.5625))
            radius: Theme.popupRadius
            color: Theme.bgAlt
            border.color: Theme.border
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: pane.view && pane.view.file ? "file://" + pane.view.file : ""
                fillMode: pane.view && pane.view.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 720
            }
            Label {
                anchors.centerIn: parent
                visible: !pane.view || !pane.view.file
                text: Wallpaper.loading ? "Downloading…" : "No picture yet"
                color: Theme.fgDim
            }
            // The kind badge (video, shader...).
            Rectangle {
                visible: pane.view && pane.view.kind !== "still"
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                radius: height / 2
                height: 22
                width: badge.implicitWidth + 16
                color: Qt.rgba(0, 0, 0, 0.55)
                Label {
                    id: badge
                    anchors.centerIn: parent
                    color: "white"
                    font.pointSize: Theme.smallFontSize
                    text: !pane.view ? "" : pane.view.kind === "video" ? "Video"
                        : pane.view.kind === "shader" ? "Shader" : pane.view.kind === "we" ? "Wallpaper Engine" : ""
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 6
            Label {
                Layout.fillWidth: true
                text: pane.view && pane.view.meta ? pane.view.meta.source : ""
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
            }
            Label {
                Layout.fillWidth: true
                text: pane.view && pane.view.meta ? pane.view.meta.title || "" : ""
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 3
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: pane.view && pane.view.meta ? pane.view.meta.copyright || "" : ""
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 3
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: pane.view && pane.view.error ? pane.view.error : ""
                color: Theme.bad
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: {
                    if (!pane.view || pane.view.kind === "still") return "";
                    const r = Wallpaper.pauseReason || (Wallpaper.paused(pane.viewOutput) ? "windows cover the screen" : "");
                    return r ? "Paused: " + r + "." : "Playing.";
                }
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                PushButton {
                    visible: pane.spec.type === "potd" || pane.spec.type === "folder"
                    text: "‹ Previous"
                    tooltip: "The picture before this one"
                    enabled: pane.spec.type === "folder" || Wallpaper.canStepOlder(pane.spec.source)
                    onClicked: Wallpaper.previous(pane.viewOutput)
                }
                PushButton {
                    visible: pane.spec.type === "potd" || pane.spec.type === "folder"
                    text: pane.srcInfo && pane.srcInfo.kind === "daily" && Wallpaper.historyIndex(pane.spec.source) <= 0
                          ? "Check for new" : "Next ›"
                    tooltip: pane.srcInfo && pane.srcInfo.kind !== "daily" ? "Get another picture now" : "The next picture"
                    enabled: !(pane.spec.type === "potd" && Wallpaper.busy[pane.spec.source])
                    onClicked: Wallpaper.next(pane.viewOutput)
                }
                PushButton {
                    visible: !!(pane.view && pane.view.meta && pane.view.meta.link)
                    text: "About this picture"
                    tooltip: "Open the picture's page in the browser"
                    onClicked: Qt.openUrlExternally(pane.view.meta.link)
                }
                PushButton {
                    visible: pane.spec.type === "potd"
                    text: "Save a copy"
                    tooltip: "Copy the picture into your Pictures folder"
                    onClicked: Wallpaper.saveCopy()
                }
            }
        }
    }

    // History strip for picture sources.
    ListView {
        id: hist
        Layout.fillWidth: true
        Layout.preferredHeight: 62
        visible: pane.spec.type === "potd" && count > 1
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: pane.spec.type === "potd" ? (Wallpaper.histories[pane.spec.source] || []) : []
        delegate: MouseArea {
            id: hd
            required property var modelData
            width: 96
            height: 58
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Wallpaper.selectItem(pane.spec.source, modelData.id)
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Theme.bgAlt
                border.width: pane.view && pane.view.meta && pane.view.meta.item && pane.view.meta.item.id === hd.modelData.id ? 2 : 0
                border.color: Theme.accent
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                    source: "file://" + hd.modelData.file
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 192
                }
            }
            Tooltip {
                anchorItem: hd
                text: hd.modelData.title || ""
                subtext: hd.modelData.date ? hd.modelData.date.replace(/(\d{4})(\d\d)(\d\d)/, "$1-$2-$3") : ""
                hovered: hd.containsMouse
            }
        }
    }

    SettingsGroup {
        SettingsRow {
            visible: pane.screens.length > 1
            label: "Show on"
            note: "Pick a wallpaper for every display, or one display at a time."
            Segmented {
                options: [{ value: "*", label: "All displays" }].concat(pane.screens.map(s => ({ value: s.name, label: s.name })))
                value: pane.display
                onPicked: v => pane.display = v
            }
        }
        SettingsDivider { visible: pane.screens.length > 1 }
        SettingsRow {
            label: "Fit to screen"
            note: "Fill crops the picture to cover the screen, Fit shows all of it, Centre keeps its size, Tile repeats it."
            Segmented {
                options: [{ value: "fill", label: "Fill" }, { value: "fit", label: "Fit" },
                          { value: "center", label: "Centre" }, { value: "tile", label: "Tile" }]
                value: pane.cfg.fit
                onPicked: v => Settings.set("wallpaper.fit", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Smart crop"
            note: "With Fill, crop around the interesting part of the picture rather than its middle (helps on ultrawide screens)."
            enabled: pane.cfg.fit === "fill"
            Toggle { checked: !!pane.cfg.smartCrop; onToggled: c => Settings.set("wallpaper.smartCrop", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Show on the lock screen and login screen"
            note: Wallpaper.exportStatus === "missing" ? "Saved for the lock screen; the login screen needs /var/lib/hearth/wallpaper (see README)."
                : Wallpaper.exportStatus === "not-writable" ? "Saved for the lock screen; /var/lib/hearth/wallpaper isn't writable for you (see README)."
                : "Use this wallpaper behind the lock screen and the login screen too."
            tip: "hearth keeps ~/.cache/hearth/wallpaper.json up to date and copies the picture (and a video) to /var/lib/hearth/wallpaper for the login screen."
            Toggle { checked: pane.cfg.lockScreen !== false; onToggled: c => Settings.set("wallpaper.lockScreen", c) }
        }
    }

    // Options of the picture source in use.
    SettingsGroup {
        visible: pane.spec.type === "potd"
        SettingsRow {
            label: "Get a new picture"
            note: pane.srcInfo ? pane.srcInfo.note : ""
            Dropdown {
                implicitWidth: 200
                options: (pane.srcInfo && pane.srcInfo.kind === "live"
                          ? [10, 30, 60, 180] : pane.srcInfo && pane.srcInfo.kind === "daily" ? [60, 180, 720, 1440]
                          : [15, 60, 180, 720, 1440, 10080]).map(m => ({
                    value: m,
                    label: pane.srcInfo && pane.srcInfo.kind === "daily" && m < 1440 ? "Check every " + (m < 60 ? m + " minutes" : (m / 60) + (m === 60 ? " hour" : " hours"))
                         : m === 10080 ? "Every week" : m === 1440 ? "Every day"
                         : m < 60 ? "Every " + m + " minutes" : "Every " + (m / 60) + (m === 60 ? " hour" : " hours")
                }))
                value: pane.spec.type === "potd" ? Wallpaper.intervalMin(pane.spec.source) : 0
                onPicked: v => pane.setSrcOpt("interval", v)
            }
        }
        // Wallhaven
        SettingsDivider { visible: pane.spec.source === "wallhaven" }
        SettingsRow {
            visible: pane.spec.source === "wallhaven"
            label: "Search for"
            note: "Words or tags, e.g. mountains, +nature -people. Empty: anything."
            TextBox { implicitWidth: 240; placeholder: "Anything"; text: pane.srcOpts.query || ""; onAccepted: pane.setSrcOpt("query", text.trim()) }
        }
        SettingsRow {
            visible: pane.spec.source === "wallhaven"
            label: "Kinds"
            note: "General wallpapers, anime, or people."
            Segmented {
                options: [{ value: "100", label: "General" }, { value: "110", label: "+ Anime" }, { value: "111", label: "All" }]
                value: pane.srcOpts.categories || "100"
                onPicked: v => pane.setSrcOpt("categories", v)
            }
        }
        SettingsRow {
            visible: pane.spec.source === "wallhaven"
            label: "Order"
            note: "Most liked of the day, week or month, or a random pick."
            Dropdown {
                implicitWidth: 200
                options: [{ value: "toplist:1d", label: "Top of the day" }, { value: "toplist:1w", label: "Top of the week" },
                          { value: "toplist:1M", label: "Top of the month" }, { value: "random:", label: "Random" },
                          { value: "date_added:", label: "Newest" }]
                value: (pane.srcOpts.sorting || "toplist") + ":" + ((pane.srcOpts.sorting || "toplist") === "toplist" ? (pane.srcOpts.topRange || "1w") : "")
                onPicked: v => { const p = v.split(":"); pane.setSrcOpt("sorting", p[0]); if (p[1]) pane.setSrcOpt("topRange", p[1]); }
            }
        }
        SettingsRow {
            visible: pane.spec.source === "wallhaven" || pane.spec.source === "reddit"
            label: "At least as big as my screen"
            note: `Only pictures of ${Wallpaper.maxPx[0]}×${Wallpaper.maxPx[1]} or more, so they stay sharp.`
            Toggle { checked: pane.srcOpts.atLeastScreen !== false; onToggled: c => pane.setSrcOpt("atLeastScreen", c) }
        }
        SettingsRow {
            visible: pane.spec.source === "wallhaven"
            label: "Shape"
            note: "Only wide pictures for wide screens (e.g. 21x9 for an ultrawide)."
            Dropdown {
                implicitWidth: 200
                options: [{ value: "", label: "Any shape" }, { value: "landscape", label: "Any landscape" },
                          { value: "16x9,16x10", label: "16:9 and 16:10" }, { value: "21x9,32x9,48x9", label: "Ultrawide (21:9 and wider)" }]
                value: pane.srcOpts.ratios || ""
                onPicked: v => pane.setSrcOpt("ratios", v)
            }
        }
        // Reddit
        SettingsDivider { visible: pane.spec.source === "reddit" }
        SettingsRow {
            visible: pane.spec.source === "reddit"
            label: "Subreddits"
            note: "Separate with commas, e.g. EarthPorn, SkyPorn, CityPorn, wallpaper."
            TextBox { implicitWidth: 240; placeholder: "EarthPorn"; text: pane.srcOpts.subreddits || ""; onAccepted: pane.setSrcOpt("subreddits", text.trim()) }
        }
        SettingsRow {
            visible: pane.spec.source === "reddit"
            label: "Top posts of the"
            Segmented {
                options: [{ value: "day", label: "Day" }, { value: "week", label: "Week" }, { value: "month", label: "Month" }]
                value: pane.srcOpts.top || "day"
                onPicked: v => pane.setSrcOpt("top", v)
            }
        }
        SettingsRow {
            visible: pane.spec.source === "reddit"
            label: "Wide pictures only"
            note: "Skip pictures narrower than your screen's shape."
            Toggle {
                checked: !!pane.srcOpts.minAspect
                onToggled: c => pane.setSrcOpt("minAspect", c ? Math.round(Wallpaper.maxPx[0] / Wallpaper.maxPx[1] * 90) / 100 : 0)
            }
        }
        // Unsplash / Pexels search
        SettingsDivider { visible: pane.spec.source === "unsplash" || pane.spec.source === "pexels" }
        SettingsRow {
            visible: pane.spec.source === "unsplash" || pane.spec.source === "pexels"
            label: "Search for"
            note: "Words such as forest, ocean, architecture. Empty: editors' picks."
            TextBox { implicitWidth: 240; placeholder: "Anything"; text: pane.srcOpts.query || ""; onAccepted: pane.setSrcOpt("query", text.trim()) }
        }
        // NOAA
        SettingsDivider { visible: pane.spec.source === "noaa" }
        SettingsRow {
            visible: pane.spec.source === "noaa"
            label: "Satellite"
            note: "GOES-East sees the Americas and the Atlantic, GOES-West the Pacific."
            Segmented {
                options: [{ value: "GOES19", label: "GOES-East" }, { value: "GOES18", label: "GOES-West" }]
                value: pane.srcOpts.satellite || "GOES19"
                onPicked: v => pane.setSrcOpt("satellite", v)
            }
        }
        // Bing / Spotlight market
        SettingsDivider { visible: pane.spec.source === "bing" || pane.spec.source === "spotlight" }
        SettingsRow {
            visible: pane.spec.source === "bing" || pane.spec.source === "spotlight"
            label: "Region"
            note: "Different regions get different pictures and captions."
            Dropdown {
                implicitWidth: 200
                options: ["en-US", "en-GB", "en-CA", "en-AU", "en-IN", "de-DE", "fr-FR", "es-ES", "it-IT", "ja-JP", "zh-CN", "pt-BR"].map(m => ({ value: m, label: m }))
                value: pane.srcOpts.market || "en-US"
                onPicked: v => pane.setSrcOpt("market", v)
            }
        }
        // Keys
        SettingsDivider { visible: !!(pane.srcInfo && (pane.srcInfo.key || pane.spec.source === "wallhaven")) }
        SettingsRow {
            visible: !!(pane.srcInfo && (pane.srcInfo.key || pane.spec.source === "wallhaven"))
            label: Wallpaper.keys[pane.spec.source] ? "API key (saved)" : "API key"
            note: pane.spec.source === "wallhaven" ? "Optional: from wallhaven.cc/settings/account. Kept in your keyring."
                : "Kept in your keyring, or a private file if there's none. Press Return to save; empty removes it."
            TextBox {
                id: keyBox
                implicitWidth: 240
                placeholder: Wallpaper.keys[pane.spec.source] ? "••••••••  (saved)" : "Paste the key"
                input.echoMode: TextInput.Password
                onAccepted: {
                    const v = text.trim();
                    const src = pane.spec.source;
                    Wallpaper.setKey(src, v, () => { if (v) Wallpaper.fetch(src, 0, true); });
                    text = "";
                }
            }
        }
        SettingsDivider {}
        Item {
            width: parent.width
            implicitHeight: 40
            PushButton {
                anchors.verticalCenter: parent.verticalCenter
                text: Wallpaper.busy[pane.spec.source] ? "Downloading…" : "Get a new picture now"
                enabled: !Wallpaper.busy[pane.spec.source]
                onClicked: Wallpaper.fetch(pane.spec.source, 0, true)
            }
        }
    }

    // Slideshow options.
    SettingsGroup {
        visible: pane.spec.type === "folder"
        SettingsRow {
            label: "Change picture"
            note: "How often the slideshow moves on."
            Dropdown {
                implicitWidth: 180
                options: [1, 5, 15, 30, 60, 180, 1440].map(m => ({ value: m, label: m < 60 ? "Every " + m + (m === 1 ? " minute" : " minutes") : m === 1440 ? "Every day" : "Every " + (m / 60) + (m === 60 ? " hour" : " hours") }))
                value: Number(pane.spec.interval) || 30
                onPicked: v => pane.choose(Object.assign({}, pane.spec, { interval: v }))
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Random order"
            Toggle { checked: !!pane.spec.shuffle; onToggled: c => pane.choose(Object.assign({}, pane.spec, { shuffle: c })) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Include subfolders"
            Toggle { checked: !!pane.spec.recursive; onToggled: c => pane.choose(Object.assign({}, pane.spec, { recursive: c })) }
        }
    }

    // ---------------------------------------------------------------- the grid

    component Tile: MouseArea {
        id: tile
        property var tspec: null
        property string name: ""
        property string thumb: ""
        property string icon: ""
        property string tip: ""
        property bool removable: false
        property bool action: false      // an "Add…" tile
        property string shaderUrl: ""    // live shader thumbnail
        signal removeRequested()
        width: 150
        height: 116
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: if (tspec) pane.choose(tspec)
        Rectangle {
            id: box
            width: parent.width
            height: 84
            radius: 9
            color: tile.action ? "transparent" : Theme.bgAlt
            border.width: tile.tspec && pane.isCurrent(tile.tspec) ? 3 : 1
            border.color: tile.tspec && pane.isCurrent(tile.tspec) ? Theme.accent : tile.action ? Theme.fgDim : Theme.border
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: box.border.width
                visible: tile.thumb !== ""
                source: tile.thumb ? "file://" + tile.thumb : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 300
            }
            Loader {
                anchors.fill: parent
                anchors.margins: box.border.width
                active: tile.shaderUrl !== ""
                sourceComponent: ShaderEffect {
                    property real iTime: 18.0
                    property size res: Qt.size(width, height)
                    property real dark: Theme.dark ? 1 : 0
                    fragmentShader: tile.shaderUrl
                    // Animate only under the pointer.
                    NumberAnimation on iTime { running: tile.containsMouse; from: 18; to: 1018; duration: 1000000; loops: Animation.Infinite }
                }
            }
            Icon {
                anchors.centerIn: parent
                visible: tile.thumb === "" && tile.shaderUrl === ""
                implicitSize: 32
                name: tile.icon || "preferences-desktop-wallpaper"
            }
            MouseArea {
                visible: tile.removable && tile.containsMouse
                anchors { top: parent.top; right: parent.right; margins: 4 }
                width: 20; height: 20
                onClicked: tile.removeRequested()
                Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(0, 0, 0, 0.6) }
                Label { anchors.centerIn: parent; text: "×"; color: "white" }
            }
        }
        Label {
            anchors.top: box.bottom
            anchors.topMargin: 4
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: tile.name
            font.pointSize: Theme.smallFontSize
            color: tile.tspec && pane.isCurrent(tile.tspec) ? Theme.fg : Theme.fgDim
        }
        Tooltip { anchorItem: box; text: tile.tip; hovered: tile.containsMouse && tile.tip !== "" }
    }
    component Section: ColumnLayout {
        property string title
        property string note: ""
        default property alias tiles: flow.data
        Layout.fillWidth: true
        spacing: 6
        Label { text: parent.title; font.weight: Font.DemiBold; Layout.fillWidth: true }
        Label {
            visible: parent.note !== ""
            text: parent.note
            Layout.fillWidth: true
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        Flow { id: flow; Layout.fillWidth: true; spacing: 12 }
    }
    function sourceThumb(id) {
        const it = Wallpaper.currentItem(id);
        return it ? it.file : "";
    }

    Section {
        title: "Pictures of the day"
        note: "A new picture from the web every day (or more often), with its story. Go back through earlier ones with Previous."
        Repeater {
            model: Wallpaper.sources.filter(s => s.group === "daily")
            Tile {
                required property var modelData
                tspec: ({ type: "potd", source: modelData.id })
                name: modelData.name
                thumb: pane.sourceThumb(modelData.id)
                icon: "internet-services"
                tip: modelData.note
            }
        }
    }

    Section {
        title: "Dynamic"
        note: "Wallpapers that change with the time of day or follow light and dark mode. Add GNOME XML sets, macOS .heic dynamic desktops or a folder with a dynamic.json."
        Repeater {
            model: Wallpaper.dynamicSets.concat((pane.cfg.added || []).filter(a => a.type === "dynamic"))
            Tile {
                required property var modelData
                tspec: ({ type: "dynamic", path: modelData.path, index: modelData.index || 0 })
                name: modelData.name || pane.baseName(modelData.path)
                thumb: modelData.preview || ""
                icon: "preferences-desktop-wallpaper"
                tip: modelData.kind === "time" || modelData.kind === "heic" ? "Changes through the day" : modelData.kind === "appearance" ? "Light and dark versions" : ""
                removable: modelData.type === "dynamic"
                onRemoveRequested: Wallpaper.removeItem(modelData.path)
            }
        }
        Tile {
            action: true
            name: "Add…"
            icon: "list-add"
            tip: "Choose a .heic, a GNOME .xml or a dynamic.json"
            onClicked: { dynDialog.open(); }
        }
    }

    Section {
        title: "Animated"
        note: "Videos (MP4, WebM, MKV) play silently, decoded by the graphics card. Videos in ~/Videos/Wallpapers show up here by themselves."
        Repeater {
            model: Wallpaper.mediaItems.filter(m => m.kind === "video").concat((pane.cfg.added || []).filter(a => a.type === "video"))
            Tile {
                required property var modelData
                tspec: ({ type: "video", path: modelData.path })
                name: modelData.name || pane.baseName(modelData.path)
                thumb: { void Wallpaper.posters; return Wallpaper.poster(modelData.path, "video"); }
                icon: "video-x-generic"
                removable: modelData.type === "video"
                onRemoveRequested: Wallpaper.removeItem(modelData.path)
            }
        }
        Tile {
            action: true
            name: "Add video…"
            icon: "list-add"
            onClicked: videoDialog.open()
        }
    }

    Section {
        title: "Shaders"
        note: "Moving pictures drawn by the graphics card, light or dark with your appearance. Add a Shadertoy shader (a .glsl file with mainImage) to make your own."
        Repeater {
            model: Wallpaper.shaders.concat(Wallpaper.mediaItems.filter(m => m.kind === "shader"),
                                            (pane.cfg.added || []).filter(a => a.type === "shader"))
            Tile {
                required property var modelData
                tspec: ({ type: "shader", path: modelData.path })
                name: modelData.name || pane.baseName(modelData.path)
                shaderUrl: modelData.path.startsWith("builtin:") ? Wallpaper.shaderUrl(modelData.path) : ""
                thumb: modelData.path.startsWith("builtin:") ? "" : (Wallpaper.posters[modelData.path] || "")
                icon: "applications-graphics"
                tip: modelData.note || ""
                removable: modelData.type === "shader"
                onRemoveRequested: Wallpaper.removeItem(modelData.path)
            }
        }
        Tile {
            action: true
            name: "Add shader…"
            icon: "list-add"
            onClicked: shaderDialog.open()
        }
    }

    Section {
        title: "Wallpaper Engine"
        note: Wallpaper.weProjects.length
            ? "Scenes, videos and web wallpapers from Wallpaper Engine on Steam, played by linux-wallpaperengine. Subscribe to more in the Steam Workshop; they appear here."
            : "Install Wallpaper Engine from Steam to use its wallpapers here (played by linux-wallpaperengine)."
        Repeater {
            model: Wallpaper.weProjects
            Tile {
                required property var modelData
                tspec: ({ type: "we", path: modelData.path, title: modelData.title, preview: modelData.preview })
                name: modelData.title
                thumb: modelData.preview
                icon: "applications-games"
                tip: (modelData.type === "scene" ? "Scene" : modelData.type === "video" ? "Video" : modelData.type === "web" ? "Web page" : modelData.type)
                     + (modelData.workshop ? " from the Workshop" : "")
            }
        }
    }

    Section {
        title: "Your pictures"
        note: "A picture of your own, or a folder shown as a slideshow."
        Repeater {
            model: (pane.cfg.folders || [])
            Tile {
                required property var modelData
                tspec: ({ type: "folder", path: modelData.path, interval: modelData.interval || 30,
                          shuffle: modelData.shuffle !== false, recursive: modelData.recursive !== false })
                name: pane.baseName(modelData.path) || modelData.path
                thumb: { void Wallpaper.folders; const f = Wallpaper.folderFiles(tspec); return f.length ? f[0] : ""; }
                icon: "folder-pictures"
                tip: "Slideshow of " + modelData.path
                removable: true
                onRemoveRequested: Wallpaper.removeItem(modelData.path)
            }
        }
        Repeater {
            model: (pane.cfg.added || []).filter(a => a.type === "image")
            Tile {
                required property var modelData
                tspec: ({ type: "image", path: modelData.path })
                name: pane.baseName(modelData.path)
                thumb: modelData.path
                removable: true
                onRemoveRequested: Wallpaper.removeItem(modelData.path)
            }
        }
        Tile {
            action: true
            name: "Add picture…"
            icon: "list-add"
            onClicked: imageDialog.open()
        }
        Tile {
            action: true
            name: "Add folder…"
            icon: "folder-new"
            onClicked: folderDialog.open()
        }
    }

    Section {
        title: "Photos from the web"
        note: "Photo sites with millions of pictures: pick words to search for below once chosen. Unsplash, Pexels and Flickr need a free key."
        Repeater {
            model: Wallpaper.sources.filter(s => s.group === "web")
            Tile {
                required property var modelData
                tspec: ({ type: "potd", source: modelData.id })
                name: modelData.name
                thumb: pane.sourceThumb(modelData.id)
                icon: "internet-web-browser"
                tip: modelData.note
            }
        }
    }

    // ---------------------------------------------------------------- animation options

    Label { text: "Animation"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Still image only"
            note: "Never animate: videos, shaders and Wallpaper Engine show a still picture instead."
            Toggle { checked: !!pane.cfg.stillOnly; onToggled: c => Settings.set("wallpaper.stillOnly", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Frame rate"
            note: "For shaders and Wallpaper Engine. Lower uses less power."
            enabled: !pane.cfg.stillOnly
            Segmented {
                options: [15, 24, 30, 60].map(f => ({ value: f, label: f + " fps" }))
                value: Number(pane.cfg.fps) || 30
                onPicked: v => Settings.set("wallpaper.fps", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Shader quality"
            note: "Shaders are soft, so half resolution looks the same at a quarter of the work."
            enabled: !pane.cfg.stillOnly
            Segmented {
                options: [{ value: 0.5, label: "Half" }, { value: 0.75, label: "High" }, { value: 1, label: "Full" }]
                value: Number(pane.cfg.shaderScale) || 0.5
                onPicked: v => Settings.set("wallpaper.shaderScale", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Pause when windows cover the screen"
            note: "Stop animating a screen whose desktop you can't see anyway."
            enabled: !pane.cfg.stillOnly
            Toggle { checked: pane.cfg.pauseCovered !== false; onToggled: c => Settings.set("wallpaper.pauseCovered", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Pause while an app is full screen"
            note: "Leaves the graphics card to games and videos."
            enabled: !pane.cfg.stillOnly
            Toggle { checked: pane.cfg.pauseFullscreen !== false; onToggled: c => Settings.set("wallpaper.pauseFullscreen", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Pause on battery"
            enabled: !pane.cfg.stillOnly
            Toggle { checked: pane.cfg.pauseBattery !== false; onToggled: c => Settings.set("wallpaper.pauseBattery", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Pause when idle or locked"
            note: "Once the screen locks or turns off (Sleep & Power)."
            enabled: !pane.cfg.stillOnly
            Toggle { checked: pane.cfg.pauseIdle !== false; onToggled: c => Settings.set("wallpaper.pauseIdle", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Wallpaper Engine sound"
            note: "Some Wallpaper Engine wallpapers play music or sounds."
            Toggle { checked: !!pane.cfg.weAudio; onToggled: c => Settings.set("wallpaper.weAudio", c) }
        }
    }

    // ---------------------------------------------------------------- file pickers

    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")); }
    FileDialog {
        id: imageDialog
        title: "Choose a picture"
        currentFolder: "file://" + Wallpaper.home + "/Pictures"
        nameFilters: ["Pictures (*.jpg *.jpeg *.png *.webp *.jxl *.avif *.heic *.svg)", "All files (*)"]
        onAccepted: { const p = pane.localPath(selectedFile); Wallpaper.addItem("image", p); pane.choose({ type: "image", path: p }); }
    }
    FileDialog {
        id: videoDialog
        title: "Choose a video"
        currentFolder: "file://" + Wallpaper.home + "/Videos"
        nameFilters: ["Videos (*.mp4 *.webm *.mkv *.mov *.m4v)", "All files (*)"]
        onAccepted: { const p = pane.localPath(selectedFile); Wallpaper.addItem("video", p); pane.choose({ type: "video", path: p }); }
    }
    FileDialog {
        id: shaderDialog
        title: "Choose a Shadertoy shader"
        currentFolder: "file://" + Wallpaper.home
        nameFilters: ["Shaders (*.glsl *.frag *.fs)", "All files (*)"]
        onAccepted: { const p = pane.localPath(selectedFile); Wallpaper.addItem("shader", p); pane.choose({ type: "shader", path: p }); }
    }
    FileDialog {
        id: dynDialog
        title: "Choose a dynamic wallpaper"
        currentFolder: "file://" + Wallpaper.home + "/Pictures"
        nameFilters: ["Dynamic wallpapers (*.heic *.heif *.xml *.json)", "All files (*)"]
        onAccepted: {
            let p = pane.localPath(selectedFile);
            if (p.endsWith("/dynamic.json")) p = p.replace(/\/dynamic\.json$/, "");
            Wallpaper.addItem("dynamic", p);
            pane.choose({ type: "dynamic", path: p, index: 0 });
        }
    }
    FolderDialog {
        id: folderDialog
        title: "Choose a folder of pictures"
        currentFolder: "file://" + Wallpaper.home + "/Pictures"
        onAccepted: {
            const p = pane.localPath(selectedFolder);
            Wallpaper.addFolder(p);
            pane.choose({ type: "folder", path: p, interval: 30, shuffle: true, recursive: true });
        }
    }
}
