import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Displays (services/Displays.qml). Changes are collected here
// and sent with Apply; then "Keep these settings?" counts down 15 s.
ColumnLayout {
    id: pane
    spacing: 14

    property var draft: ({})
    property string selected: ""
    readonly property bool dirty: JSON.stringify(draft) !== JSON.stringify(Displays.states)
    function sync() {
        pane.draft = JSON.parse(JSON.stringify(Displays.states));
        if (!pane.selected || !pane.draft[pane.selected]) pane.selected = Displays.names[0] || "";
    }
    Connections {
        target: Displays
        function onStatesChanged() { if (!pane.dirty || Object.keys(pane.draft).length === 0) pane.sync(); }
    }
    Component.onCompleted: { Displays.refresh(); sync(); }

    function edit(key, value) {
        const d = JSON.parse(JSON.stringify(pane.draft));
        if (!d[pane.selected]) return;
        d[pane.selected][key] = value;
        pane.draft = d;
    }
    readonly property var cur: draft[selected] || null
    readonly property var out: Displays.live[selected] || null

    // Modes of the selected output, grouped by resolution.
    readonly property var resolutions: {
        if (!out) return [];
        const seen = {};
        const list = [];
        for (const m of out.modes) {
            const k = `${m.width}x${m.height}`;
            if (seen[k]) continue;
            seen[k] = true;
            list.push({ value: k, label: `${m.width} × ${m.height}` + (m.is_preferred ? " (best for this display)" : ""), px: m.width * m.height });
        }
        list.sort((a, b) => b.px - a.px);
        return list;
    }
    readonly property string curRes: cur ? (cur.mode || "").split("@")[0] : ""
    readonly property var rates: {
        if (!out) return [];
        const list = out.modes.filter(m => `${m.width}x${m.height}` === pane.curRes)
            .sort((a, b) => b.refresh_rate - a.refresh_rate)
            .map(m => ({ value: Displays.modeString(m), label: (m.refresh_rate / 1000).toFixed(m.refresh_rate % 1000 ? 2 : 0) + " Hz" }));
        return list;
    }
    function pickResolution(res) {
        // Keep the refresh rate if this resolution has it, else the fastest.
        const oldHz = cur && cur.mode.split("@")[1] ? parseFloat(cur.mode.split("@")[1]) : 0;
        const modes = out.modes.filter(m => `${m.width}x${m.height}` === res).sort((a, b) => b.refresh_rate - a.refresh_rate);
        if (!modes.length) return;
        const same = modes.find(m => Math.abs(m.refresh_rate / 1000 - oldHz) < 0.5);
        edit("mode", Displays.modeString(same || modes[0]));
    }

    Label {
        visible: !Compositor.isArbor
        Layout.fillWidth: true
        text: "Display settings work under the arbor compositor."
        color: Theme.warn
    }
    Label {
        visible: Compositor.isArbor && Displays.names.length === 0
        Layout.fillWidth: true
        text: "Looking for displays…"
        color: Theme.fgDim
    }

    // --- arrangement ---
    Label {
        visible: Displays.names.length > 0
        Layout.fillWidth: true
        text: Displays.names.length > 1 ? "Drag the screens to match how they stand on your desk. Click one to change its settings below."
                                         : "Your display. Its settings are below."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    Rectangle {
        id: arrange
        visible: Displays.names.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 220
        radius: Theme.popupRadius
        color: Theme.bgAlt
        border.color: Theme.border
        clip: true

        // Fit every (on) output's logical rectangle into the box.
        readonly property var rects: {
            const r = {};
            for (const n in pane.draft) {
                const s = pane.draft[n];
                const sz = Displays.logicalSize(s);
                r[n] = { x: s.x, y: s.y, w: sz.w, h: sz.h, on: s.on };
            }
            return r;
        }
        readonly property var bounds: {
            let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
            for (const n in rects) { const q = rects[n]; x0 = Math.min(x0, q.x); y0 = Math.min(y0, q.y); x1 = Math.max(x1, q.x + q.w); y1 = Math.max(y1, q.y + q.h); }
            if (x0 === Infinity) return { x: 0, y: 0, w: 1, h: 1 };
            return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
        }
        // Frozen while dragging so the view doesn't move under the pointer.
        property var view: ({ x: 0, y: 0, k: 0.05 })
        property bool dragging: false
        function fit() {
            if (dragging) return;
            const b = bounds;
            const k = Math.min((width - 60) / Math.max(1, b.w), (height - 40) / Math.max(1, b.h));
            view = { x: b.x - (width / k - b.w) / 2, y: b.y - (height / k - b.h) / 2, k: k };
        }
        onBoundsChanged: fit()
        onWidthChanged: fit()

        // Snap a moved output so it touches the others edge to edge and
        // doesn't overlap any of them.
        function snap(name, x, y) {
            const me = rects[name];
            const others = Object.keys(rects).filter(n => n !== name && rects[n].on).map(n => rects[n]);
            if (!others.length) return { x: 0, y: 0 };
            let best = null;
            const near = 14 / Math.max(view.k, 0.0001);    // 14 screen px
            for (const o of others) {
                const cands = [
                    { x: o.x - me.w, y: y, side: true }, { x: o.x + o.w, y: y, side: true },   // left / right of it
                    { x: x, y: o.y - me.h, side: false }, { x: x, y: o.y + o.h, side: false }   // above / below it
                ];
                for (const c of cands) {
                    if (c.side) {
                        for (const e of [o.y, o.y + o.h - me.h, o.y + (o.h - me.h) / 2]) if (Math.abs(c.y - e) < near) { c.y = e; break; }
                        c.y = Math.max(o.y - me.h + 1, Math.min(o.y + o.h - 1, c.y));
                    } else {
                        for (const e of [o.x, o.x + o.w - me.w, o.x + (o.w - me.w) / 2]) if (Math.abs(c.x - e) < near) { c.x = e; break; }
                        c.x = Math.max(o.x - me.w + 1, Math.min(o.x + o.w - 1, c.x));
                    }
                    const overlaps = others.some(p => c.x < p.x + p.w && c.x + me.w > p.x && c.y < p.y + p.h && c.y + me.h > p.y);
                    if (overlaps) continue;
                    const d = Math.hypot(c.x - x, c.y - y);
                    if (!best || d < best.d) best = { x: Math.round(c.x), y: Math.round(c.y), d: d };
                }
            }
            return best ? { x: best.x, y: best.y } : { x: x, y: y };
        }
        // Positions start at 0,0 at the top left, as arbor expects.
        function normalize(d) {
            let x0 = Infinity, y0 = Infinity;
            for (const n in d) if (d[n].on) { x0 = Math.min(x0, d[n].x); y0 = Math.min(y0, d[n].y); }
            if (x0 === Infinity) return d;
            for (const n in d) { d[n].x -= x0; d[n].y -= y0; }
            return d;
        }

        Repeater {
            model: Object.keys(arrange.rects)
            Rectangle {
                id: mon
                required property string modelData
                readonly property var q: arrange.rects[modelData]
                property real dx: 0
                property real dy: 0
                x: (q.x - arrange.view.x) * arrange.view.k + dx
                y: (q.y - arrange.view.y) * arrange.view.k + dy
                width: q.w * arrange.view.k
                height: q.h * arrange.view.k
                radius: 4
                opacity: q.on ? 1 : 0.4
                color: Theme.dark ? "#2d4f6c" : "#b5d3ee"
                border.width: pane.selected === modelData ? 3 : 1
                border.color: pane.selected === modelData ? Theme.accent : Theme.border
                Column {
                    anchors.centerIn: parent
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: mon.modelData; font.weight: Font.DemiBold }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: mon.q.on ? `${mon.q.w} × ${mon.q.h}` : "Off"
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                }
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Displays.names.length > 1 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                    property point start
                    onPressed: m => { pane.selected = mon.modelData; start = Qt.point(m.x, m.y); arrange.dragging = true; }
                    onPositionChanged: m => {
                        if (!pressed || Displays.names.length < 2) return;
                        mon.dx += m.x - start.x;
                        mon.dy += m.y - start.y;
                    }
                    onReleased: {
                        const k = arrange.view.k;
                        const nx = mon.q.x + mon.dx / k, ny = mon.q.y + mon.dy / k;
                        mon.dx = 0; mon.dy = 0;
                        arrange.dragging = false;
                        if (Displays.names.length < 2) return;
                        const p = arrange.snap(mon.modelData, nx, ny);
                        const d = JSON.parse(JSON.stringify(pane.draft));
                        d[mon.modelData].x = p.x;
                        d[mon.modelData].y = p.y;
                        pane.draft = arrange.normalize(d);
                        arrange.fit();
                    }
                }
                Tooltip {
                    anchorItem: mon
                    text: Displays.describe(mon.modelData) + (Displays.names.length > 1 ? "\nDrag to move it next to the others." : "")
                    hovered: drag.containsMouse && !drag.pressed
                }
            }
        }
    }

    // --- the selected output ---
    RowLayout {
        visible: Displays.names.length > 1
        Layout.fillWidth: true
        Label { text: "Settings for"; color: Theme.fgDim }
        Segmented {
            options: Displays.names.map(n => ({ value: n, label: n }))
            value: pane.selected
            onPicked: v => pane.selected = v
        }
    }
    Label {
        visible: !!pane.out
        text: pane.out ? Displays.describe(pane.selected) : ""
        font.weight: Font.DemiBold
    }

    SettingsGroup {
        visible: !!pane.cur
        SettingsRow {
            label: "Use this display"
            note: "Off: the screen goes dark and windows move to the others."
            enabled: pane.cur && (!pane.cur.on || Object.values(pane.draft).filter(s => s.on).length > 1)
            tip: "You can't turn off your only display that's on."
            Toggle {
                checked: !!(pane.cur && pane.cur.on)
                onToggled: c => pane.edit("on", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Resolution"
            note: "How many pixels the screen shows. The one marked best is the screen's own."
            enabled: !!(pane.cur && pane.cur.on)
            Dropdown {
                implicitWidth: 280
                options: pane.resolutions
                value: pane.curRes
                onPicked: v => pane.pickResolution(v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Refresh rate"
            note: "How many times a second the picture is redrawn. Higher looks smoother."
            enabled: !!(pane.cur && pane.cur.on)
            Dropdown {
                implicitWidth: 180
                options: pane.rates
                value: pane.cur ? pane.cur.mode : ""
                onPicked: v => pane.edit("mode", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Scale"
            note: "Makes text and everything else bigger. 133% suits a large, sharp screen."
            enabled: !!(pane.cur && pane.cur.on)
            Segmented {
                options: [{ value: 1, label: "100%" }, { value: 1.25, label: "125%" }, { value: 1.333333, label: "133%" },
                          { value: 1.5, label: "150%" }, { value: 1.75, label: "175%" }, { value: 2, label: "200%" }]
                value: pane.cur ? pane.cur.scale : 1
                onPicked: v => pane.edit("scale", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Rotation"
            note: "Turn the picture for a screen standing on its side."
            enabled: !!(pane.cur && pane.cur.on)
            Segmented {
                options: [{ value: "normal", label: "Standard" }, { value: "90", label: "90°" },
                          { value: "180", label: "180°" }, { value: "270", label: "270°" }]
                value: pane.cur ? pane.cur.transform : "normal"
                onPicked: v => pane.edit("transform", v)
            }
        }
    }

    SettingsGroup {
        visible: !!pane.cur
        enabled: !!(pane.cur && pane.cur.on)
        SettingsRow {
            label: "High dynamic range (HDR)"
            note: "Brighter highlights and richer colours on an HDR screen. Normal content is shown at the brightness below."
            Toggle {
                checked: !!(pane.cur && pane.cur.hdr)
                onToggled: c => pane.edit("hdr", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Brightness of normal content"
            note: "In HDR, how bright ordinary (non-HDR) windows look, in nits."
            enabled: !!(pane.cur && pane.cur.hdr)
            ValueSlider {
                implicitWidth: 300
                from: 80; to: 1000; step: 10; suffix: " nits"
                value: pane.cur ? pane.cur.sdrBrightness : 400
                onMoved: v => pane.edit("sdrBrightness", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Colour profile"
            note: "Standard (sRGB): colours as sent. Display's own: corrects colours using what the screen reports about itself."
            enabled: !!(pane.cur && !pane.cur.hdr)
            tip: "Only used without HDR; HDR has its own colour handling."
            Segmented {
                options: [{ value: "srgb", label: "Standard" }, { value: "edid", label: "Display's own" }]
                value: pane.cur ? pane.cur.colorProfile : "srgb"
                onPicked: v => pane.edit("colorProfile", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Adaptive sync (FreeSync / G-Sync)"
            note: pane.out && !pane.out.vrr_supported ? "This display doesn't support adaptive sync."
                : "Smooth games without tearing. When needed: only for games and videos that ask (always on can flicker)."
            enabled: !!(pane.out && pane.out.vrr_supported)
            Segmented {
                options: [{ value: "off", label: "Off" }, { value: "on-demand", label: "When needed" }, { value: "always", label: "Always" }]
                value: pane.cur ? pane.cur.vrr : "off"
                onPicked: v => pane.edit("vrr", v)
            }
        }
    }

    Label {
        visible: Displays.error !== ""
        Layout.fillWidth: true
        text: Displays.error
        color: Theme.bad
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    RowLayout {
        visible: Displays.names.length > 0
        Layout.fillWidth: true
        spacing: 10
        PushButton {
            text: "Use the Defaults"
            enabled: !!Displays.saved
            tooltip: "Forget the display settings made here and go back to the ones in arbor's config."
            onClicked: Displays.resetAll()
        }
        Item { Layout.fillWidth: true }
        PushButton {
            text: "Undo Changes"
            enabled: pane.dirty
            tooltip: "Throw away the changes you haven't applied yet."
            onClicked: pane.sync()
        }
        PushButton {
            text: "Apply"
            primary: true
            enabled: pane.dirty && !Displays.pending
            tooltip: "Use these settings now. You'll have 15 seconds to keep them, or they're undone."
            onClicked: {
                const next = {};
                for (const n in pane.draft) if (JSON.stringify(pane.draft[n]) !== JSON.stringify(Displays.states[n])) next[n] = pane.draft[n];
                Displays.apply(next);
            }
        }
    }
}
