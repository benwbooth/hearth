import QtQuick
import QtQuick.Shapes
import ".."

// Round crop for a user picture (Settings > Users & Accounts): the photo
// fills a square, drag pans it, the wheel (or setZoom) zooms; outside the
// circle is dimmed. `renderItem` is the square to grab (512x512) on save.
Item {
    id: root
    property string source
    property real zoom: 1
    readonly property bool ready: img.status === Image.Ready
    readonly property alias renderItem: view
    readonly property int side: 280
    implicitWidth: side
    implicitHeight: side

    // Picture size at zoom 1: its short side fills the square.
    readonly property real baseScale: ready ? side / Math.min(img.implicitWidth, img.implicitHeight) : 1
    property real cx: 0.5   // centre of the view in the picture (0..1)
    property real cy: 0.5

    function clamp() {
        const w = img.implicitWidth * baseScale * zoom, h = img.implicitHeight * baseScale * zoom;
        const hx = side / 2 / w, hy = side / 2 / h;
        cx = Math.min(Math.max(cx, hx), 1 - hx);
        cy = Math.min(Math.max(cy, hy), 1 - hy);
    }
    function setZoom(z) { zoom = Math.min(4, Math.max(1, z)); clamp(); }
    onSourceChanged: { zoom = 1; cx = 0.5; cy = 0.5; }

    Item {
        id: view
        width: root.side
        height: root.side
        clip: true
        Image {
            id: img
            source: root.source ? "file://" + root.source.split("/").map(encodeURIComponent).join("/") : ""
            // Big enough for a crisp 512 px grab at full zoom-in.
            sourceSize: Qt.size(2048, 2048)
            autoTransform: true
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            width: implicitWidth * root.baseScale * root.zoom
            height: implicitHeight * root.baseScale * root.zoom
            x: root.side / 2 - root.cx * width
            y: root.side / 2 - root.cy * height
            onStatusChanged: if (status === Image.Ready) root.clamp()
        }
    }

    // Dim outside the circle: the square minus the circle (odd-even fill).
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillRule: ShapePath.OddEvenFill
            fillColor: Qt.rgba(0, 0, 0, 0.55)
            strokeWidth: -1
            startX: 0; startY: 0
            PathLine { x: root.side; y: 0 }
            PathLine { x: root.side; y: root.side }
            PathLine { x: 0; y: root.side }
            PathLine { x: 0; y: 0 }
            PathMove { x: root.side; y: root.side / 2 }
            PathArc { x: 0; y: root.side / 2; radiusX: root.side / 2; radiusY: root.side / 2 }
            PathArc { x: root.side; y: root.side / 2; radiusX: root.side / 2; radiusY: root.side / 2 }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: Qt.rgba(1, 1, 1, 0.85)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real px
        property real py
        onPressed: m => { px = m.x; py = m.y; }
        onPositionChanged: m => {
            root.cx -= (m.x - px) / img.width;
            root.cy -= (m.y - py) / img.height;
            px = m.x; py = m.y;
            root.clamp();
        }
        onWheel: w => root.setZoom(root.zoom * Math.pow(1.0015, w.angleDelta.y))
    }
}
