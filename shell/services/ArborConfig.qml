pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Writes the arbor config pieces hearth generates from its Settings window
// (~/.config/hearth/arbor-*.kdl). ~/.config/arbor/config.kdl is a read-only
// file from /etc/nixos that includes these (optional=true), so arbor picks
// them up live when they change.
//
// Every write goes to a temp file first, is checked with `arbor validate`,
// and only then replaces the real file, so a bad value never breaks the
// compositor's config. Errors come back in plain language.
//
//   ArborConfig.write("arbor-keyboard.kdl", text, (ok, error) => ...)
//   ArborConfig.remove("arbor-displays.kdl", cb)
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hearth"
    function path(name) { return root.dir + "/" + name; }

    // The last error per file name ("" when the last write worked).
    property var errors: ({})
    signal written(string name)

    // Turn `arbor validate` output into something a person can read.
    function plain(out) {
        const lines = out.split("\n").map(l => l.replace(/\x1b\[[0-9;]*m/g, "").trim())
            .filter(l => l && !/\b(WARN|INFO|DEBUG|TRACE)\b/.test(l));
        const msgs = [];
        for (let l of lines) {
            // miette's boxes and arrows around the source snippet.
            l = l.replace(/^(Error|error):\s*/, "").replace(/^[│╭╰├─┬┴┼·:|>\s\d]*[─▶]+\s*/, "").replace(/^×\s*/, "").trim();
            if (!l || /^[│╭╰├─┬┴┼·|\s\d:]+$/.test(l)) continue;
            if (/^error (loading config|parsing( KDL)?)$|failed to parse included config/i.test(l) || /^\[.*\]$/.test(l)) continue;
            if (/^\d+\s*│/.test(l) || /^│/.test(l)) continue;
            if (msgs.indexOf(l) < 0) msgs.push(l);
        }
        const text = msgs.slice(0, 3).join("; ");
        return text ? "arbor can't use these settings (nothing was changed): " + text : "arbor can't use these settings (nothing was changed).";
    }
    function setError(name, e) {
        const m = Object.assign({}, root.errors);
        if (e) m[name] = e; else delete m[name];
        root.errors = m;
    }

    Component {
        id: writerComp
        Process {
            id: w
            property string name
            property var cb: null
            property string out: ""
            stdout: StdioCollector { id: so }
            stderr: StdioCollector { id: se }
            onExited: code => {
                const ok = code === 0;
                const err = ok ? "" : root.plain(se.text + "\n" + so.text);
                root.setError(w.name, err);
                if (ok) root.written(w.name);
                if (w.cb) w.cb(ok, err);
                Qt.callLater(() => w.destroy());
            }
        }
    }

    // `arbor validate` is skipped when arbor isn't installed (Hyprland).
    readonly property string script: '
set -u
dir=$(dirname "$1"); mkdir -p "$dir" || exit 3
if [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]; then exit 0; fi
tmp=$(mktemp "$1.XXXXXX.kdl") || exit 3
printf "%s\\n" "$2" > "$tmp"
if command -v arbor >/dev/null 2>&1; then
  if ! arbor validate -c "$tmp" >"$tmp.out" 2>&1; then
    cat "$tmp.out" >&2; rm -f "$tmp" "$tmp.out"; exit 1
  fi
  rm -f "$tmp.out"
fi
mv -f "$tmp" "$1"'

    // arbor's real config: devloop installs hearth's arbor/config.kdl into
    // ~/.config/hearth/arbor/ (~/.config/arbor/config.kdl only includes it);
    // the old place when that copy doesn't exist (no devloop).
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    property bool liveCopy: true
    readonly property string mainConfig: configHome + (liveCopy ? "/hearth/arbor/config.kdl" : "/arbor/config.kdl")
    FileView {
        path: root.configHome + "/hearth/arbor/config.kdl"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.liveCopy = true
        onLoadFailed: root.liveCopy = false
    }

    function write(name, text, cb) {
        const p = writerComp.createObject(root, { name: name, cb: cb || null });
        p.command = ["sh", "-c", root.script, "sh", root.path(name), text.replace(/\n+$/, "")];
        p.running = true;
    }
    function remove(name, cb) {
        const p = writerComp.createObject(root, { name: name, cb: cb || null });
        p.command = ["rm", "-f", root.path(name)];
        p.running = true;
    }

    // The login screen (greeter.qml) runs its own arbor as the `greeter`
    // user, which can't read ~: the display and keyboard pieces are copied
    // to /var/lib/hearth/greeter (README "Login screen") whenever they
    // change, so it starts with your resolution, scale and layouts. Skipped
    // when that directory is missing, in test sessions and in the greeter.
    readonly property var greeterFiles: ["arbor-displays.kdl", "arbor-keyboard.kdl"]
    readonly property string greeterDir: Quickshell.env("HEARTH_GREETER_DIR") || "/var/lib/hearth/greeter"
    readonly property bool mirrorForGreeter: Quickshell.env("HEARTH_SESSION_DRYRUN") !== "1"
                                             && Quickshell.env("HEARTH_GREETER") !== "1"
    readonly property string mirrorScript: '
d=$1; src=$2; name=$(basename "$src")
[ -d "$d" ] && [ -w "$d" ] || exit 0
if [ -f "$src" ]; then
  # Colour profiles in your home are out of the greeter\'s reach.
  grep -v "color-profile \"/home/" "$src" > "$d/.$name.tmp" && chmod 664 "$d/.$name.tmp" && mv -f "$d/.$name.tmp" "$d/$name"
elif [ "$3" = removed ]; then
  rm -f "$d/$name"
fi'
    function mirror(name, removed) {
        if (!root.mirrorForGreeter || root.greeterFiles.indexOf(name) < 0) return;
        const p = mirrorComp.createObject(root);
        p.command = ["sh", "-c", root.mirrorScript, "sh", root.greeterDir, root.path(name), removed ? "removed" : ""];
        p.running = true;
    }
    Component {
        id: mirrorComp
        Process { onExited: Qt.callLater(() => destroy()) }
    }
    onWritten: name => root.mirror(name, true)
    Component.onCompleted: { for (const n of root.greeterFiles) root.mirror(n, false); }

    // KDL string literal.
    function str(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }
    // KDL raw string (regexes).
    function raw(s) { return 'r#"' + s + '"#'; }
    function escapeRegex(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
}
