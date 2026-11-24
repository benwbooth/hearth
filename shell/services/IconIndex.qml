pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Breeze icon files by name, for icons drawn pixel-exact (menus) and for
// light mode. Indexed once: each name's category and which design sizes
// (16, 22, 24, 32) Breeze Dark and Breeze (light) have of it.
//
// The shell's icon theme is fixed to Breeze Dark (pragma), whose monochrome
// status/action icons are light grey; in light mode widgets/Icon.qml takes
// the same icon from Breeze by file path. Menus load the file of the one
// design size that lands exactly on the device pixels (Icon.crispSize):
// Qt's own icon lookup renders at its integer device pixel ratio and
// rescales, which smears 1 px strokes at a fractional scale.
Singleton {
    id: root
    readonly property var designSizes: [16, 22, 24, 32]
    property string darkBase: ""   // ".../icons/breeze-dark/"
    property string lightBase: ""  // ".../icons/breeze/"
    property var entries: ({})     // name -> [category, darkMask, lightMask]
    property bool loaded: false

    // Bit of a design size in an entry's masks.
    function bit(size) { const i = designSizes.indexOf(size); return i < 0 ? 0 : 1 << i; }

    // Design sizes the theme (dark or light Breeze) has of `name`.
    function sizes(name, dark) {
        const e = root.entries[name];
        if (!e) return [];
        const m = dark ? e[1] : e[2];
        return designSizes.filter(s => m & bit(s));
    }

    // Absolute path of `name` at design size `size`, or "".
    function path(name, size, dark) {
        const e = root.entries[name];
        if (!e || !((dark ? e[1] : e[2]) & bit(size))) return "";
        return (dark ? root.darkBase : root.lightBase) + e[0] + "/" + size + "/" + name + ".svg";
    }

    // Light-mode file of `name` at its usual menu size (22, else 24, else 16).
    function lookup(name) {
        for (const s of [22, 24, 16, 32]) {
            const p = path(name, s, false);
            if (p) return p;
        }
        return "";
    }

    Process {
        running: true
        // name<TAB>category<TAB>darkMask<TAB>lightMask, one line per name
        // (its first category; @2x/@3x and other sizes skipped).
        command: ["sh", "-c", `
            for d in $(echo "\${XDG_DATA_DIRS:-/run/current-system/sw/share}" | tr : ' '); do
                [ -d "$d/icons/breeze-dark/actions" ] && [ -d "$d/icons/breeze/actions" ] || continue
                echo "BASE	$d/icons/breeze-dark/	$d/icons/breeze/"
                for t in breeze-dark breeze; do
                    ( cd -L "$d/icons/$t" && find -L . -mindepth 3 -maxdepth 3 -path '*@*' -prune -o \\
                        \\( -path './*/16/*' -o -path './*/22/*' -o -path './*/24/*' -o -path './*/32/*' \\) -name '*.svg' -print |
                        sed "s|^\\./|$t	|" )
                done | awk -F'\\t' '{
                    split($2, p, "/"); n = p[3]; sub(/\\.svg$/, "", n)
                    b = (p[2] == "16") ? 1 : (p[2] == "22") ? 2 : (p[2] == "24") ? 4 : 8
                    if (!(n in cat)) cat[n] = p[1]
                    if (cat[n] != p[1]) next
                    if ((n, b, $1) in seen) next
                    seen[n, b, $1] = 1
                    if ($1 == "breeze-dark") dm[n] += b; else lm[n] += b
                } END { for (n in cat) print n "\\t" cat[n] "\\t" (dm[n] + 0) "\\t" (lm[n] + 0) }'
                break
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "BASE") { root.darkBase = f[1]; root.lightBase = f[2]; continue; }
                    if (f.length === 4) m[f[0]] = [f[1], +f[2], +f[3]];
                }
                root.entries = m;
                root.loaded = true;
            }
        }
    }
}
