pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screenshots and screen recordings (hearth's Spectacle): captures, file
// naming, saving, copying and the recorder. The capture overlay is
// popups/Screenshot.qml, the result window (preview, annotate, copy, save,
// drag out) popups/ScreenshotEditor.qml, the menu bar's stop button
// bar/indicators/Recording.qml.
//
// Captures: grim (wlr-screencopy) for screens and regions, arbor's own
// window capture (`ScreenshotWindow` IPC: the window alone even when
// covered, with or without its title bar and shadow) for windows.
// Recording: wf-recorder (wlr-screencopy + ffmpeg's encoders).
//
// Options live under `screenshots.*` in settings.json (Settings >
// Screenshots); defaults below.
//
//   hearth-ipc call screenshot open | region | window | screen | all | activeWindow | record | stopRecording
Singleton {
    id: root

    readonly property var defaults: ({
        printAction: "overlay",         // what Print does: "overlay" | "region" | "screen" | "all" | "activeWindow"
        afterCapture: "editor",         // "editor" (result window) | "save" (save + notify, no window)
        copyOnCapture: true,            // also copy the image when it's taken (Print lands on the clipboard)
        autoSave: false,                // save every capture straight away
        closeAfterCopy: false,          // close the result window after Copy
        closeAfterSave: false,          // close the result window after Save
        folder: "~/Pictures/Screenshots",
        fileName: "Screenshot_%Y%m%d_%H%M%S",
        format: "png",                  // "png" | "jpg" | "webp"
        quality: 92,                    // jpg / webp
        pointer: false,                 // include the mouse pointer
        decorations: true,              // window captures: arbor's title bar and border
        shadow: true,                   // window captures: the shadow around it
        delay: 0,                       // seconds before the capture
        mode: "region",                 // overlay's last mode: "region" | "window" | "screen" | "all"
        rememberRegion: true,
        lastRegion: null,               // { output, x, y, w, h } output-local logical px
        recordFolder: "~/Videos/Screencasts",
        recordFormat: "mp4",            // "mp4" (H.264) | "webm" (VP9)
        recordAudio: false,             // also record sound
        recordAudioSource: "",          // PipeWire/Pulse source name ("…monitor" = what you hear); "" = default input
        annotationColor: "#ff3b30"
    })

    function opt(key) {
        void Settings.data;
        const v = Settings.get("screenshots." + key);
        return v !== undefined && v !== null ? v : root.defaults[key];
    }
    function setOpt(key, value) { Settings.set("screenshots." + key, value); }

    readonly property string home: Quickshell.env("HOME")
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hearth-shots"
    function expand(p) { return String(p || "").replace(/^~(?=\/|$)/, root.home); }

    // --- the result window ---------------------------------------------
    // Raw capture (PNG) shown in the result window; "" = closed.
    property string editorFile: ""
    property string editorTitle: ""
    property int editorSerial: 0
    function openEditor(file, title) {
        editorTitle = title || "";
        editorFile = file;
        editorSerial++;
    }
    function closeEditor() { editorFile = ""; }

    // The overlay (popups/Screenshot.qml) listens for these.
    signal overlayRequested(string mode)

    // --- file names -------------------------------------------------------
    function pad(n, w) { return String(n).padStart(w || 2, "0"); }
    // strftime-like: %Y %m %d %H %M %S %T (window title), %% ; Spectacle's
    // <yyyy> <MM> <dd> <hh> <mm> <ss> <title> work too.
    function formatName(pattern, title) {
        const d = new Date();
        const t = String(title || "").replace(/[\/\\:*?"<>|]+/g, "-").trim().slice(0, 60);
        const map = { Y: d.getFullYear(), m: pad(d.getMonth() + 1), d: pad(d.getDate()),
                      H: pad(d.getHours()), M: pad(d.getMinutes()), S: pad(d.getSeconds()), T: t, "%": "%" };
        let s = String(pattern || root.defaults.fileName).replace(/%([YmdHMST%])/g, (m, k) => map[k]);
        s = s.replace(/<yyyy>/g, map.Y).replace(/<MM>/g, map.m).replace(/<dd>/g, map.d)
             .replace(/<hh>/g, map.H).replace(/<mm>/g, map.M).replace(/<ss>/g, map.S).replace(/<title>/g, t);
        s = s.replace(/__+/g, "_").replace(/^[_ -]+|[_ -]+$/g, "");
        return s || "Screenshot";
    }
    function extFor(fmt) { return fmt === "jpg" ? "jpg" : fmt === "webp" ? "webp" : "png"; }
    function savePathFor(title, fmt) {
        return expand(opt("folder")) + "/" + formatName(opt("fileName"), title) + "." + extFor(fmt || opt("format"));
    }
    function tmpPath(ext) {
        return root.runDir + "/shot-" + Date.now() + "-" + Math.floor(Math.random() * 1e6) + "." + (ext || "png");
    }

    // --- running commands -------------------------------------------------
    Component {
        id: procComp
        Process {
            property var cb: null
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: code => {
                if (cb) cb(code, out.text, err.text);
                destroy();
            }
        }
    }
    // cb(exitCode, stdout, stderr)
    function run(cmd, cb) {
        const p = procComp.createObject(root, { command: cmd, cb: cb || null });
        p.running = true;
    }
    function sh(script, args, cb) { run(["sh", "-c", script, "sh"].concat(args || []), cb); }

    Component.onCompleted: run(["mkdir", "-p", root.runDir])

    // Waits until `path` exists and isn't empty (arbor writes it atomically).
    function waitFile(path, cb) {
        sh('for i in $(seq 100); do [ -s "$1" ] && exit 0; sleep 0.05; done; exit 1', [path],
           code => cb(code === 0));
    }

    function notify(summary, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Screenshot", "-i", icon || "camera-photo", summary, body || ""]);
    }

    // --- captures ---------------------------------------------------------
    // grim's geometry is in global logical coordinates.
    function geom(r) { return Math.round(r.x) + "," + Math.round(r.y) + " " + Math.round(r.w) + "x" + Math.round(r.h); }

    // Whole outputs / all of them / a region, live (the overlay is hidden).
    function grabScreen(output, pointer, title) {
        const f = tmpPath("png");
        const cmd = ["grim"].concat(pointer ? ["-c"] : []).concat(output ? ["-o", output] : []).concat([f]);
        run(cmd, (code, o, e) => code === 0 ? deliver(f, title || (output ? "Screen" : "All screens"))
                                            : failed("grim: " + e.trim()));
    }
    function grabRegion(r, pointer) {
        const f = tmpPath("png");
        run(["grim"].concat(pointer ? ["-c"] : []).concat(["-g", geom(r), f]),
            (code, o, e) => code === 0 ? deliver(f, "Region") : failed("grim: " + e.trim()));
    }
    // A window by arbor id ("" = the focused one), drawn by arbor itself.
    function grabWindow(id, opts) {
        opts = opts || {};
        if (!Compositor.isArbor) { failed("Window captures need arbor"); return; }
        const f = tmpPath("png");
        const win = id ? Compositor.windows.find(w => w.id === String(id)) : Compositor.windows.find(w => w.focused);
        const args = {
            id: id ? Number(id) : null,
            write_to_disk: true,
            show_pointer: opts.pointer !== undefined ? !!opts.pointer : !!opt("pointer"),
            path: f,
            decorations: opts.decorations !== undefined ? !!opts.decorations : !!opt("decorations"),
            shadow: opts.shadow !== undefined ? !!opts.shadow : !!opt("shadow"),
            clipboard: false
        };
        Compositor.arborRequest({ Action: { ScreenshotWindow: args } }, reply => {
            if (reply && reply.Err !== undefined) { failed("arbor: " + reply.Err); return; }
            waitFile(f, ok => ok ? deliver(f, win ? win.title : "Window") : failed("arbor didn't write the window capture"));
        });
    }

    function failed(msg) {
        console.warn("screenshot:", msg);
        notify("Screenshot failed", msg, "dialog-error");
    }

    property string lastCapture: ""     // newest raw capture
    property string lastSaved: ""       // newest saved file
    signal captured(string file)

    // A capture is ready: copy/save it as configured, then open the result
    // window (or just say where it went).
    function deliver(file, title) {
        lastCapture = file;
        captured(file);
        const editor = opt("afterCapture") !== "save";
        if (opt("copyOnCapture")) copyImage(file);
        if (opt("autoSave") || !editor) {
            saveFile(file, title, "", path => {
                if (!editor) notify("Screenshot saved", path + (opt("copyOnCapture") ? "\nCopied to the clipboard" : ""), path);
            });
        }
        if (editor) openEditor(file, title);
    }

    // Saves a PNG `src` as `dest` ("" = auto name in the folder) in the
    // chosen format; cb(path) on success.
    function saveFile(src, title, dest, cb, fmt) {
        fmt = fmt || (dest ? (/\.jpe?g$/i.test(dest) ? "jpg" : /\.webp$/i.test(dest) ? "webp" : "png") : opt("format"));
        const out = dest || savePathFor(title, fmt);
        const q = Math.max(1, Math.min(100, Number(opt("quality")) || 92));
        // Never overwrite: name_1, name_2 ... when the name is taken (auto names only).
        const script = `
src=$1; out=$2; fmt=$3; q=$4; auto=$5
mkdir -p "$(dirname "$out")" || exit 1
if [ "$auto" = 1 ] && [ -e "$out" ]; then
  base=\${out%.*}; ext=\${out##*.}; i=1
  while [ -e "\${base}_$i.$ext" ]; do i=$((i+1)); done
  out="\${base}_$i.$ext"
fi
case $fmt in
  png) cp -f "$src" "$out" ;;
  jpg) vips copy "$src" "$out[Q=$q,strip]" 2>/dev/null || vips copy "$src" "$out[Q=$q]" ;;
  webp) vips copy "$src" "$out[Q=$q]" ;;
esac || exit 1
printf %s "$out"`;
        sh(script, [src, out, fmt, String(q), dest ? "0" : "1"], (code, o, e) => {
            if (code !== 0) { failed("couldn't save " + out + ": " + e.trim()); return; }
            lastSaved = o;
            if (cb) cb(o);
        });
    }

    function copyImage(file) {
        sh('wl-copy --type image/png < "$1"', [file]);
    }
    function copyText(text) { run(["wl-copy", "--", text]); }
    // Opens the file manager with `file` selected (or its folder).
    function showInFolder(file) {
        const uri = "file://" + encodeURI(file);
        sh(`busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1 ShowItems ass 1 "$1" "" >/dev/null 2>&1 || xdg-open "$2"`,
           [uri, file.replace(/\/[^\/]*$/, "") || "/"]);
        // Asked over D-Bus, grove gets no activation token, so arbor leaves
        // its window behind the editor: bring it forward once it shows the
        // folder (its newest window, the one titled after the folder first).
        raiseFiles.folder = (file.replace(/\/[^\/]*$/, "") || "/").replace(/^.*\//, "");
        raiseFiles.before = Compositor.windows.filter(w => w.appId === "grove").map(w => w.id);
        raiseFiles.tries = 0;
        raiseFiles.restart();
    }
    Timer {
        id: raiseFiles
        property string folder: ""
        property var before: []
        property int tries: 0
        interval: 150
        repeat: true
        onTriggered: {
            const g = Compositor.windows.filter(w => w.appId === "grove");
            const fresh = g.filter(w => before.indexOf(w.id) < 0);
            const titled = g.filter(w => folder && String(w.title || "").indexOf(folder) >= 0);
            const pick = fresh.length ? fresh[fresh.length - 1] : titled.length ? titled[0] : null;
            if (pick && !pick.focused) { Compositor.focusWindow(pick.id); stop(); return; }
            if (pick || ++tries >= 20) stop();
        }
    }

    // --- delay ------------------------------------------------------------
    property int countdown: 0           // seconds left, shown by the overlay's OSD
    property var pendingShot: null
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            // The countdown bubble unmaps first, then the shot.
            if (root.countdown <= 0) { stop(); hideWait.restart(); }
        }
    }
    // Runs `fn` after `secs` seconds (0: after the overlay has gone).
    function later(secs, fn) {
        if (secs > 0) { countdown = secs; pendingShot = fn; tick.restart(); }
        else { pendingShot = fn; hideWait.restart(); }
    }
    function cancelDelay() { tick.stop(); countdown = 0; pendingShot = null; }
    Timer {
        id: hideWait
        interval: 220   // the overlay unmaps first
        onTriggered: { const f = root.pendingShot; root.pendingShot = null; if (f) f(); }
    }

    // --- instant captures (keybinds, IPC) --------------------------------
    function captureScreen() {
        const s = Compositor.focusedOutput;
        later(Number(opt("delay")) || 0, () => grabScreen(s, opt("pointer")));
    }
    function captureAll() { later(Number(opt("delay")) || 0, () => grabScreen("", opt("pointer"))); }
    function captureActiveWindow() { later(Number(opt("delay")) || 0, () => grabWindow("", {})); }

    // --- recording --------------------------------------------------------
    property bool recording: false
    property string recordFile: ""
    property string recordWhat: ""
    property real recordStarted: 0
    property int recordSeconds: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.recordSeconds = Math.round((Date.now() - root.recordStarted) / 1000)
    }
    function recordPathFor(title) {
        const ext = opt("recordFormat") === "webm" ? "webm" : "mp4";
        return expand(opt("recordFolder")) + "/" + formatName(String(opt("fileName")).replace(/^Screenshot/, "Screencast"), title) + "." + ext;
    }
    // target: { output } | { region: {x,y,w,h} global logical } ; title for the file name.
    function startRecording(target, title) {
        if (recording) return;
        const file = recordPathFor(title);
        const webm = /\.webm$/.test(file);
        // Constant 30 fps: wf-recorder only sends frames on damage, so a still
        // screen would make a one-frame video.
        const args = ["-y", "-r", "30", "-f", file];
        if (target.region) args.push("-g", geom(target.region));
        else if (target.output) args.push("-o", target.output);
        if (webm) args.push("-c", "libvpx-vp9", "-p", "deadline=realtime", "-p", "cpu-used=8", "-p", "row-mt=1", "-p", "b=0", "-p", "crf=32");
        else args.push("-c", "libx264", "-p", "preset=veryfast", "-p", "crf=23", "-x", "yuv420p");
        if (opt("recordAudio")) {
            const src = String(opt("recordAudioSource") || "");
            args.push(src ? "--audio=" + src : "--audio");
            if (webm) args.push("-C", "libopus");
        }
        recorder.file = file;
        recorder.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && shift && exec wf-recorder "$@"', "sh", file].concat(args);
        recorder.running = true;
        recordFile = file;
        recordWhat = title || "";
        recordStarted = Date.now();
        recordSeconds = 0;
        recording = true;
    }
    function stopRecording() {
        if (recorder.running) recorder.signal(2);   // SIGINT: wf-recorder finishes the file
    }
    Process {
        id: recorder
        property string file: ""
        stderr: StdioCollector { id: recErr }
        onExited: code => {
            root.recording = false;
            const f = recorder.file;
            root.sh('[ -s "$1" ]', [f], c => {
                if (c === 0) {
                    root.lastSaved = f;
                    root.notify("Recording saved", f, "media-record");
                } else {
                    root.failed("recording failed: " + recErr.text.trim().split("\n").slice(-3).join(" "));
                }
            });
        }
    }
    function formatDuration(s) {
        const m = Math.floor(s / 60), h = Math.floor(m / 60);
        return (h > 0 ? h + ":" + pad(m % 60) : m) + ":" + pad(s % 60);
    }

    IpcHandler {
        target: "screenshot"
        function open(): void { root.overlayRequested(""); }
        function region(): void { root.overlayRequested("region"); }
        function window(): void { root.overlayRequested("window"); }
        function screen(): void { root.captureScreen(); }
        function all(): void { root.captureAll(); }
        function activeWindow(): void { root.captureActiveWindow(); }
        function record(): void { if (root.recording) root.stopRecording(); else root.overlayRequested("record"); }
        function stopRecording(): void { root.stopRecording(); }
        // What Print does (Settings > Screenshots).
        function printKey(): void {
            const a = root.opt("printAction");
            if (a === "screen") root.captureScreen();
            else if (a === "all") root.captureAll();
            else if (a === "activeWindow") root.captureActiveWindow();
            else root.overlayRequested(a === "region" ? "region" : "");
        }
        function lastFile(): string { return root.lastSaved || root.lastCapture; }
    }
}
