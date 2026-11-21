import QtQuick

// One picture filling its parent with the chosen fit, cross-fading to the
// next picture whenever `source` changes (two Images: the new one fades in
// over the old once it has loaded, so there's never a blank frame).
Item {
    id: root
    property string source: ""          // a local file path
    property string fit: "fill"         // fill | fit | center | tile
    property int fadeMs: 900
    property size pixelSize: Qt.size(width, height)
    readonly property bool ready: (a.visible && a.status === Image.Ready) || (b.visible && b.status === Image.Ready)
    signal shown()

    property bool useA: true
    readonly property url url: source ? "file://" + source : ""
    onUrlChanged: {
        const back = useA ? b : a;
        if ((useA ? a : b).source === url) return;
        back.opacity = 0;
        back.source = url;
        if (back.status === Image.Ready) swap();
    }
    function swap() {
        const front = useA ? b : a, old = useA ? a : b;
        front.z = 1; old.z = 0;
        fade.target = front;
        fade.restart();
        useA = !useA;
    }
    NumberAnimation {
        id: fade
        property: "opacity"
        from: 0; to: 1
        duration: root.fadeMs
        easing.type: Easing.InOutQuad
        onFinished: {
            const old = root.useA ? b : a;
            old.source = "";
            root.shown();
        }
    }

    component Pic: Image {
        anchors.fill: parent
        asynchronous: true
        cache: false
        smooth: true
        mipmap: root.fit === "fit"
        fillMode: root.fit === "fit" ? Image.PreserveAspectFit
                : root.fit === "center" ? Image.Pad
                : root.fit === "tile" ? Image.Tile : Image.PreserveAspectCrop
        // Decode at screen size (a 6K picture would otherwise take 4x the
        // memory); centre and tile keep the picture's own pixels.
        sourceSize: root.fit === "center" || root.fit === "tile" ? undefined : root.pixelSize
        opacity: 0
    }
    Pic {
        id: a
        onStatusChanged: if (status === Image.Ready && root.useA === false && source === root.url) root.swap()
    }
    Pic {
        id: b
        onStatusChanged: if (status === Image.Ready && root.useA === true && source === root.url) root.swap()
    }
}
