pragma Singleton
import QtQuick
import Quickshell

// Menu bar status symbols, drawn for the menu bar like SF Symbols: simple
// shapes on a 22 x 22 grid (the size BarButton draws them at: 22 device
// pixels), edges on whole pixels. Theme icons at that size are pictures
// (a monitor with a cable for Ethernet, a detailed USB stick) that turn
// into blobs once made one colour. Each function returns an SVG data URL
// for Icon/BarButton `icon`; BarButton recolours it (black, white).
Singleton {
    id: root

    function svg(body) {
        return "data:image/svg+xml;base64," + Qt.btoa(
            '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">' + body + '</svg>');
    }
    function n(v) { return Math.round(v * 100) / 100; }

    // An Ethernet port.
    readonly property string ethernet: svg(
        '<path fill-rule="evenodd" d="M3 5h16v11h-4v2H7v-2H3zM4.5 6.5v8h4v2h5v-2h4v-8z"/>'
        + '<rect x="7" y="8" width="1.5" height="3"/><rect x="10.25" y="8" width="1.5" height="3"/><rect x="13.5" y="8" width="1.5" height="3"/>')

    // The same with a "!" badge: limited connectivity.
    readonly property string ethernetLimited: svg(
        '<path fill-rule="evenodd" d="M3 5h16v11h-4v2H7v-2H3zM4.5 6.5v8h4v2h5v-2h4v-8z" opacity="0.55"/>'
        + '<rect x="10" y="7" width="2" height="6"/><rect x="10" y="14" width="2" height="2"/>')

    // Eject (removable drives), like macOS's.
    readonly property string eject: svg(
        '<path d="M11 4l7 8H4z"/><rect x="4" y="14" width="14" height="2.5" rx="0.5"/>')

    // Help: an "i" in a circle.
    readonly property string info: svg(
        '<circle cx="11" cy="11" r="7.75" fill="none" stroke="#000" stroke-width="1.5"/>'
        + '<rect x="10" y="6" width="2" height="2" rx="0.5"/><rect x="10" y="9" width="2" height="7" rx="0.5"/>')

    // A battery: outline, level (0..1) and, while charging, a bolt.
    function battery(level, charging) {
        const l = Math.max(0, Math.min(1, level || 0));
        const w = n(14 * l);
        let b = '<rect x="1.75" y="6.25" width="17.5" height="9.5" rx="2.5" fill="none" stroke="#000" stroke-width="1.5" opacity="0.6"/>'
            + '<rect x="20" y="9" width="1.5" height="4" rx="0.75" opacity="0.6"/>';
        if (w > 0) b += `<rect x="3.5" y="8" width="${w}" height="6" rx="1" opacity="${charging ? 0.45 : 1}"/>`;
        if (charging) b += '<path d="M11.1 5.7 6.9 11.5h3l-.9 4.8 4.4-6.1h-3z"/>';
        return svg(b);
    }

    // A zones layout: the screen's outline with its zones filled.
    // zones: [{ x, y, width, height }] in 0..1.
    function zones(list) {
        const X = 3, Y = 6, W = 16, H = 10;
        let b = `<rect x="${X - 0.75}" y="${Y - 0.75}" width="${W + 1.5}" height="${H + 1.5}" rx="2" fill="none" stroke="#000" stroke-width="1.5" opacity="0.55"/>`;
        for (const z of list || []) {
            const x0 = Math.round(X + 1 + z.x * (W - 2)), x1 = Math.round(X + 1 + (z.x + z.width) * (W - 2));
            const y0 = Math.round(Y + 1 + z.y * (H - 2)), y1 = Math.round(Y + 1 + (z.y + z.height) * (H - 2));
            // One pixel between neighbouring zones.
            const w = Math.max(1, x1 - x0 - (x1 < X + W - 1 ? 1 : 0)), h = Math.max(1, y1 - y0 - (y1 < Y + H - 1 ? 1 : 0));
            b += `<rect x="${x0}" y="${y0}" width="${w}" height="${h}" rx="0.75"/>`;
        }
        return svg(b);
    }
}
