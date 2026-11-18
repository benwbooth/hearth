import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../../widgets"
import "../.."

// Batteries: this is a desktop, so it only shows when something runs on a
// battery (mice, keyboards, controllers, headsets, or a laptop battery).
// The bar icon is the emptiest device; the popup lists them all, plus power
// profile switching.
Indicator {
    id: root

    // Peripheral batteries often don't set IsPresent, so a reported charge
    // counts too.
    readonly property var devices: UPower.devices.values.filter(d =>
        d.ready !== false
        && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Unknown
        && (d.isPresent || d.percentage > 0))
        .sort((a, b) => a.percentage - b.percentage)
    readonly property var lowest: devices.length > 0 ? devices[0] : null

    function pct(d) { return Math.round(d.percentage * 100) + "%"; }
    function label(d) {
        return d.model || UPowerDeviceType.toString(d.type);
    }
    function typeIcon(d) {
        switch (d.type) {
        case UPowerDeviceType.Mouse: return "input-mouse";
        case UPowerDeviceType.Keyboard: return "input-keyboard";
        case UPowerDeviceType.GamingInput: return "input-gamepad";
        case UPowerDeviceType.Touchpad: return "input-touchpad";
        case UPowerDeviceType.Tablet: case UPowerDeviceType.Pen: return "input-tablet";
        case UPowerDeviceType.Headset: return "audio-headset";
        case UPowerDeviceType.Headphones: return "audio-headphones";
        case UPowerDeviceType.Speakers: case UPowerDeviceType.OtherAudio: return "audio-speakers";
        case UPowerDeviceType.Phone: return "smartphone";
        case UPowerDeviceType.Ups: return "battery-ups";
        case UPowerDeviceType.Battery: return "battery";
        default: return "battery";
        }
    }
    function stateText(d) {
        switch (d.state) {
        case UPowerDeviceState.Charging: return "charging";
        case UPowerDeviceState.FullyCharged: return "full";
        case UPowerDeviceState.PendingCharge: return "not charging";
        default: return "";
        }
    }
    function profileName(p) {
        switch (p) {
        case PowerProfile.PowerSaver: return "Power Saver";
        case PowerProfile.Performance: return "Performance";
        default: return "Balanced";
        }
    }

    shown: devices.length > 0
    icon: lowest?.iconName || "battery"
    iconFallback: "battery"
    tooltip: lowest ? (devices.length === 1 ? label(lowest) + ": " + pct(lowest)
                                            : "Lowest battery: " + label(lowest) + " " + pct(lowest)) : ""
    tooltipSub: devices.length > 1 ? devices.map(d => label(d) + ": " + pct(d)).join("\n") : ""

    popupContent: ColumnLayout {
        spacing: 4

        Label {
            Layout.fillWidth: true
            text: "Batteries"
            font.weight: Font.DemiBold
            color: Theme.fgDim
        }

        Repeater {
            model: root.devices
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 340
                spacing: 8
                Icon {
                    implicitSize: 22
                    name: root.typeIcon(row.modelData)
                    fallback: "battery"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: root.label(row.modelData)
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.stateText(row.modelData)
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                }
                Icon {
                    implicitSize: 16
                    name: row.modelData.iconName
                    fallback: "battery"
                }
                Label {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: root.pct(row.modelData)
                    color: row.modelData.percentage <= 0.15 ? Theme.bad
                         : row.modelData.percentage <= 0.3 ? Theme.warn : Theme.fg
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 8
            text: "Power profile"
            font.weight: Font.DemiBold
            color: Theme.fgDim
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: PowerProfiles.hasPerformanceProfile
                       ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                       : [PowerProfile.PowerSaver, PowerProfile.Balanced]
                delegate: BarButton {
                    required property int modelData
                    Layout.fillWidth: true
                    implicitHeight: 34
                    iconSize: 16
                    icon: modelData === PowerProfile.PowerSaver ? "battery-profile-powersave"
                        : modelData === PowerProfile.Performance ? "battery-profile-performance"
                        : "battery-profile-balanced"
                    iconFallback: "speedometer"
                    text: root.profileName(modelData)
                    active: PowerProfiles.profile === modelData
                    onClicked: PowerProfiles.profile = modelData
                }
            }
        }
        Label {
            Layout.fillWidth: true
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: "Performance limited: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
            color: Theme.warn
            font.pointSize: Theme.smallFontSize
        }
    }
}
