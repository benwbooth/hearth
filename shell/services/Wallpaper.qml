pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import ".."

// The wallpaper engine. hearth draws the wallpaper itself
// (desktop/Background.qml: one background-layer surface per screen) with
// cross-fades, so no swaybg/hyprpaper is needed. What each screen shows is
// settings.json `wallpaper.displays` (an output name or "*" for all):
//
//   potd     a picture source (Bing, NASA APOD, Wikimedia Commons, NASA
//            Earth Observatory, NOAA live Earth, Windows Spotlight, Google
//            Earth View, Simon Stålenhag, David Revoy, Wallhaven, Reddit,
//            Unsplash/Pexels/Flickr with your key), refreshed on a timer,
//            with a history to step back and forth through
//   image    one picture         folder   a slideshow
//   dynamic  time-of-day or light/dark sets (GNOME XML, macOS .heic,
//            hearth's dynamic.json), cross-faded as the day goes
//   video    mp4/webm/mkv (QtMultimedia, hardware decoding)
//   shader   a GLSL shader (built-in or Shadertoy-style)
//   we       a Wallpaper Engine project (linux-wallpaperengine)
//
// All the slow work (downloads, crops, scans, conversions) runs in
// helpers/hearth-wallpaper; nothing here blocks the UI thread. Animated
// wallpapers pause on a screen covered by windows, everywhere while an app
// is full screen, when idle/locked, and on battery (Settings > Wallpaper).
//
// For the lock and login screens: ~/.cache/hearth/wallpaper is the current
// still (a stable link), ~/.cache/hearth/wallpaper.json describes it (type,
// path, video, shader, attribution), and a copy goes to
// /var/lib/hearth/wallpaper/ when that directory exists and is writable.
//
//   hearth-ipc call wallpaper refresh | next | previous | info | usePotd
//   hearth-ipc call wallpaper setImage PATH
//   hearth-ipc call wallpaper set '{"type":"shader","path":"builtin:aurora"}' [OUTPUT]
//   hearth-ipc call wallpaper stillOnly true|false
Singleton {
    id: root

    // ---------------------------------------------------------------- catalog

    // group: "daily" (Pictures of the day) or "web" (Photos from the web).
    // kind: "daily" (one per day, browse back by date), "random" (a new
    // pick each time), "live" (always the latest).
    readonly property var sources: [
        { id: "bing", name: "Bing", group: "daily", kind: "daily", interval: 60,
          note: "Microsoft Bing's photo of the day, in 4K." },
        { id: "apod", name: "NASA Astronomy", group: "daily", kind: "daily", interval: 60,
          note: "NASA's Astronomy Picture of the Day (days with a video are skipped)." },
        { id: "wikimedia", name: "Wikimedia Commons", group: "daily", kind: "daily", interval: 60,
          note: "The Wikimedia Commons picture of the day." },
        { id: "earthobs", name: "Earth Observatory", group: "daily", kind: "daily", interval: 120,
          note: "NASA Earth Observatory's image of the day: Earth from satellites." },
        { id: "noaa", name: "Live Earth (NOAA)", group: "daily", kind: "live", interval: 30, fit: "fit",
          note: "The whole Earth right now, from NOAA's GOES weather satellites (every 30 minutes)." },
        { id: "spotlight", name: "Windows Spotlight", group: "daily", kind: "random", interval: 1440,
          note: "The landscapes from the Windows lock screen." },
        { id: "earthview", name: "Google Earth View", group: "daily", kind: "random", interval: 1440,
          note: "Striking satellite views of landscapes from Google Earth (1800 px wide)." },
        { id: "stalenhag", name: "Simon Stålenhag", group: "daily", kind: "random", interval: 1440,
          note: "Paintings by Simon Stålenhag (Tales from the Loop)." },
        { id: "davidrevoy", name: "David Revoy", group: "daily", kind: "random", interval: 1440,
          note: "Pepper&Carrot art by David Revoy (CC BY)." },
        { id: "wallhaven", name: "Wallhaven", group: "web", kind: "random", interval: 1440,
          note: "Search Wallhaven's wallpapers by words and category; safe for work only unless you add a key." },
        { id: "reddit", name: "Reddit", group: "web", kind: "random", interval: 1440,
          note: "Top pictures of the day or week from picture subreddits such as r/EarthPorn." },
        { id: "unsplash", name: "Unsplash", group: "web", kind: "random", interval: 1440, key: true,
          note: "Photos from Unsplash. Needs a free access key from unsplash.com/developers." },
        { id: "pexels", name: "Pexels", group: "web", kind: "random", interval: 1440, key: true,
          note: "Photos from Pexels. Needs a free API key from pexels.com/api." },
        { id: "flickr", name: "Flickr Explore", group: "web", kind: "daily", interval: 1440, key: true,
          note: "Flickr's most interesting photos of the day. Needs a free API key from flickr.com/services/apps/create." }
    ]
    function sourceInfo(id) { return sources.find(s => s.id === id) || null; }

    readonly property var shaders: [
        { path: "builtin:aurora", name: "Aurora", note: "Northern lights over the hills (a dawn sky in light mode)." },
        { path: "builtin:liquid", name: "Liquid", note: "Soft colour fields drifting together, like macOS's gradients." },
        { path: "builtin:dunes", name: "Dunes", note: "Layered hills slowly drifting under a turning sky." },
        { path: "builtin:nebula", name: "Nebula", note: "Stars drifting through soft clouds of gas." }
    ]

    // ---------------------------------------------------------------- paths

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/hearth"
    readonly property string cacheDir: cacheRoot + "/wallpapers"
    readonly property string stableLink: cacheRoot + "/wallpaper"
    readonly property string exportJson: cacheRoot + "/wallpaper.json"
    readonly property string systemDir: Quickshell.env("HEARTH_WALLPAPER_SYSTEM_DIR") || "/var/lib/hearth/wallpaper"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/hearth"

    readonly property var cfg: Settings.wallpaper
    readonly property bool stillOnly: !!cfg.stillOnly

    // ---------------------------------------------------------------- state

    // { current: { source: id }, lastFetch: { source: ms }, folder: { path: { index, at } },
    //   shaderTime }
    property var st: ({ current: {}, lastFetch: {}, folder: {} })
    property bool stateLoaded: false
    property var histories: ({})      // source -> [items]
    property var errors: ({})         // source -> message
    property var busy: ({})           // source -> true while fetching
    property var crops: ({})          // key -> path | "pending" | "failed"
    property var cropFailedAt: ({})   // key -> ms (failed crops are retried after a minute)
    // Something to try again shortly (a screen without its size yet, a
    // failed crop waiting for its retry).
    property bool retryPending: false
    Timer {
        interval: 5000; repeat: true; running: root.retryPending
        onTriggered: { root.retryPending = false; root.rebuildSoon(); }
    }
    property var posters: ({})        // video/shader/we path -> still
    property var folders: ({})        // path+opts -> [files]
    property var dyn: ({})            // path#index -> schedule | { error }
    property var shaderQsb: ({})      // user shader path -> { file } | { error }
    property var keys: ({})           // unsplash/pexels/flickr/wallhaven -> bool
    property string exportStatus: ""  // "ok" | "missing" | "not-writable" | "off"
    property int tick: 0              // bumps every 30 s for dynamic wallpapers

    property var views: ({})          // screen name -> view (see resolve())
    signal infoRequested()

    function setState(fn) {
        const s = JSON.parse(JSON.stringify(root.st));
        fn(s);
        root.st = s;
        stateSave.restart();
        rebuildSoon();
    }
    function setMap(name, key, value) {
        const m = Object.assign({}, root[name]);
        if (value === undefined) delete m[key]; else m[key] = value;
        root[name] = m;
    }

    // ---------------------------------------------------------------- jobs

    // Run the helper; cb(result) with the parsed JSON ({ error } on failure).
    Component {
        id: jobComp
        Process {
            id: p
            property var cb: null
            property string input: ""
            stdinEnabled: input !== ""
            stdout: StdioCollector { id: so }
            stderr: StdioCollector { id: se }
            onStarted: if (input !== "") { write(input); stdinEnabled = false; }
            onExited: code => {
                let r = null;
                const lines = so.text.trim().split("\n");
                try { r = JSON.parse(lines[lines.length - 1]); } catch (e) {
                    r = { error: (se.text.trim() || so.text.trim() || "hearth-wallpaper failed").slice(-300) };
                }
                if (r === null || typeof r !== "object") r = { error: "bad reply" };
                if (p.cb) p.cb(r);
                Qt.callLater(() => p.destroy());
            }
        }
    }
    function job(args, cb, input) {
        const p = jobComp.createObject(root, { command: ["hearth-wallpaper"].concat(args), cb: cb || null, input: input || "" });
        p.running = true;
    }

    // ---------------------------------------------------------------- what each screen shows

    function specFor(name) {
        const d = root.cfg.displays || {};
        return d[name] || d["*"] || { type: "potd", source: "bing" };
    }
    // Same spec on every screen?
    readonly property bool perDisplay: {
        const d = root.cfg.displays || {};
        return Object.keys(d).some(k => k !== "*");
    }
    function setSpec(spec, output) {
        const d = Object.assign({}, root.cfg.displays || {});
        if (!output || output === "*") {
            for (const k of Object.keys(d)) delete d[k];
            d["*"] = spec;
        } else {
            if (!d["*"]) d["*"] = specFor(output);
            d[output] = spec;
        }
        Settings.set("wallpaper.displays", d);
    }
    function specKey(s) { return s ? JSON.stringify(s) : ""; }
    function sameSpec(a, b) {
        if (!a || !b || a.type !== b.type) return false;
        if (a.type === "potd") return a.source === b.source;
        return a.path === b.path && (a.index || 0) === (b.index || 0);
    }

    function screenPx(s) {
        const dpr = s.devicePixelRatio || 1;
        return [Math.round(s.width * dpr), Math.round(s.height * dpr)];
    }
    // The largest screen in pixels: the size picture searches ask for.
    readonly property var maxPx: {
        let w = 0, h = 0;
        for (const s of Quickshell.screens) {
            const p = screenPx(s);
            if (p[0] * p[1] > w * h) { w = p[0]; h = p[1]; }
        }
        return [w || 3840, h || 2160];
    }

    function currentItem(source) {
        const h = root.histories[source] || [];
        if (!h.length) return null;
        const id = (root.st.current || {})[source];
        return h.find(x => x.id === id) || h[0];
    }
    function historyIndex(source) {
        const h = root.histories[source] || [];
        const it = currentItem(source);
        return it ? h.indexOf(it) : -1;
    }

    // A picture sized for screen s: fill + smart crop makes an exact-size
    // crop around the interesting part (once, cached); until it's ready the
    // original shows (Qt crops it centred).
    function fitted(file, s, fit, w, h) {
        if (!file) return "";
        if (fit !== "fill" || !root.cfg.smartCrop) return file;
        const px = screenPx(s);
        // A screen whose size isn't known yet (at startup): no crop request
        // for a 0-pixel picture (it failed and stuck, so the screen showed a
        // plain centre crop that cut the sky off); this runs again once the
        // screen has its size.
        if (!(px[0] > 0 && px[1] > 0)) { root.retryPending = true; return file; }
        if (w && h && Math.abs(w / h - px[0] / px[1]) < 0.02 && w <= px[0] * 1.3) return file;
        const key = Qt.md5(file) + "_" + px[0] + "x" + px[1];
        const c = root.crops[key];
        if (c && c !== "pending" && c !== "failed") return c;
        // A failed crop is tried again after a while (a busy disk, a
        // half-downloaded picture), not never.
        if (c === "failed" && Date.now() - (root.cropFailedAt[key] || 0) > 60000) {
            delete root.crops[key];
            requestCrop(key, file, px[0], px[1]);
        } else if (!c) requestCrop(key, file, px[0], px[1]);
        else if (c === "failed") root.retryPending = true;
        return file;
    }
    property var cropQueue: []
    property bool cropping: false
    function requestCrop(key, file, w, h) {
        root.crops[key] = "pending";   // no notify: avoids a rebuild loop
        root.cropQueue.push({ key: key, file: file, w: w, h: h });
        nextCrop();
    }
    function nextCrop() {
        if (root.cropping || !root.cropQueue.length) return;
        const c = root.cropQueue.shift();
        root.cropping = true;
        job(["crop", c.file, String(c.w), String(c.h), `${root.cacheDir}/crops/${c.key}.jpg`], r => {
            root.cropping = false;
            if (r.error) root.cropFailedAt[c.key] = Date.now();
            setMap("crops", c.key, r.error ? "failed" : r.file);
            if (r.error) console.warn("hearth wallpaper: crop:", r.error);
            rebuildSoon();
            nextCrop();
        });
    }

    function shaderUrl(path) {
        if (path.startsWith("builtin:"))
            return Qt.resolvedUrl("../shaders/wallpaper/" + path.substring(8) + ".frag.qsb");
        const q = root.shaderQsb[path];
        if (q && q.file) return "file://" + q.file;
        if (!q) {
            setMap("shaderQsb", path, { pending: true });
            job(["shader", path, `${root.cacheDir}/shaders/${Qt.md5(path)}.qsb`], r => {
                setMap("shaderQsb", path, r);
                if (r.error) console.warn("hearth wallpaper: shader:", r.error);
                rebuildSoon();
            });
        }
        return "";
    }

    function poster(path, kind) {
        const p = root.posters[path];
        if (p !== undefined) return p;
        root.posters[path] = "";
        if (kind === "video") {
            job(["poster", path, `${root.cacheDir}/posters/${Qt.md5(path)}.jpg`], r => {
                if (!r.error) { setMap("posters", path, r.file); rebuildSoon(); }
            });
        }
        return "";
    }
    // Background.qml grabs a rendered shader frame for the lock screen and
    // the menu bar's brightness sampling.
    function setPoster(path, file) { setMap("posters", path, file); rebuildSoon(); }
    function shaderPosterPath(path) { return `${root.cacheDir}/shader-${Qt.md5(path)}.png`; }

    function folderKey(spec) { return spec.path + (spec.recursive ? "#r" : ""); }
    function folderFiles(spec) {
        const k = folderKey(spec);
        const f = root.folders[k];
        if (f !== undefined) return f;
        root.folders[k] = [];
        job(["scan-folder", spec.path].concat(spec.recursive ? ["--recursive"] : []), r => {
            setMap("folders", k, r.files || []);
            rebuildSoon();
        });
        return [];
    }
    function folderFile(spec) {
        const files = folderFiles(spec);
        if (!files.length) return "";
        const s = (root.st.folder || {})[folderKey(spec)] || { index: 0 };
        const order = spec.shuffle ? shuffled(files.length, folderKey(spec)) : null;
        const i = ((s.index || 0) % files.length + files.length) % files.length;
        return files[order ? order[i] : i];
    }
    // A stable shuffled order per folder (a new order each pass through).
    function shuffled(n, seedStr) {
        let seed = 0;
        const pass = Math.floor((((root.st.folder || {})[seedStr] || {}).index || 0) / Math.max(n, 1));
        const str = seedStr + pass;
        for (let i = 0; i < str.length; i++) seed = (seed * 31 + str.charCodeAt(i)) >>> 0;
        const a = Array.from({ length: n }, (_, i) => i);
        for (let i = n - 1; i > 0; i--) {
            seed = (seed * 1103515245 + 12345) >>> 0;
            const j = seed % (i + 1);
            const t = a[i]; a[i] = a[j]; a[j] = t;
        }
        return a;
    }
    function stepFolder(spec, d) {
        const k = folderKey(spec);
        setState(s => {
            s.folder = s.folder || {};
            const f = s.folder[k] || { index: 0 };
            s.folder[k] = { index: (f.index || 0) + d, at: Date.now() };
        });
    }

    function dynKey(spec) { return spec.path + "#" + (spec.index || 0); }
    function dynamicSchedule(spec) {
        const k = dynKey(spec);
        const d = root.dyn[k];
        // Solar schedules are for one day: redo them after midnight.
        const today = Qt.formatDate(new Date(), "yyyyMMdd");
        if (d !== undefined && !(d.solarDay && d.solarDay !== today)) return d;
        root.dyn[k] = d || { pending: true };
        const loc = Weather.location;
        const args = ["dynamic", spec.path, "--dir", root.cacheDir, "--index", String(spec.index || 0)];
        if (loc) args.push("--lat", String(loc.latitude), "--lon", String(loc.longitude));
        job(args, r => {
            setMap("dyn", k, r);
            if (r.error) console.warn("hearth wallpaper: dynamic:", r.error);
            rebuildSoon();
        });
        return root.dyn[k];
    }
    // { file, fileA, blend } for now.
    function dynamicFrame(d) {
        if (!d || d.error || d.pending) return null;
        if (d.kind === "appearance" || !d.frames || !d.frames.length)
            return { file: Theme.dark ? (d.dark || d.light) : (d.light || d.dark), fileA: "", blend: 1 };
        void root.tick;
        const now = new Date();
        const t = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
        const fr = d.frames;
        let i = fr.length - 1;
        for (let k = 0; k < fr.length; k++) if (fr[k].start <= t) i = k;
        // Before the first frame of the day: the last one (from yesterday).
        if (fr[0].start > t) i = fr.length - 1;
        const cur = fr[i], prev = fr[(i - 1 + fr.length) % fr.length];
        let since = t - cur.start;
        if (since < 0) since += 86400;
        const blend = cur.fade > 0 ? Math.min(1, since / cur.fade) : 1;
        return { file: cur.file, fileA: blend < 1 ? prev.file : "", blend: blend };
    }

    // view: { kind: "still"|"video"|"shader"|"we", file (the still: shown
    // for "still", underneath/poster otherwise), fileA + blend (dynamic
    // cross-fade), video, shader (qsb url), shaderPath, wePath, fit, spec,
    // meta { title, copyright, link, source }, error }
    function resolve(spec, s) {
        const fit = root.cfg.fit || "fill";
        const v = { kind: "still", file: "", fileA: "", blend: 1, fit: fit, spec: spec, meta: null, error: "" };
        switch (spec.type) {
        case "potd": {
            const it = currentItem(spec.source);
            const info = sourceInfo(spec.source) || {};
            v.error = root.errors[spec.source] || "";
            if (it) {
                v.fit = it.fit || info.fit || fit;
                v.file = fitted(it.file, s, v.fit, it.width, it.height);
                v.meta = { title: it.title, copyright: it.copyright, link: it.link, source: info.name || spec.source, item: it };
            }
            break;
        }
        case "image":
            v.file = fitted(spec.path, s, fit, 0, 0);
            v.meta = { title: spec.path.split("/").pop(), copyright: "", link: "", source: "Picture" };
            break;
        case "folder": {
            const f = folderFile(spec);
            v.file = fitted(f, s, fit, 0, 0);
            v.meta = { title: f.split("/").pop(), copyright: "", link: "", source: spec.path.split("/").pop() || spec.path };
            break;
        }
        case "dynamic": {
            const d = dynamicSchedule(spec);
            const fr = dynamicFrame(d);
            if (d && d.error) v.error = d.error;
            if (fr) {
                v.file = fitted(fr.file, s, fit, 0, 0);
                v.fileA = fr.fileA ? fitted(fr.fileA, s, fit, 0, 0) : "";
                v.blend = fr.blend;
            }
            v.meta = { title: (d && d.name) || spec.path.split("/").pop(), copyright: "", link: "", source: "Dynamic" };
            break;
        }
        case "video":
            v.kind = root.stillOnly ? "still" : "video";
            v.video = spec.path;
            v.file = fitted(poster(spec.path, "video"), s, fit, 0, 0);
            v.meta = { title: spec.path.split("/").pop(), copyright: "", link: "", source: "Video" };
            break;
        case "shader": {
            const info = root.shaders.find(x => x.path === spec.path);
            v.kind = root.stillOnly ? "still" : "shader";
            v.shaderPath = spec.path;
            v.shader = shaderUrl(spec.path);
            const q = root.shaderQsb[spec.path];
            if (q && q.error) v.error = q.error;
            v.file = root.posters[spec.path] || "";
            v.fit = "fill";
            v.meta = { title: info ? info.name : spec.path.split("/").pop(), copyright: "", link: "", source: "Shader" };
            break;
        }
        case "we": {
            const p = root.weProjects.find(x => x.path === spec.path);
            v.kind = root.stillOnly ? "still" : "we";
            v.wePath = spec.path;
            v.file = fitted(p && p.preview ? p.preview : (spec.preview || ""), s, "fill", 0, 0);
            v.meta = { title: p ? p.title : (spec.title || spec.path.split("/").pop()), copyright: "", link: "",
                       source: "Wallpaper Engine" };
            break;
        }
        }
        return v;
    }

    function rebuildSoon() { rebuildTimer.restart(); }
    Timer { id: rebuildTimer; interval: 10; onTriggered: root.rebuild() }
    function rebuild() {
        const v = {};
        for (const s of Quickshell.screens) v[s.name] = resolve(specFor(s.name), s);
        root.views = v;
    }
    onCfgChanged: { rebuildSoon(); fetchDue(); }
    Connections { target: Theme; function onDarkChanged() { root.rebuildSoon(); } }
    Connections { target: Quickshell; function onScreensChanged() { root.rebuildSoon(); } }
    onTickChanged: if (usesType("dynamic")) rebuildSoon()

    function usedSpecs() {
        const out = [];
        for (const s of Quickshell.screens) {
            const sp = specFor(s.name);
            if (!out.some(o => sameSpec(o, sp))) out.push(sp);
        }
        return out;
    }
    function usesType(t) { return usedSpecs().some(s => s.type === t); }

    // The first screen's view: what `file`, `title`... describe.
    readonly property var primaryView: {
        const s = Quickshell.screens;
        return s.length ? (root.views[s[0].name] || null) : null;
    }
    readonly property string file: primaryView ? primaryView.file : ""
    readonly property string title: primaryView && primaryView.meta ? primaryView.meta.title || "" : ""
    readonly property string copyright: primaryView && primaryView.meta ? primaryView.meta.copyright || "" : ""
    readonly property string link: primaryView && primaryView.meta ? primaryView.meta.link || "" : ""
    readonly property string sourceName: primaryView && primaryView.meta ? primaryView.meta.source || "" : ""
    readonly property string error: primaryView ? primaryView.error || "" : ""
    readonly property var primarySpec: primaryView ? primaryView.spec : null
    // Legacy names (WallpaperInfo, old scripts).
    readonly property string mode: primarySpec && primarySpec.type === "potd" ? "potd" : "image"
    readonly property bool loading: Object.keys(root.busy).length > 0

    // ---------------------------------------------------------------- fetching

    function srcOpts(id) {
        return Object.assign({}, (root.cfg.sources || {})[id] || {});
    }
    function intervalMin(id) {
        const o = srcOpts(id);
        const info = sourceInfo(id) || {};
        return Number(o.interval) || info.interval || 1440;
    }
    // offset: days back (daily sources). select: show the fetched picture.
    function fetch(source, offset, select) {
        if (root.busy[source]) return;
        setMap("busy", source, true);
        const prevNewest = ((root.histories[source] || [])[0] || {}).id;
        const args = ["fetch", source, "--dir", root.cacheDir, "--min", root.maxPx[0] + "x" + root.maxPx[1],
                      "--opts", JSON.stringify(srcOpts(source))];
        if (offset) args.push("--offset", String(offset));
        job(args, r => {
            setMap("busy", source, undefined);
            if (r.error) {
                setMap("errors", source, r.error);
                console.warn("hearth wallpaper:", source + ":", r.error);
                setState(s => { s.lastFetch = s.lastFetch || {}; s.lastFetch[source] = Date.now() - (intervalMin(source) - 5) * 60000; });
                return;
            }
            setMap("errors", source, undefined);
            setMap("histories", source, r.history || []);
            const info = sourceInfo(source) || {};
            setState(s => {
                s.lastFetch = s.lastFetch || {};
                s.lastFetch[source] = Date.now();
                s.current = s.current || {};
                // A new picture (or one asked for) becomes the current one.
                if (select || info.kind !== "daily" || (r.item && r.item.id !== prevNewest && offset === 0))
                    s.current[source] = r.item.id;
            });
        });
    }
    function fetchDue() {
        if (!root.stateLoaded || !root.historiesLoaded) return;
        const now = Date.now();
        for (const sp of usedSpecs()) {
            if (sp.type !== "potd") continue;
            const last = (root.st.lastFetch || {})[sp.source] || 0;
            const h = root.histories[sp.source] || [];
            if (!h.length || now - last >= intervalMin(sp.source) * 60000) fetch(sp.source, 0, false);
        }
        // Folder slideshows.
        for (const sp of usedSpecs()) {
            if (sp.type !== "folder") continue;
            const f = (root.st.folder || {})[folderKey(sp)] || {};
            const iv = (Number(sp.interval) || 30) * 60000;
            if (!f.at) setState(s => { s.folder = s.folder || {}; s.folder[folderKey(sp)] = { index: f.index || 0, at: now }; });
            else if (now - f.at >= iv) stepFolder(sp, 1);
        }
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: { root.tick++; root.fetchDue(); }
    }

    // History browsing for a picture source: d = -1 older, +1 newer.
    function step(source, d) {
        const info = sourceInfo(source) || {};
        const h = root.histories[source] || [];
        const i = historyIndex(source);
        if (d < 0) {
            if (i >= 0 && i < h.length - 1) selectItem(source, h[i + 1].id);
            else if (info.kind === "daily" && h.length) {
                // Older than anything kept: fetch the day before the oldest.
                const last = h[h.length - 1].date || "";
                const days = last.length === 8
                    ? Math.round((Date.now() - new Date(+last.slice(0, 4), +last.slice(4, 6) - 1, +last.slice(6, 8)).getTime()) / 86400000) + 1
                    : h.length;
                fetch(source, Math.max(1, days), true);
            }
        } else {
            if (i > 0) selectItem(source, h[i - 1].id);
            else fetch(source, 0, true);
        }
    }
    function canStepOlder(source) {
        const info = sourceInfo(source) || {};
        const h = root.histories[source] || [];
        const i = historyIndex(source);
        return (i >= 0 && i < h.length - 1) || (info.kind === "daily" && h.length > 0);
    }
    function selectItem(source, id) { setState(s => { s.current = s.current || {}; s.current[source] = id; }); }

    // Next/previous for whatever the screen shows (IPC, WallpaperInfo).
    function next(output) {
        const sp = specFor(output || (Quickshell.screens[0] || {}).name || "*");
        if (sp.type === "potd") step(sp.source, 1);
        else if (sp.type === "folder") stepFolder(sp, 1);
    }
    function previous(output) {
        const sp = specFor(output || (Quickshell.screens[0] || {}).name || "*");
        if (sp.type === "potd") step(sp.source, -1);
        else if (sp.type === "folder") stepFolder(sp, -1);
    }
    function refresh(force) {
        for (const sp of usedSpecs()) if (sp.type === "potd") fetch(sp.source, 0, true);
    }

    // Legacy API used by WallpaperInfo/the old Settings row.
    function setMode(mode, image) {
        if (mode === "potd") setSpec({ type: "potd", source: "bing" }, "*");
        else if (image) setSpec({ type: "image", path: image }, "*");
    }

    // ---------------------------------------------------------------- API keys

    readonly property var keyNames: ["unsplash", "pexels", "flickr", "wallhaven"]
    function loadKeys() {
        for (const k of keyNames) job(["secret", "get", k], r => { if (!r.error) setMap("keys", k, !!r.set); });
    }
    function setKey(name, value, cb) {
        if (value) job(["secret", "set", name], r => { setMap("keys", name, !r.error); if (cb) cb(r); }, value + "\n");
        else job(["secret", "delete", name], r => { setMap("keys", name, false); if (cb) cb(r); });
    }

    // ---------------------------------------------------------------- catalog scans (Settings grid)

    property var weProjects: []
    property string weAssets: ""
    property var dynamicSets: []
    property var mediaItems: []       // [{ path, kind: "video"|"shader", name }]
    property bool scanning: false
    readonly property var dynamicDirs: {
        const d = (Quickshell.env("HEARTH_BACKGROUND_DIRS") || "").split(":").filter(x => x);
        return d.concat(["/run/current-system/sw/share/gnome-background-properties",
                         "/run/current-system/sw/share/backgrounds",
                         home + "/.local/share/gnome-background-properties", home + "/.local/share/backgrounds",
                         home + "/Pictures/Wallpapers", configDir + "/wallpapers"], cfg.extraDirs || []);
    }
    readonly property var mediaDirs: [home + "/Videos/Wallpapers", home + "/Pictures/Wallpapers",
                                      configDir + "/wallpapers", configDir + "/shaders"].concat(cfg.extraDirs || [])
    function scanCatalog() {
        if (root.scanning) return;
        root.scanning = true;
        let left = 3;
        const done = () => { if (--left === 0) root.scanning = false; };
        job(["scan-we", "--steam"], r => {
            if (!r.error) { root.weProjects = r.projects || []; root.weAssets = r.assets || ""; rebuildSoon(); }
            done();
        });
        job(["scan-dynamic", "--dir", root.cacheDir].concat(dynamicDirs), r => {
            if (Array.isArray(r)) root.dynamicSets = r;
            done();
        });
        job(["scan-media"].concat(mediaDirs), r => {
            if (Array.isArray(r)) root.mediaItems = r;
            done();
        });
    }
    function addItem(type, path) {
        const a = (root.cfg.added || []).filter(x => x.path !== path);
        a.push({ type: type, path: path });
        Settings.set("wallpaper.added", a);
    }
    function removeItem(path) {
        Settings.set("wallpaper.added", (root.cfg.added || []).filter(x => x.path !== path));
        Settings.set("wallpaper.folders", (root.cfg.folders || []).filter(x => x.path !== path));
    }
    function addFolder(path) {
        const f = (root.cfg.folders || []).filter(x => x.path !== path);
        f.push({ path: path, interval: 30, shuffle: true, recursive: true });
        Settings.set("wallpaper.folders", f);
    }

    // ---------------------------------------------------------------- pausing animation

    // Windows covering each screen, and whether any app is full screen.
    property var covered: ({})
    property bool fullscreenAny: false
    readonly property var coverInput: [Compositor.windows, Compositor.workspaces, Quickshell.screens]
    onCoverInputChanged: coverTimer.restart()
    Timer { id: coverTimer; interval: 250; onTriggered: root.computeCover() }
    function computeCover() {
        const cov = {};
        let fs = false;
        const activeWs = {};
        for (const w of Compositor.workspaces) if (w.active) activeWs[w.output] = w.id;
        for (const s of Quickshell.screens) {
            const wins = Compositor.windows.filter(w => !w.minimized && w.output === s.name
                && w.workspaceId === activeWs[s.name] && w.at && w.size);
            for (const w of wins)
                if (w.at[0] <= 1 && w.at[1] <= 1 && w.size[0] >= s.width - 2 && w.size[1] >= s.height - 2) fs = true;
            // Sample a grid below the menu bar: covered when 92% is under windows.
            let hit = 0, n = 0;
            const top = 30;
            for (let i = 0; i < 24; i++) for (let j = 0; j < 10; j++) {
                const x = (i + 0.5) / 24 * s.width, y = top + (j + 0.5) / 10 * (s.height - top);
                n++;
                if (wins.some(w => x >= w.at[0] && x < w.at[0] + w.size[0] && y >= w.at[1] && y < w.at[1] + w.size[1])) hit++;
            }
            cov[s.name] = n > 0 && hit / n >= 0.92;
        }
        if (JSON.stringify(cov) !== JSON.stringify(root.covered)) root.covered = cov;
        root.fullscreenAny = fs;
    }

    // Idle: the screen locks or turns off at the first of those timeouts.
    readonly property int idleTimeout: {
        const p = Settings.power;
        const t = [p.lock, p.displayOff].filter(x => x > 0);
        return t.length ? Math.min.apply(null, t) : 600;
    }
    IdleMonitor {
        id: idleMon
        enabled: root.animatedInUse && !!root.cfg.pauseIdle
        timeout: root.idleTimeout
        respectInhibitors: true
    }
    // The lock screen (hearth's own, which plays its own copy, or a
    // fallback hyprlock): the desktop's animation pauses underneath.
    readonly property bool locked: Lock.locked
    property bool lockerRunning: false
    Timer {
        interval: 5000
        running: root.animatedInUse
        repeat: true
        onTriggered: lockProbe.running = true
    }
    Process {
        id: lockProbe
        command: ["sh", "-c", "pidof hyprlock >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: root.lockerRunning = text.trim() === "1" }
    }
    readonly property bool onBattery: UPower.onBattery
    readonly property bool animatedInUse: usedSpecs().some(s => s.type === "video" || s.type === "shader" || s.type === "we") && !stillOnly
    readonly property string pauseReason: stillOnly ? "Still image only"
        : (root.locked || root.lockerRunning) ? "the screen is locked"
        : (idleMon.isIdle && root.cfg.pauseIdle) ? "the computer is idle"
        : (root.cfg.pauseBattery && root.onBattery) ? "on battery"
        : (root.cfg.pauseFullscreen && root.fullscreenAny) ? "an app is full screen" : ""
    function paused(output) {
        return root.pauseReason !== "" || (!!root.cfg.pauseCovered && !!root.covered[output]);
    }

    // ---------------------------------------------------------------- the stable still + lock/login export

    onFileChanged: linkTimer.restart()
    Timer {
        id: linkTimer
        interval: 300
        onTriggered: {
            if (!root.file) return;
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$2")" && ln -sfn "$1" "$2"', "sh", root.file, root.stableLink]);
            exportTimer.restart();
        }
    }
    onPrimaryViewChanged: exportTimer.restart()
    Timer {
        id: exportTimer
        interval: 1500
        onTriggered: root.doExport()
    }
    function exportView(v) {
        if (!v) return null;
        return {
            type: v.spec ? v.spec.type : "image",
            kind: v.kind,
            path: v.file || "",
            video: v.spec && v.spec.type === "video" ? v.spec.path : "",
            shader: v.spec && v.spec.type === "shader" ? String(v.shader || "").replace(/^file:\/\//, "") : "",
            wallpaperEngine: v.spec && v.spec.type === "we" ? v.spec.path : "",
            fit: v.fit,
            title: v.meta ? v.meta.title || "" : "",
            copyright: v.meta ? v.meta.copyright || "" : "",
            link: v.meta ? v.meta.link || "" : "",
            source: v.meta ? v.meta.source || "" : ""
        };
    }
    function doExport() {
        const v = root.primaryView;
        if (!v || !v.file) return;
        const outputs = {};
        for (const k in root.views) outputs[k] = exportView(root.views[k]);
        const data = Object.assign({ version: 1, updated: new Date().toISOString(),
                                     lockScreen: root.cfg.lockScreen !== false, outputs: outputs }, exportView(v));
        job(["export", root.exportJson, "--data", JSON.stringify(data), "--system", root.systemDir], r => {
            root.exportStatus = r.error ? "error" : (r.system || "");
            if (r.error) console.warn("hearth wallpaper: export:", r.error);
        });
    }

    // Old configs started swaybg under arbor: stop it once hearth's own
    // background is on screen (only the one on this compositor).
    property bool surfaceUp: false
    function backgroundReady() {
        if (root.surfaceUp) return;
        root.surfaceUp = true;
        Quickshell.execDetached(["sh", "-c",
            'for p in $(pgrep -u "$(id -u)" -x swaybg); do '
            + 'tr "\\0" "\\n" < /proc/$p/environ 2>/dev/null | grep -qx "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" && kill $p; done']);
    }

    // ---------------------------------------------------------------- IPC

    IpcHandler {
        target: "wallpaper"
        function refresh(): void { root.refresh(true); }
        function next(): void { root.next(""); }
        function previous(): void { root.previous(""); }
        function usePotd(): void { root.setSpec({ type: "potd", source: "bing" }, "*"); }
        function setImage(path: string): void {
            if (path.startsWith("~/")) path = root.home + path.substring(1);
            else if (path.startsWith("file://")) path = decodeURIComponent(path.substring(7));
            root.setSpec({ type: "image", path: path }, "*");
        }
        // spec JSON, output name or "" for all screens.
        function set(spec: string, output: string): string {
            try { root.setSpec(JSON.parse(spec), output || "*"); } catch (e) { return "bad JSON: " + e; }
            return "ok";
        }
        function stillOnly(on: bool): void { Settings.set("wallpaper.stillOnly", on); }
        function setLocked(on: bool): void { root.locked = on; }
        // Opens the info popup and returns the same details as text.
        function info(): string {
            root.infoRequested();
            return [root.sourceName, root.title, root.copyright, root.link, root.file, root.error]
                .filter(s => s).join("\n");
        }
        function state(): string {
            return JSON.stringify({ views: root.views, paused: Quickshell.screens.map(s => [s.name, root.paused(s.name)]),
                                    pauseReason: root.pauseReason, covered: root.covered, fullscreen: root.fullscreenAny,
                                    exportStatus: root.exportStatus }, null, 1);
        }
    }

    // "Save image as…": copy to ~/Pictures under the picture's name.
    function saveCopy() {
        if (!root.file) return;
        const it = root.primaryView && root.primaryView.meta && root.primaryView.meta.item;
        const base = it ? (root.sourceName + " " + (it.date || "") + " " + (it.title || it.id)).replace(/[\/:]/g, "-").slice(0, 120).trim()
                          + "." + (root.file.split(".").pop() || "jpg")
                        : root.file.split("/").pop();
        const src = it ? it.file : root.file;
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$HOME/Pictures" && cp -f "$1" "$HOME/Pictures/$2" '
            + '&& notify-send -a Wallpaper -i image-x-generic "Saved $2" "in ~/Pictures"',
            "sh", src, base]);
    }
    function openLink() {
        if (root.link) Launch.open(root.link);
    }

    // ---------------------------------------------------------------- load

    property bool historiesLoaded: false
    Process {
        id: histLoad
        running: true
        command: ["sh", "-c", 'for f in "$1"/*/history.json; do [ -f "$f" ] || continue; '
                  + 'printf "%s\\t" "$(basename "$(dirname "$f")")"; tr -d "\\n" < "$f"; echo; done', "sh", root.cacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const h = {};
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    try { h[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1)); } catch (e) {}
                }
                root.histories = h;
                root.historiesLoaded = true;
                root.rebuildSoon();
                root.fetchDue();
            }
        }
    }

    Timer { id: stateSave; interval: 500; onTriggered: stateFile.setText(JSON.stringify(root.st, null, 1)) }
    FileView {
        id: stateFile
        path: Quickshell.statePath("wallpaper.json")
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                // hearth before the engine: { mode: "potd"|"image", image }.
                if (s.mode !== undefined && !s.current) {
                    if (s.mode === "image" && s.image && !(Settings.data.wallpaper && Settings.data.wallpaper.displays))
                        Settings.set("wallpaper.displays", { "*": { type: "image", path: s.image } });
                    root.st = { current: {}, lastFetch: {}, folder: {} };
                } else {
                    root.st = Object.assign({ current: {}, lastFetch: {}, folder: {} }, s);
                }
            } catch (e) {}
            root.stateLoaded = true;
            root.fetchDue();
        }
        onLoadFailed: { root.stateLoaded = true; root.fetchDue(); }
    }

    Component.onCompleted: {
        loadKeys();
        // Wallpaper Engine titles/previews for the grid and the engine.
        job(["scan-we", "--steam"], r => {
            if (!r.error) { root.weProjects = r.projects || []; root.weAssets = r.assets || ""; rebuildSoon(); }
        });
        rebuildSoon();
    }
}
