pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Desktop wallpaper, shown by hyprpaper. Default is Bing's image of the day
// (what Plasma's "Picture of the Day" did): the UHD image is cached in
// Quickshell.cachePath("wallpaper/"), Bing is checked at startup and hourly
// (a small JSON request; the image is only downloaded when it changed), and
// the last cached image stays up while offline. Mode "image" shows a fixed
// file instead; mode and file live in the state dir (wallpaper.json).
//
// Each change runs `hyprctl hyprpaper wallpaper ",<file>,cover"` and points
// ~/.cache/hearth/wallpaper (a stable path, unlike cachePath's per-shell
// hash) at the file, so hyprpaper.conf can name it and show the right image
// at login before hearth is up.
//
//   hearth-ipc call wallpaper refresh | usePotd | setImage PATH | info
Singleton {
    id: root

    property string mode: "potd"        // "potd" | "image"
    property string image: ""           // fixed file for mode "image"
    // Last fetched picture of the day:
    // { id, startdate, file, title, copyright, link, checked }
    property var potd: null

    readonly property string file: mode === "image" ? image : potd ? potd.file : ""
    readonly property string title: mode === "image" ? image.split("/").pop() : potd ? potd.title : ""
    readonly property string copyright: mode === "image" ? "" : potd ? potd.copyright : ""
    readonly property string link: mode === "image" ? "" : potd ? potd.link : ""
    property bool loading: false
    property string error: ""

    readonly property string cacheDir: Quickshell.cachePath("wallpaper")
    readonly property string home: Quickshell.env("HOME")
    readonly property string stableLink: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/hearth/wallpaper"

    signal infoRequested()

    IpcHandler {
        target: "wallpaper"
        function refresh(): void { root.refresh(true); }
        function usePotd(): void { root.setMode("potd", root.image); root.refresh(false); }
        function setImage(path: string): void {
            if (path.startsWith("~/")) path = root.home + path.substring(1);
            else if (path.startsWith("file://")) path = decodeURIComponent(path.substring(7));
            root.setMode("image", path);
        }
        // Opens the info popup and returns the same details as text.
        function info(): string {
            root.infoRequested();
            return [root.mode, root.title, root.copyright, root.link, root.file, root.error]
                .filter(s => s).join("\n");
        }
    }

    function today() {
        return Qt.formatDate(new Date(), "yyyyMMdd");
    }

    function setMode(mode, image) {
        root.mode = mode;
        root.image = image;
        stateFile.setText(JSON.stringify({ mode: root.mode, image: root.image }, null, 2));
    }

    // force: download the image again even if it's the cached one.
    // curl rather than XMLHttpRequest: Qt's request sometimes never finished.
    function refresh(force) {
        if (root.loading) return;
        root.loading = true;
        fetch.force = force;
        fetch.running = true;
    }

    Process {
        id: fetch
        property bool force: false
        command: ["curl", "-fsS", "--max-time", "30",
                  "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"]
        stdout: StdioCollector { id: fetchOut }
        stderr: StdioCollector { id: fetchErr }
        onExited: code => root.gotMeta(code, fetchOut.text, fetchErr.text, force)
    }

    function gotMeta(code, text, err, force) {
        let img = null;
        if (code === 0) {
            try { img = JSON.parse(text).images[0]; } catch (e) {}
        }
        if (!img || !img.urlbase) {
            root.loading = false;
            root.error = "Bing: " + (err.trim() || "bad response");
            return;
        }
        root.error = "";
        const id = img.urlbase.replace(/^.*[?&]id=/, "");
        const meta = {
            id: id, startdate: img.startdate || "",
            title: img.title || "", copyright: img.copyright || "",
            link: img.copyrightlink || "", checked: root.today(),
            file: `${root.cacheDir}/${id}_UHD.jpg`
        };
        if (!force && root.potd && root.potd.id === id) {
            root.loading = false;
            // Same picture: just keep the metadata current.
            meta.file = root.potd.file;
            root.potd = meta;
            saveMeta();
            return;
        }
        download.meta = meta;
        download.command = ["sh", "-c",
            'mkdir -p "$1" && { curl -fsSL --retry 2 -o "$2.part" "$3" || curl -fsSL --retry 2 -o "$2.part" "$4"; } '
            + '&& mv -f "$2.part" "$2" '
            // keep the newest few
            + '&& ls -1t "$1"/*.jpg | tail -n +6 | xargs -r rm -f --',
            "sh", root.cacheDir, meta.file,
            `https://www.bing.com${img.urlbase}_UHD.jpg`,
            `https://www.bing.com${img.url}`];
        download.running = true;
    }

    function saveMeta() {
        metaFile.setText(JSON.stringify(root.potd, null, 2));
    }

    // "Save image as…": copy to ~/Pictures under the picture's name.
    function saveCopy() {
        if (!root.file) return;
        const base = root.mode === "potd" && root.potd
            ? "Bing " + root.potd.id.replace(/^OHR\./, "").replace(/_.*$/, "") + " " + root.potd.startdate + ".jpg"
            : root.file.split("/").pop();
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$HOME/Pictures" && cp -f "$1" "$HOME/Pictures/$2" '
            + '&& notify-send -a Wallpaper -i image-x-generic "Saved $2" "in ~/Pictures"',
            "sh", root.file, base]);
    }

    function openLink() {
        if (root.link) Quickshell.execDetached(["xdg-open", root.link]);
    }

    Process {
        id: download
        property var meta: null
        stderr: StdioCollector { id: dlErr }
        onExited: code => {
            root.loading = false;
            if (code !== 0) {
                root.error = "Download failed: " + dlErr.text.trim();
                return;
            }
            root.potd = meta;
            root.saveMeta();
        }
    }

    // ---- show it (hyprpaper on Hyprland, swaybg on arbor) ----
    onFileChanged: applyTimer.restart()
    property int applyTries: 0
    Timer {
        id: applyTimer
        interval: 200
        onTriggered: { root.applyTries = 0; root.apply(); }
    }
    function apply() {
        if (!root.file) return;
        if (Compositor.isArbor) {
            // arbor: swaybg shows the stable link; restart it on the new
            // image (swaybg doesn't watch its file). setsid: it outlives a
            // hearth restart, like the one arbor's config starts.
            Quickshell.execDetached(["sh", "-c",
                'mkdir -p "$(dirname "$2")" && ln -sfn "$1" "$2"; '
                + 'pkill -x swaybg; setsid -f swaybg -m fill -i "$2" >/dev/null 2>&1',
                "sh", root.file, root.stableLink]);
            return;
        }
        apply_.command = ["sh", "-c",
            'mkdir -p "$(dirname "$2")" && ln -sfn "$1" "$2"; '
            + 'out=$(hyprctl hyprpaper wallpaper ",$1,cover" 2>&1); echo "$out"; '
            + 'case "$out" in *rror*|*"not set"*|*"ouldn"*) exit 1;; esac',
            "sh", root.file, root.stableLink];
        apply_.running = true;
    }
    Process {
        id: apply_
        stdout: StdioCollector { id: applyOut }
        onExited: code => {
            if (code === 0) return;
            // hyprpaper may not be up yet at login: retry for a minute.
            if (++root.applyTries < 20) retryTimer.start();
            else console.warn("hearth wallpaper: hyprpaper didn't take the image:", applyOut.text.trim());
        }
    }
    Timer {
        id: retryTimer
        interval: 3000
        onTriggered: root.apply()
    }

    // Hourly Bing check (cheap JSON; picks up the new picture soon after it
    // appears), and sooner after a failure such as no network at login.
    Timer {
        interval: 60 * 60 * 1000
        running: root.mode === "potd"
        repeat: true
        onTriggered: root.refresh(false)
    }
    Timer {
        interval: 5 * 60 * 1000
        running: root.mode === "potd" && root.error !== "" && !root.loading
        onTriggered: root.refresh(false)
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("wallpaper.json")
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (s.mode === "image" || s.mode === "potd") root.mode = s.mode;
                root.image = s.image || "";
            } catch (e) {}
        }
    }
    FileView {
        id: metaFile
        path: root.cacheDir + "/meta.json"
        printErrors: false
        onLoaded: {
            try { root.potd = JSON.parse(text()); } catch (e) {}
            root.refresh(false);
        }
        onLoadFailed: root.refresh(false)
    }
}
