import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import "indicators"
import ".."

// The macOS-style menu bar (layout "mac"): system menu, the focused app's
// name and menus on the left; tray, indicators and clock on the right.
// macOS 26 look (README "Look"): 24 pt tall, 13 pt text, the app name bold,
// titles 10 pt apart, a translucent capsule behind the open item.
// Transparent (Tahoe's default: items float on the wallpaper over a faint
// shade, lifted by a soft shadow), liquid glass or solid (Settings > Menu
// Bar > Style); the compositor blurs behind it (namespace hearth-menubar,
// layer rule hearth-glass in hypr/hyprland.lua, arbor/hearth-layer-rules.kdl).
//
// Menus behave like macOS's: they open on press, press-drag-release
// chooses an item, hovering another title while one is open switches to
// it, Left/Right move between them (pressTitle/dragTitle/releaseTitle/
// hoverTitle/switchMenu, used by BarButton and GlobalMenu's titles).
// With "automatically hide the menu bar" it slides up and comes back when
// the pointer touches the top edge.
PanelWindow {
    id: bar
    required property ShellScreen modelData
    screen: modelData

    // Read by BarButton / BarPopup / Tooltip in this window.
    readonly property string edge: "top"
    readonly property int barHeight: Theme.menuBarHeight
    readonly property int barIconSize: Theme.menuBarIconSize
    readonly property real barFontSize: Theme.menuBarFontSize
    // Popups clear the bar themselves when it reserves no space (auto-hide).
    readonly property int popupGap: autohide ? barHeight : 0

    readonly property bool autohide: Settings.menubar.autohide
    readonly property bool popupOpen: !!ShellState.activePopup && ShellState.activePopup.barWindow === bar
    readonly property bool revealed: !autohide || hover.hovered || popupOpen

    anchors { left: true; right: true; top: true }
    // Room below the bar for the glass style's soft shadow (transparent;
    // windows still only make room for barHeight, and only the bar itself
    // takes the pointer: see mask). Fixed, so the surface never resizes.
    readonly property int shadowRoom: 10
    implicitHeight: barHeight + shadowRoom
    exclusiveZone: autohide ? 0 : barHeight
    color: "transparent"
    WlrLayershell.namespace: "hearth-menubar"
    WlrLayershell.layer: WlrLayer.Top
    // While one of its menus is open the bar takes the keyboard when the
    // pointer is on it (Hyprland focuses on-demand layers under the
    // pointer), and hands the keys to the menu: arrows, Return, Escape and
    // type-ahead work right after clicking a title, before the pointer
    // ever enters the menu.
    // Handing the keyboard back waits until the menu has faded out: changing
    // it reconfigures the bar's layer surface, and doing that in the same
    // frame the menu unmapped made the bar flicker for a frame on arbor.
    property bool keyboardHeld: false
    onPopupOpenChanged: { if (popupOpen) { keyboardRelease.stop(); keyboardHeld = true; } else keyboardRelease.restart(); }
    Timer { id: keyboardRelease; interval: Theme.menuOutMs + 60; onTriggered: bar.keyboardHeld = false }
    WlrLayershell.keyboardFocus: popupOpen || keyboardHeld ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    Item {
        focus: true
        Keys.onPressed: event => {
            const a = ShellState.activePopup;
            if (a && a.open && a.barWindow === bar) a.handleKey(event);
        }
    }
    // Hidden: only a 2 px strip along the top edge takes the pointer.
    mask: Region { item: bar.revealed ? content : strip }

    Item {
        id: strip
        width: parent.width
        height: 2
    }
    HoverHandler { id: hover }

    // How bright the wallpaper is under the bar, so the transparent bar's
    // items can be white or black like macOS 26's: the top 4% of the
    // picture *as shown on this screen*: the file this screen's wallpaper
    // view shows, covering the screen's shape around its centre like Qt
    // draws it. Sampling the original's own top edge read
    // a bright sky that the ultrawide crop cuts off, and turned the items
    // black over dark rooftops.
    Image {
        id: wallSample
        visible: false
        // The exact file this screen's wallpaper shows (services/Wallpaper.qml
        // views: the smart-cropped copy when there is one).
        readonly property var view: bar.screen ? (Wallpaper.views[bar.screen.name] || null) : null
        readonly property string shown: view && view.file ? view.file : (Wallpaper.file || "")
        readonly property string url: shown ? (shown.startsWith("/") ? "file://" + shown : shown) : ""
        source: url
        sourceSize.width: 192
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) sampler.loadImage(url)
    }
    Canvas {
        id: sampler
        // The screen's shape, 96 px wide.
        width: 96
        height: Math.max(8, Math.round(96 * (bar.screen ? bar.screen.height / Math.max(1, bar.screen.width) : 9 / 16)))
        visible: false
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onImageLoaded: requestPaint()
        onPaint: {
            const url = wallSample.url;
            if (!url || !isImageLoaded(url)) return;
            const ctx = getContext("2d");
            ctx.reset();
            // Cover the canvas like the wallpaper covers the screen.
            const iw = Math.max(1, wallSample.implicitWidth), ih = Math.max(1, wallSample.implicitHeight);
            const k = Math.max(width / iw, height / ih);
            ctx.drawImage(url, (width - iw * k) / 2, (height - ih * k) / 2, iw * k, ih * k);
            const rows = Math.max(1, Math.round(height * 0.04));
            const d = ctx.getImageData(0, 0, width, rows).data;
            // Black items only where black reads everywhere: the strip has to
            // be light nearly all the way across. As soon as a real part of
            // it is dark (houses at one end, a dark sky band), the items go
            // white, which the bar's shade keeps readable over light parts.
            let dark = 0, n = 0;
            for (let i = 0; i < d.length; i += 4) {
                const l = (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255;
                if (l < 0.6) dark++;
                n++;
            }
            if (n) Theme.wallpaperLight = dark / n < 0.12;
            unloadImage(url);
        }
    }

    // --- menu behaviour ---
    property var menus: []          // menu bar menus (BarPopup.menuBarMenu), for Left/Right
    function registerMenu(p) { if (menus.indexOf(p) < 0) menus = menus.concat([p]); }
    function unregisterMenu(p) { menus = menus.filter(m => m !== p); }
    function xOf(p) { return p.anchorItem.mapToItem(null, 0, 0).x; }
    function switchMenu(from, dir) {
        const l = menus.filter(m => m.anchorItem && m.anchorItem.visible && m.anchorItem.enabled !== false)
                       .sort((a, b) => xOf(a) - xOf(b));
        const i = l.indexOf(from);
        if (i < 0 || l.length < 2) return;
        const next = l[(i + dir + l.length) % l.length];
        next.open = true;
        Qt.callLater(() => next.move(1));
    }
    // Hovering an item while another of this bar's menus is open.
    function hoverTitle(popup) {
        const a = ShellState.activePopup;
        if (a && a.open && a !== popup && a.barWindow === bar) popup.open = true;
    }
    // Press on an item: open its menu at once. While the button is held
    // the bar keeps the pointer (the menu's focus grab waits for the
    // release: BarPopup.pressHeld), so the bar feeds the pointer to the
    // menu (BarPopup.dragAt selects the row under it) or opens the title
    // under it. Releasing on a row chooses it, on a title keeps that menu
    // open, anywhere else closes it; a plain click on the open menu's title
    // closes it. Like macOS.
    property bool dragging: false
    property bool dragSeen: false
    property bool pressWasOpen: false
    property point pressAt
    property var heldPopup: null
    function hold(popup) {
        if (heldPopup && heldPopup !== popup) heldPopup.pressHeld = false;
        heldPopup = popup;
        if (popup) popup.pressHeld = true;
    }
    function pressTitle(item, popup, mouse) {
        pressWasOpen = popup.open;
        dragging = true;
        dragSeen = false;
        pressAt = item.mapToItem(null, mouse.x, mouse.y);
        hold(popup);
        if (!popup.open) popup.open = true;
    }
    function dragTitle(item, popup, mouse) {
        const g = item.mapToItem(null, mouse.x, mouse.y);
        if (Math.hypot(g.x - pressAt.x, g.y - pressAt.y) > 3) dragSeen = true;
        if (g.y >= 0 && g.y < bar.barHeight) {
            const other = menuUnder(g.x);
            if (other && !other.open) { hold(other); other.open = true; }
        }
        const a = ShellState.activePopup;
        if (a && a.open && a.dragAt) a.dragAt(g.x, g.y);
    }
    function releaseTitle(item, popup, mouse) {
        dragging = false;
        hold(null);
        const a = ShellState.activePopup;
        if (!a || !a.open) return;
        if (!dragSeen) {
            if (pressWasOpen && a === popup) popup.close();
            return;
        }
        const g = item.mapToItem(null, mouse.x, mouse.y);
        if (a.releaseAt(g.x, g.y)) return;
        if (a.containsScreenPoint(g.x, g.y)) return;
        if (g.y >= 0 && g.y < bar.barHeight && menuUnder(g.x)) return;
        a.close();
    }
    // The popup whose title (any bar button with a menu) is at x.
    property var titleItems: []
    function registerTitle(item) { if (titleItems.indexOf(item) < 0) titleItems = titleItems.concat([item]); }
    function unregisterTitle(item) { titleItems = titleItems.filter(t => t !== item); }
    function menuUnder(x) {
        for (const t of titleItems) {
            if (!t.visible || !t.menuPopup || t.enabled === false) continue;
            const p = t.mapToItem(null, 0, 0);
            if (x >= p.x && x < p.x + t.width) return t.menuPopup;
        }
        return null;
    }

    // --- the status items (right side) ---
    // Built from Settings > Menu Bar's item list (services/BarItems.qml):
    // every item exists once and is put into the row in the list's order
    // (applyOrder); where it shows comes from the list too.
    readonly property var itemById: ({
        "workspaces": workspaces, "treetop.cpu": gCpu, "treetop.mem": gMem, "treetop.gpu": gGpu, "treetop.vram": gVram,
        "treetop.disk": gDisk, "treetop.net": gNet, "treetop.temp": gTemp, "devapps": devApps, "trayicons": tray,
        "recording": recording, "media": media, "clipboard": clipboard, "zones": zones, "network": network, "rdp": rdp,
        "camera": camera, "printers": printers, "drives": drives, "weather": weather, "keyboard": keyboard,
        "battery": battery, "bluetooth": bluetooth, "brightness": brightness, "volume": volume, "notifications": bell,
        "more": tray.chevron, "help": help, "spotlight": spotlight, "controlcenter": controlCenter, "ai": assistant, "clock": clock
    })
    function applyOrder() {
        const want = BarItems.order.map(id => itemById[id]).filter(it => !!it);
        const cur = statusRow.children.filter(it => want.indexOf(it) >= 0);
        if (cur.length === want.length && cur.every((it, i) => it === want[i])) return;
        for (const it of want) it.parent = parking;
        for (const it of want) it.parent = statusRow;
    }
    Connections {
        target: BarItems
        function onOrderChanged() { Qt.callLater(bar.applyOrder); }
    }
    Component.onCompleted: Qt.callLater(applyOrder)
    // Whether an item could show at all right now (not hidden, and its
    // thing exists: a battery, a camera in use...).
    function present(id) {
        const it = itemById[id];
        if (!it) return false;
        if (id === "trayicons" || id === "more") return true;
        // Indicators know whether their thing exists (Indicator.present);
        // the rest only follow the list.
        return it.ipcName ? !!it.present : BarItems.show(id) !== "hidden";
    }
    function itemWidth(id) {
        // (The workspace map has a margin on each side.)
        return itemById[id].implicitWidth + (id === "workspaces" ? 2 * Math.round(4 * Theme.pt) : 0);
    }

    // --- fitting the status items on narrow screens ---
    // The app's menus come first (like macOS): the status items get the
    // room left after every title. What doesn't fit moves into the ⌃
    // chevron's dropdown in BarItems.overflowOrder (app icons first, from
    // the left, then the wide widgets, then the less important indicators);
    // items Settings > Menu Bar says stay ("Can move into ⌃ when the bar is
    // full" off) never move. "Only in the ⌃ menu" items are always there.
    readonly property real statusRoom: {
        const leftEnd = left.x + globalMenu.x + globalMenu.naturalWidth + Math.round(12 * Theme.pt);
        return items.width - statusRow.anchors.rightMargin - leftEnd;
    }
    readonly property var statusEntries: {
        void BarItems.list;
        return BarItems.order.filter(id => id !== "trayicons" && id !== "more" && itemById[id])
            .map(id => ({ key: id, w: itemWidth(id), present: present(id), where: BarItems.show(id) }));
    }
    readonly property var overflow: {
        const room = statusRoom;
        const entries = statusEntries;
        const dropKeys = entries.filter(e => e.present && e.where === "overflow").map(e => e.key);
        const iconsInBar = tray.iconsShow === "bar";
        const sniN = iconsInBar ? tray.shownItems.length : 0, sniW = Theme.menuBarItemWidth;
        let total = sniN * sniW;
        for (const e of entries) if (e.present && e.where === "bar") total += e.w;
        const chevronAnyway = tray.hiddenItems.length > 0 || dropKeys.length > 0 || (!iconsInBar && tray.shownItems.length > 0);
        if (total + (chevronAnyway ? tray.chevronWidth : 0) <= room) return { keys: dropKeys, sni: 0 };
        total += tray.chevronWidth;
        const keys = [];
        let sni = 0;
        if (BarItems.canMove("trayicons")) while (sni < sniN && total > room) { sni++; total -= sniW; }
        const order = BarItems.overflowOrder.concat(entries.map(e => e.key).filter(k => BarItems.overflowOrder.indexOf(k) < 0));
        for (const k of order) {
            if (total <= room) break;
            const e = entries.find(x => x.key === k);
            if (!e || !e.present || e.where !== "bar" || !BarItems.canMove(k)) continue;
            keys.push(k);
            total -= e.w;
        }
        // Taking out a wide item can leave room for things that went
        // before it: back they come, the most important first.
        for (let i = keys.length - 1; i >= 0; i--) {
            const e = entries.find(x => x.key === keys[i]);
            if (total + e.w <= room) { total += e.w; keys.splice(i, 1); }
        }
        while (sni > 0 && total + sniW <= room) { sni--; total += sniW; }
        return { keys: dropKeys.concat(keys), sni: sni };
    }
    // The dropdown's rows below the app icons, in bar order.
    readonly property var menuRows: BarItems.order.filter(id => overflow.keys.indexOf(id) >= 0)
        .map(id => ({ key: id, item: itemById[id] }))

    // --- editing in place (like macOS's Cmd-drag) ---
    // Super-drag an item, or any drag while "Edit Menu Bar" is on: drop it
    // between two others to move it, below the bar to hide it. A right
    // click on an item: Hide, Only in the ⌃ menu, Edit Menu Bar, Menu Bar
    // Settings… (app icons keep their own right-click menus).
    property string dragId: ""
    property bool dragMoved: false
    property real dragX: 0
    property real dragY: 0
    property real grabDx: 0
    readonly property bool removing: dragId !== "" && dragMoved && dragY > barHeight + Math.round(18 * Theme.pt)
                                     && !(BarItems.byId[dragId] && BarItems.byId[dragId].fixed)
    // Visible items in bar order (x within `right`), for hit tests.
    function shownIds() { return BarItems.order.filter(id => itemById[id] && itemById[id].visible && itemById[id].width > 0); }
    function idAt(x) {
        for (const id of shownIds()) {
            const it = itemById[id];
            if (x >= it.x && x < it.x + it.width) return id;
        }
        return "";
    }
    // The visible item a drop at x goes in front of ("" = the end).
    readonly property string dropBefore: {
        if (!dragId || !dragMoved) return "";
        for (const id of shownIds()) {
            if (id === dragId) continue;
            const it = itemById[id];
            if (dragX < it.x + it.width / 2) return id;
        }
        return "";
    }
    readonly property real dropMarkX: {
        if (!dragId || !dragMoved) return 0;
        if (dropBefore) return itemById[dropBefore].x;
        const ids = shownIds().filter(id => id !== dragId);
        if (!ids.length) return 0;
        const last = itemById[ids[ids.length - 1]];
        return last.x + last.width;
    }
    function endDrag(apply) {
        const id = dragId, it = itemById[id];
        if (it) it.opacity = 1;
        if (apply && id && dragMoved) {
            if (removing) BarItems.setShow(id, "hidden");
            else BarItems.moveBefore(id, dropBefore);
        }
        dragId = "";
        dragMoved = false;
    }
    property string menuId: ""
    function openItemMenu(id) {
        const it = itemById[id];
        menuId = id;
        const p = it.mapToItem(content, 0, 0);
        ctxAnchor.x = p.x;
        ctxAnchor.width = it.width;
        itemMenu.open = true;
    }

    Item {
        id: content
        width: parent.width
        height: bar.barHeight
        y: bar.revealed ? 0 : -height
        // macOS slides the auto-hidden menu bar in and out in ~0.25 s.
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

        // The bar's surface, by Settings > Menu Bar > Style:
        //  transparent: macOS 26's default. A faint shade from the top edge
        //    (too faint to be blurred), the items lifted off the wallpaper
        //    by a soft shadow.
        //  glass: liquid glass strip (GlassFrame, no corners or shadow).
        //  solid: an opaque strip.
        readonly property string style: Theme.menuBarStyle
        Rectangle {
            anchors.fill: parent
            visible: content.style === "solid"
            color: Theme.bg
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: content.style === "transparent"
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.barDark ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
        GlassFrame {
            anchors.fill: parent
            anchors.topMargin: -2
            visible: content.style === "glass"
            radius: 0
            shadow: false
            // The shader's rim is made for rounded panes; along a full-width
            // square bar it drew a flat white line. The edge is drawn below.
            rimVisible: false
            tint: Theme.menuBarTint
        }
        // The glass bar's bottom edge, macOS 26 style: light caught inside the
        // glass, a dark hairline where it ends, and a soft shadow falling onto
        // the windows below, so the bar reads as a raised pane.
        Item {
            visible: content.style === "glass"
            anchors.fill: parent
            Rectangle {
                y: parent.height - 2
                width: parent.width
                height: 1
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
            }
            Rectangle {
                y: parent.height - 1
                width: parent.width
                height: 1
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.16)
            }
            Rectangle {
                y: parent.height
                width: parent.width
                height: bar.shadowRoom
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.28 : 0.12) }
                    GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.08 : 0.04) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
            }
        }

        // Soft shadow under every item on the transparent bar (macOS lifts
        // its menu bar text and symbols off the wallpaper the same way).
        MultiEffect {
            visible: content.style === "transparent"
            source: itemsSrc
            anchors.fill: items
            shadowEnabled: true
            shadowColor: Theme.barDark ? "#000000" : "#ffffff"
            shadowOpacity: Theme.barDark ? 0.55 : 0.6
            shadowBlur: 0.45
            shadowVerticalOffset: 0.5
            shadowHorizontalOffset: 0
            blurMax: 12
            // Only the shadow: the items themselves are drawn above, as is.
            opacity: 1
            paddingRect: Qt.rect(12, 12, 24, 24)
        }
        ShaderEffectSource {
            id: itemsSrc
            sourceItem: items
            hideSource: false
            live: true
            visible: false
            recursive: false
        }

        Item {
            id: items
            anchors.fill: parent

            RowLayout {
                id: left
                height: parent.height
                x: Math.round(6 * Theme.pt)
                spacing: 0
                transform: Translate { x: 0.001; y: 0.001 }
                SystemMenu {}
                // Menus that would run into the status items are left out
                // (macOS drops them too); the space ends 12 pt before them.
                GlobalMenu { id: globalMenu; maxWidth: statusRow.x - left.x - x - Math.round(12 * Theme.pt) }
            }

            RowLayout {
                id: statusRow
                anchors.right: parent.right
                anchors.rightMargin: Math.round(6 * Theme.pt)
                height: parent.height
                spacing: 0
                transform: Translate { x: 0.001; y: 0.001 }
                // Items that don't fit or that only show in the dropdown
                // (BarButton.overflowed and the Graph items read these).
                readonly property var overflowKeys: bar.overflow.keys
                readonly property Item overflowAnchor: tray.overflowAnchor

                // Created in the default order; applyOrder() puts them in
                // Settings > Menu Bar's order.
                // A map of the workspaces: click one to go there.
                Workspaces {
                    id: workspaces
                    readonly property bool present: BarItems.show("workspaces") !== "hidden"
                    visible: present && bar.overflow.keys.indexOf("workspaces") < 0
                    screen: bar.screen
                    menuBarItem: true
                    boxScale: ({ small: 0.6, medium: 0.8 })[BarItems.opt("workspaces", "size")] || 1
                    Layout.leftMargin: Math.round(4 * Theme.pt)
                    Layout.rightMargin: Math.round(4 * Theme.pt)
                }
                // treetop's graphs, one item each.
                Graph { id: gCpu; barId: "treetop.cpu" }
                Graph { id: gMem; barId: "treetop.mem" }
                Graph { id: gGpu; barId: "treetop.gpu" }
                Graph { id: gVram; barId: "treetop.vram" }
                Graph { id: gDisk; barId: "treetop.disk" }
                Graph { id: gNet; barId: "treetop.net" }
                Graph { id: gTemp; barId: "treetop.temp" }
                DevApps { id: devApps; ipcName: "devapps"; iconSize: Theme.menuBarIconSize; implicitWidth: Theme.menuBarItemWidth }
                // App tray icons (its ⌃ chevron is placed on its own).
                Tray {
                    id: tray
                    overflowKeys: bar.overflow.keys
                    sniOverflow: bar.overflow.sni
                    menuRows: bar.menuRows
                }
                Recording { id: recording; ipcName: "recording" }
                Media { id: media; ipcName: "media" }
                Clipboard { id: clipboard; ipcName: "clipboard" }
                Zones { id: zones; ipcName: "zones" }
                Network { id: network; ipcName: "network" }
                Rdp { id: rdp; ipcName: "rdp" }
                Camera { id: camera; ipcName: "camera" }
                Printers { id: printers; ipcName: "printers" }
                Drives { id: drives; ipcName: "drives" }
                Weather { id: weather; ipcName: "weather" }
                Keyboard { id: keyboard; ipcName: "keyboard" }
                Battery { id: battery; ipcName: "battery" }
                Bluetooth { id: bluetooth; ipcName: "bluetooth" }
                Brightness { id: brightness; ipcName: "brightness" }
                Volume { id: volume; ipcName: "volume" }
                NotificationBell {
                    id: bell
                    readonly property bool present: BarItems.show("notifications") !== "hidden"
                    overflowKey: "notifications"
                    visible: present && !overflowed
                }
                HelpMenu {
                    id: help
                    readonly property bool present: BarItems.show("help") !== "hidden"
                    visible: present && !overflowed
                }
                SpotlightButton {
                    id: spotlight
                    readonly property bool present: BarItems.show("spotlight") !== "hidden"
                    overflowKey: "spotlight"
                    visible: present && !overflowed
                }
                ControlCenter { id: controlCenter }
                AssistantMenu { id: assistant }
                Clock { id: clock }
            }
            // Items wait here while applyOrder() puts them back in order.
            Item { id: parking; visible: false }
        }

        // --- editing in place ---
        // Over the status items: takes a Super-press (or any press while
        // editing) for dragging, and right clicks for the item menu;
        // everything else goes through to the item below.
        MouseArea {
            id: editArea
            x: statusRow.x
            width: statusRow.width
            height: bar.barHeight
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: BarItems.editing
            cursorShape: bar.dragId ? Qt.ClosedHandCursor : BarItems.editing ? Qt.OpenHandCursor : Qt.ArrowCursor
            onPressed: mouse => {
                const id = bar.idAt(mouse.x);
                const superHeld = (mouse.modifiers & Qt.MetaModifier) !== 0;
                if (mouse.button === Qt.RightButton) {
                    // App icons keep their own menus (Super+right click or
                    // Edit Menu Bar gives theirs).
                    if (!id || (id === "trayicons" && !BarItems.editing && !superHeld)) { mouse.accepted = false; return; }
                    bar.openItemMenu(id);
                    return;
                }
                if (!id || !(BarItems.editing || superHeld)) {
                    if (!BarItems.editing) mouse.accepted = false;
                    return;
                }
                if (ShellState.activePopup && ShellState.activePopup.close) ShellState.activePopup.close();
                const it = bar.itemById[id];
                bar.dragId = id;
                bar.dragMoved = false;
                bar.grabDx = mouse.x - it.x;
                bar.dragX = mouse.x;
                bar.dragY = mouse.y;
            }
            onPositionChanged: mouse => {
                if (!bar.dragId) return;
                bar.dragX = mouse.x;
                bar.dragY = mouse.y;
                if (!bar.dragMoved && Math.abs(mouse.x - (bar.itemById[bar.dragId].x + bar.grabDx)) + Math.abs(mouse.y - bar.barHeight / 2) > 6) {
                    bar.dragMoved = true;
                    bar.itemById[bar.dragId].opacity = 0.3;
                }
            }
            onReleased: bar.endDrag(true)
            onCanceled: bar.endDrag(false)
        }

        // Edit mode: a faint outline around every item.
        Repeater {
            model: BarItems.editing ? bar.shownIdsList : []
            Rectangle {
                required property string modelData
                readonly property Item it: bar.itemById[modelData]
                x: statusRow.x + it.x + 1
                width: Math.max(0, it.width - 2)
                y: 2
                height: bar.barHeight - 4
                radius: height / 2
                color: modelData === bar.dragId ? "transparent" : Qt.rgba(Theme.barFg.r, Theme.barFg.g, Theme.barFg.b, 0.08)
                border.color: Qt.rgba(Theme.barFg.r, Theme.barFg.g, Theme.barFg.b, 0.35)
                border.width: 1
            }
        }
        // Where the dragged item will go.
        Rectangle {
            visible: bar.dragMoved && !bar.removing
            x: statusRow.x + bar.dropMarkX - 1
            y: 3
            width: 2
            height: bar.barHeight - 6
            radius: 1
            color: Theme.accent
        }
        // The dragged item, following the pointer.
        ShaderEffectSource {
            id: ghost
            visible: bar.dragMoved
            sourceItem: bar.dragId ? bar.itemById[bar.dragId] : null
            hideSource: false
            live: true
            width: sourceItem ? sourceItem.width : 0
            height: sourceItem ? sourceItem.height : 0
            x: statusRow.x + bar.dragX - bar.grabDx
            y: bar.removing ? 4 : 0
            opacity: bar.removing ? 0.45 : 0.9
            Rectangle {
                visible: bar.removing
                anchors.right: parent.right
                anchors.top: parent.top
                width: Math.round(12 * Theme.pt)
                height: width
                radius: width / 2
                color: "#e0453a"
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.55; height: 2; radius: 1; color: "white" }
            }
        }

        // What's going on, over the app's menus while editing or dragging.
        Rectangle {
            id: hint
            visible: BarItems.editing || bar.dragMoved
            x: Math.round(6 * Theme.pt)
            y: 2
            height: bar.barHeight - 4
            width: Math.min(hintRow.implicitWidth + Math.round(20 * Theme.pt), Math.max(0, statusRow.x - x - Math.round(12 * Theme.pt)))
            radius: height / 2
            clip: true
            color: Theme.dark ? Qt.rgba(0.12, 0.12, 0.14, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.94)
            border.color: Theme.border
            transform: Translate { x: 0.001; y: 0.001 }
            MouseArea { anchors.fill: parent }
            Row {
                id: hintRow
                x: Math.round(10 * Theme.pt)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(10 * Theme.pt)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pointSize: Theme.menuBarFontSize
                    text: bar.removing ? "Release to hide “" + BarItems.label(bar.dragId) + "” (bring it back in Menu Bar Settings)"
                        : bar.dragMoved ? "Drop between two items to move “" + BarItems.label(bar.dragId) + "”; below the bar to hide it"
                        : "Drag items to rearrange them; drag one below the bar to hide it"
                }
                HintButton {
                    visible: BarItems.editing && !bar.dragMoved
                    text: "Add Items…"
                    tip: "Menu Bar Settings: show hidden items again"
                    onClicked: BarItems.openSettings("")
                }
                HintButton {
                    visible: BarItems.editing && !bar.dragMoved
                    text: "Done"
                    accent: true
                    onClicked: BarItems.editing = false
                }
            }
        }

        Item { id: ctxAnchor; y: 0; height: bar.barHeight }
    }
    readonly property var shownIdsList: { void BarItems.list; void BarItems.editing; void overflow; void statusRow.width; return shownIds(); }

    // The item menu (right click on an item).
    BarPopup {
        id: itemMenu
        anchorItem: ctxAnchor
        padding: Theme.menuPadding
        readonly property var cat: BarItems.byId[bar.menuId] || {}
        readonly property string where: bar.menuId ? BarItems.show(bar.menuId) : "bar"
        Column {
            width: Math.round(230 * Theme.pt)
            MenuHeader { text: itemMenu.cat.label || "" }
            MenuItem {
                visible: !!itemMenu.cat.rightAction
                text: itemMenu.cat.rightAction || ""
                onTriggered: { itemMenu.close(); const it = bar.itemById[bar.menuId]; if (it && it.rightClicked) it.rightClicked(); }
            }
            MenuSeparator { visible: !!itemMenu.cat.rightAction }
            MenuItem {
                visible: !!itemMenu.cat.dropdown && !itemMenu.cat.fixed
                text: itemMenu.where === "overflow" ? "Show in the Menu Bar" : "Show Only in the ⌃ Menu"
                onTriggered: { itemMenu.close(); BarItems.setShow(bar.menuId, itemMenu.where === "overflow" ? "bar" : "overflow"); }
            }
            MenuItem {
                visible: !itemMenu.cat.fixed
                text: "Hide This Item"
                onTriggered: { itemMenu.close(); BarItems.setShow(bar.menuId, "hidden"); }
            }
            MenuSeparator {}
            MenuItem {
                text: BarItems.editing ? "Done Editing" : "Edit Menu Bar"
                onTriggered: { itemMenu.close(); BarItems.editing = !BarItems.editing; }
            }
            MenuItem {
                text: "Menu Bar Settings…"
                onTriggered: { itemMenu.close(); BarItems.openSettings(bar.menuId); }
            }
        }
    }

    // One treetop graph as a menu bar item (services/BarItems.qml ids
    // "treetop.cpu"...). Hidden while it sits in the ⌃ dropdown.
    component Graph: SysMonitor {
        required property string barId
        readonly property bool present: BarItems.show(barId) !== "hidden"
        visible: present && !(parent && parent.overflowKeys !== undefined && parent.overflowKeys.indexOf(barId) >= 0)
        kinds: [BarItems.treetopKinds[barId]]
        style: BarItems.opt(barId, "style") || "graph"
        padding: Math.round(h * 0.32)
    }
    component HintButton: MouseArea {
        id: hb
        property string text
        property string tip: ""
        property bool accent: false
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        implicitWidth: hbl.implicitWidth + Math.round(16 * Theme.pt)
        implicitHeight: Math.round(18 * Theme.pt)
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: hb.accent ? Theme.accent : (hb.containsMouse ? Theme.hover : Qt.rgba(0.5, 0.5, 0.5, 0.18))
        }
        Label {
            id: hbl
            anchors.centerIn: parent
            text: hb.text
            color: hb.accent ? Theme.accentText : Theme.fg
            font.pointSize: Theme.menuBarFontSize - 1
        }
        Tooltip { anchorItem: hb; text: hb.tip; hovered: hb.containsMouse && hb.tip !== "" }
    }
}
