import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Window Rules (services/WindowRules.qml): per-app choices for
// how new windows open.
ColumnLayout {
    id: pane
    // The app list for the pickers is built only while this pane shows.
    Binding { target: WindowRules; property: "choicesWanted"; value: pane.visible }
    spacing: 14

    Label {
        visible: !Compositor.isArbor
        Layout.fillWidth: true
        text: "Window rules work under the arbor compositor."
        color: Theme.warn
    }
    Label {
        Layout.fillWidth: true
        text: "Choose how an app's windows open: docked beside others or floating on the desktop, on which workspace, how big. They apply to windows opened from now on."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        SettingsRow {
            label: "Add an app"
            note: "Apps that are open now come first; type to search."
            Dropdown {
                implicitWidth: 300
                placeholder: "Choose an app…"
                options: WindowRules.appChoices
                searchable: true
                listWidth: 380
                onPicked: v => {
                    const c = WindowRules.appChoices.find(x => x.value === v);
                    WindowRules.add(v, c ? c.label : v, c ? c.icon : "");
                }
            }
        }
    }

    Repeater {
        model: WindowRules.rules
        SettingsGroup {
            id: rg
            required property var modelData
            required property int index
            readonly property var r: Object.assign({}, WindowRules.blank, modelData)
            function set(k, v) { WindowRules.update(rg.index, k, v); }

            Item {
                width: parent.width
                height: 48
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Icon { implicitSize: 28; name: rg.r.icon || rg.r.appId; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Label { text: rg.r.name || rg.r.appId; font.weight: Font.DemiBold }
                        Label { text: rg.r.appId; color: Theme.fgDim; font.pointSize: Theme.smallFontSize }
                    }
                }
                PushButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Remove"
                    tooltip: "Forget the rules for this app; its windows open the usual way."
                    onClicked: WindowRules.remove(rg.index)
                }
            }
            SettingsDivider {}
            SettingsRow {
                label: "Open windows"
                note: "Docked: placed beside your other docked windows. Floating: free on the desktop, on top."
                Segmented {
                    options: [{ value: "default", label: "Usual" }, { value: "docked", label: "Docked" }, { value: "floating", label: "Floating" }]
                    value: rg.r.open
                    onPicked: v => rg.set("open", v)
                }
            }
            SettingsDivider {}
            SettingsRow {
                label: "On workspace"
                note: "Type a name to always open there (a workspace with that name is kept for it). Empty: the current one."
                TextBox {
                    implicitWidth: 200
                    placeholder: "Current workspace"
                    text: rg.r.workspace
                    input.onEditingFinished: if (text.trim() !== rg.r.workspace) rg.set("workspace", text.trim())
                }
            }
            SettingsDivider {}
            SettingsRow {
                label: "Size"
                note: "Width and height in pixels when it opens. Empty: the app decides."
                Row {
                    spacing: 6
                    TextBox {
                        implicitWidth: 80
                        placeholder: "Width"
                        text: rg.r.width > 0 ? String(rg.r.width) : ""
                        input.validator: IntValidator { bottom: 0; top: 20000 }
                        input.onEditingFinished: rg.set("width", parseInt(text) || 0)
                    }
                    Label { text: "×"; anchors.verticalCenter: parent.verticalCenter }
                    TextBox {
                        implicitWidth: 80
                        placeholder: "Height"
                        text: rg.r.height > 0 ? String(rg.r.height) : ""
                        input.validator: IntValidator { bottom: 0; top: 20000 }
                        input.onEditingFinished: rg.set("height", parseInt(text) || 0)
                    }
                }
            }
            SettingsDivider {}
            SettingsRow {
                label: "Title bar"
                note: "The bar with the minimize, maximize and close buttons (for apps that use arbor's)."
                Segmented {
                    options: [{ value: "default", label: "Usual" }, { value: "on", label: "Show" }, { value: "off", label: "Hide" }]
                    value: rg.r.titleBar
                    onPicked: v => rg.set("titleBar", v)
                }
            }
            SettingsDivider {}
            SettingsRow {
                label: "Opacity"
                note: "Below 100% you can see through its windows."
                ValueSlider {
                    implicitWidth: 260
                    from: 20; to: 100; step: 5; suffix: "%"
                    value: rg.r.opacity
                    onMoved: v => rg.set("opacity", v)
                }
            }
            SettingsDivider {}
            SettingsRow {
                label: "Adaptive sync"
                note: "On: smooth, tear-free motion for games and video while this app is shown (needs a display that supports it)."
                Segmented {
                    options: [{ value: "default", label: "Usual" }, { value: "on", label: "On" }, { value: "off", label: "Off" }]
                    value: rg.r.vrr
                    onPicked: v => rg.set("vrr", v)
                }
            }
        }
    }
    Label {
        visible: WindowRules.rules.length === 0
        Layout.fillWidth: true
        text: "No apps have rules yet."
        color: Theme.fgDim
    }
    Label {
        visible: WindowRules.error !== ""
        Layout.fillWidth: true
        text: WindowRules.error
        color: Theme.bad
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
}
