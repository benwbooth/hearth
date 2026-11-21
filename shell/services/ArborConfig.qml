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

    // KDL string literal.
    function str(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }
    // KDL raw string (regexes).
    function raw(s) { return 'r#"' + s + '"#'; }
    function escapeRegex(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
}
