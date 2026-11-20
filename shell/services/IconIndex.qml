pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Light-mode icons. The shell's icon theme is fixed to Breeze Dark (pragma),
// whose monochrome status/action icons are light grey. In light mode
// widgets/Icon.qml takes the same icon from Breeze (light) by file path:
// this indexes Breeze Dark's small monochrome icons once (name -> relative
// path; Breeze has the same layout).
Singleton {
    id: root
    property var paths: ({})       // name -> absolute Breeze (light) path
    property bool loaded: false


    function lookup(name) { return root.paths[name] || ""; }

    Process {
        running: true
        command: ["sh", "-c", `
            for d in $(echo "\${XDG_DATA_DIRS:-/run/current-system/sw/share}" | tr : ' '); do
                [ -d "$d/icons/breeze-dark/status" ] && [ -d "$d/icons/breeze/status" ] || continue
                cd -L "$d/icons/breeze-dark" || continue
                find -L status actions devices places applets preferences -path '*@*' -prune -o \\( -path '*/22/*' -o -path '*/16/*' -o -path '*/24/*' \\) -name '*.svg' -print |
                  awk -F/ -v base="$d/icons/breeze/" '{n=$NF; sub(/\\.svg$/,"",n); p=($2=="22")?0:($2=="24")?1:2; if(!(n in b) || p<b[n]){b[n]=p; f[n]=$0}} END{for(n in f) print n"\\t"base f[n]}'
                break
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i > 0) m[line.substring(0, i)] = line.substring(i + 1);
                }
                root.paths = m;
                root.loaded = true;
            }
        }
    }
}
