import QtQuick
import Quickshell
import Quickshell.Widgets
import ".."

// Theme icon by name (or an absolute path / image:// URL), with a fallback.
IconImage {
    id: root
    property string name: ""
    property string fallback: "application-x-executable"
    implicitSize: 22
    asynchronous: true
    source: {
        const n = root.name;
        if (!n) return Quickshell.iconPath(root.fallback, true);
        if (n.startsWith("/") || n.includes("://")) return n.startsWith("/") ? "file://" + n : n;
        const p = Quickshell.iconPath(n, root.fallback);
        // The shell's icon theme is Breeze Dark (pragma); in light mode take
        // the same icon from Breeze, which has the same layout.
        return !Theme.dark && p.includes("/breeze-dark/") ? p.replace("/breeze-dark/", "/breeze/") : p;
    }
}
