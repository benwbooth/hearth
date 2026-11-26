pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// hearth's AI hub (README "AI"): every model the desktop uses, through
// helpers/hearth-ai. Local servers (Ollama, llama.cpp) and coding-agent
// CLIs (Claude Code, Codex, Gemini); installed and loaded models, VRAM per
// GPU and per process; the assistant used by voice and Spotlight's "Ask".
// Settings > AI and the menu bar's AI icon show it.
//
//   hearth-ipc call ai state | unloadAll | load ollama qwen3.5:4b | unload ollama qwen3.5:4b
//   hearth-ai --state      (the same, from a terminal)
Singleton {
    id: root

    readonly property var defaults: ({
        allowCloud: false,              // the Claude/Codex/Gemini CLIs may be used
        unloadOnFullscreen: false,      // free VRAM while a game or video is full screen
        menuBarStats: true,             // GPU busy % and VRAM % next to the AI icon
        // Memory manager (helpers/hearth-ai Arbiter): models unused this
        // many minutes unload (slow loaders get loadTimeFactor x their load
        // time, up to an hour); a full card evicts idle models first.
        autoUnload: true,
        idleMinutes: 5,
        loadTimeFactor: 10,
        evictOnPressure: true,
        pinned: [],                     // keys never unloaded automatically
        modelDirs: [],                  // extra folders with GGUF models
        providers: {
            ollama: { enabled: true, url: "http://127.0.0.1:11434" },
            llamacpp: { enabled: true, url: "http://127.0.0.1:8181", modelsDir: "~/models", modelsMax: 1 },
            claude: { enabled: false },
            codex: { enabled: false },
            gemini: { enabled: false }
        },
        assistant: { provider: "ollama", model: "qwen3.5:4b" }
    })
    readonly property var cfg: {
        void Settings.data;
        const d = Settings.data.ai || {};
        const p = Object.assign({}, defaults.providers);
        for (const k in (d.providers || {})) p[k] = Object.assign({}, p[k] || {}, d.providers[k]);
        return Object.assign({}, defaults, d, { providers: p, assistant: Object.assign({}, defaults.assistant, d.assistant || {}) });
    }

    // Last state from the helper.
    property var providers: []
    property var gpus: []
    property var processes: []
    property var clis: []               // [{ id, label, installed }] Claude Code, Codex, Gemini CLI
    property bool ready: false
    property string busy: ""            // "provider/model" being loaded
    property string lastError: ""
    property var pulls: ({})            // "provider/model" -> { status, completed, total }

    // The discrete GPU (biggest VRAM): busy %, VRAM used/free/percent, GTT.
    property var gpu: null
    readonly property var mainGpu: gpu || (gpus.length ? gpus.reduce((a, b) => b.total > a.total ? b : a) : null)
    // Every loaded model, from the helper's memory manager: { key, name,
    // category, categoryLabel, provider, providerLabel, kind (server |
    // process), vram, gtt, active, gpuPercent, idleSec, loadSec, idleLimit,
    // unloadIn (-1 never), pinned, canUnload, unloadLabel, unit, external }.
    property var loaded: []
    // Every installed model: { key, name, family, category, categoryLabel,
    // source, size, sizeText, quant, context, runners: [{ provider, model,
    // label, fits, note }], loaded, loadable, deletable }.
    property var installed: []
    property var apps: []               // other GPU users: [{ name, vram, vramText, count }]
    property var categories: []         // [{ id, label }]
    property int modelVram: 0
    property var evicted: []            // the last few automatic unloads: [{ name, reason, vramText, time }]
    property var catalog: ({ sections: [], category: "", query: "", loading: false })
    signal tabRequested(string tab, string category)
    function provider(id) { return providers.find(p => p.id === id) || null; }
    function isLoaded(pid, model) {
        return loaded.some(m => m.provider === pid && (m.model === model || m.name === model));
    }

    // Several views (Settings > AI, the menu bar popup) can watch: the
    // helper polls every 2 s only while one is open, else every 30 s.
    property int watchers: 0
    function watch(on) {
        watchers = Math.max(0, watchers + (on ? 1 : -1));
        send({ cmd: "watch", on: watchers > 0 });
    }

    function send(obj) {
        if (!proc.running) proc.running = true;
        proc.write(JSON.stringify(obj) + "\n");
    }
    function refresh() { send({ cmd: "refresh" }); }
    function load(pid, model) { busy = pid + "/" + model; send({ cmd: "load", provider: pid, model: model }); }
    function unload(pid, model) { send({ cmd: "unload", provider: pid, model: model }); }
    function unloadAll() { send({ cmd: "unloadAll" }); }
    function pull(pid, model) {
        const p = Object.assign({}, pulls); p[pid + "/" + model] = { status: "starting", completed: 0, total: 0 }; pulls = p;
        send({ cmd: "pull", provider: pid, model: model });
    }
    function remove(pid, model) { send({ cmd: "delete", provider: pid, model: model }); }
    // By key (Ai.loaded / Ai.installed entries).
    property var busyKeys: ({})         // key -> "loading" | "unloading" | "removing"
    function markBusy(key, what) { const b = Object.assign({}, busyKeys); if (what) b[key] = what; else delete b[key]; busyKeys = b; }
    function loadKey(key, provider) { markBusy(key, "loading"); send({ cmd: "loadKey", key: key, provider: provider || "" }); }
    function unloadKey(key) { markBusy(key, "unloading"); send({ cmd: "unloadKey", key: key }); }
    function removeKey(key) { markBusy(key, "removing"); send({ cmd: "remove", key: key }); }
    function pin(key, on) { send({ cmd: "pin", key: key, on: on }); }
    function isPinned(key) { return (cfg.pinned || []).indexOf(key) >= 0; }
    function install(provider, model) {
        const p = Object.assign({}, pulls); p[provider + "/" + model] = { status: "starting", completed: 0, total: 0 }; pulls = p;
        send({ cmd: "install", provider: provider, model: model });
    }
    function browse(category, query) {
        catalog = Object.assign({}, catalog, { loading: true, category: category, query: query || "" });
        send({ cmd: "catalog", category: category, query: query || "", browse: true });
    }
    function server(pid, on) { send({ cmd: "server", provider: pid, on: on }); }

    // --- assistant ---
    property int nextId: 1
    property var handlers: ({})        // id -> { onReply, onStep, onTool }
    function ask(text, context, h) {
        const id = nextId++;
        const hs = Object.assign({}, handlers); hs[id] = h; handlers = hs;
        send({ cmd: "ask", id: id, feature: "assistant", text: text, context: context || {}, history: h.history || [] });
        return id;
    }
    function cancel(id) {
        send({ cmd: "cancel", id: id });
        const hs = Object.assign({}, handlers); delete hs[id]; handlers = hs;
    }

    Process {
        id: proc
        command: ["hearth-ai"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                root.handle(m);
            }
        }
        stderr: SplitParser { onRead: line => console.warn(line) }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 3000; onTriggered: proc.running = true }

    function handle(m) {
        switch (m.type) {
        case "state":
            root.providers = m.providers || [];
            root.gpus = m.gpus || [];
            root.gpu = m.gpu || null;
            if (m.processes) root.processes = m.processes;
            root.clis = m.clis || [];
            root.loaded = m.loaded || [];
            root.installed = m.installed || [];
            root.apps = m.apps || [];
            root.categories = m.categories || [];
            root.modelVram = m.modelVram || 0;
            root.ready = true;
            break;
        case "busy":
            root.busy = m.provider + "/" + m.model;
            break;
        case "done": {
            if (m.cmd === "load" || m.cmd === "loadKey") root.busy = "";
            if (m.key) root.markBusy(m.key, "");
            const verb = { load: "Couldn't load", loadKey: "Couldn't load", unload: "Couldn't unload", unloadKey: "Couldn't unload",
                           pull: "Couldn't download", remove: "Couldn't remove", delete: "Couldn't delete" }[m.cmd] || ("Couldn't " + m.cmd);
            root.lastError = m.error ? `${verb} ${m.model || ""}: ${m.error}` : "";
            break;
        }
        case "gpu":
            root.gpu = m.gpu || null;
            break;
        case "evicted": {
            const ev = [Object.assign({ time: Date.now() }, m)].concat(root.evicted).slice(0, 5);
            root.evicted = ev;
            break;
        }
        case "setting":
            Settings.set(m.path, m.value);
            break;
        case "catalog":
            root.catalog = Object.assign({ loading: false }, m);
            break;
        case "pull": {
            const p = Object.assign({}, root.pulls);
            const k = m.provider + "/" + m.model;
            if (m.done || m.error) delete p[k];
            else p[k] = { status: m.status, completed: m.completed || 0, total: m.total || 0 };
            root.pulls = p;
            if (m.error) root.lastError = `Couldn't download ${m.model}: ${m.error}`;
            break;
        }
        case "step": {
            const h = root.handlers[m.id];
            if (h && h.onStep) h.onStep(m.name, m.args);
            break;
        }
        case "tool": {
            const h = root.handlers[m.id];
            const result = root.runTool(m.name, m.args || {});
            send({ cmd: "toolResult", id: m.id, call: m.call, result: result });
            if (h && h.onTool) h.onTool(m.name, m.args, result);
            break;
        }
        case "reply": {
            const h = root.handlers[m.id];
            if (h && h.onReply) h.onReply(m.text || "", !!m.error);
            const hs = Object.assign({}, root.handlers); delete hs[m.id]; root.handlers = hs;
            break;
        }
        }
    }

    // Tools the shell itself runs (helpers/hearth-ai SHELL_TOOLS).
    function findApp(name) {
        const q = (name || "").toLowerCase().trim();
        if (!q) return null;
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        return apps.find(e => e.name.toLowerCase() === q)
            || apps.find(e => e.name.toLowerCase().startsWith(q))
            || apps.find(e => e.id.toLowerCase().replace(/\.desktop$/, "").split(".").pop() === q)
            || apps.find(e => e.name.toLowerCase().includes(q))
            || apps.find(e => (e.genericName || "").toLowerCase().includes(q))
            || apps.find(e => (e.keywords || []).some(k => k.toLowerCase() === q))
            || null;
    }
    function runTool(name, args) {
        switch (name) {
        case "launch_app": {
            const e = findApp(args.name);
            if (!e) return `No app called ${args.name} is installed.`;
            if (Quickshell.env("HEARTH_AI_DRYRUN")) return `Opened ${e.name} (dry run).`;
            Launch.app(e);
            return `Opened ${e.name}.`;
        }
        case "get_weather": {
            if (!Weather.hasLocation) return "No place is set for the weather (menu bar weather icon).";
            const c = Weather.current;
            if (!c) return "The weather isn't loaded yet.";
            const d = Weather.daily.length ? Weather.daily[0] : null;
            return `${Weather.locationName}: ${Math.round(c.temp)}${Weather.tempUnit}, ${c.text}, feels like ${Math.round(c.feels)}${Weather.tempUnit}`
                + (d ? `; today ${Math.round(d.min)} to ${Math.round(d.max)}${Weather.tempUnit}, ${d.text}, ${d.pop || 0}% chance of rain` : "");
        }
        case "desktop_action": {
            const v = args.value;
            switch (args.action) {
            case "lock_screen": Session.run("lock"); return "Locked.";
            case "sleep": Session.run("suspend"); return "Going to sleep.";
            case "dark_mode_on": Settings.set("appearance.mode", "dark"); return "Dark mode is on.";
            case "dark_mode_off": Settings.set("appearance.mode", "light"); return "Light mode is on.";
            case "do_not_disturb_on": Notifications.setDnd(true); return "Do Not Disturb is on.";
            case "do_not_disturb_off": Notifications.setDnd(false); return "Do Not Disturb is off.";
            case "screenshot": Screenshots.overlayRequested(""); return "Screenshot tool opened.";
            case "show_desktop": Compositor.focusEmptyWorkspace(); return "Showing the desktop.";
            case "show_all_windows": ShellState.overviewRequested(); return "Showing all windows.";
            case "next_wallpaper": Wallpaper.next(""); return "Next wallpaper.";
            case "set_brightness": {
                const pct = Math.max(1, Math.min(100, parseInt(v) || 50));
                Brightness.setAll(pct, true);
                return `Brightness set to ${pct}%.`;
            }
            case "open_settings": Settings.openRequested(String(v || "")); return "Settings opened.";
            }
            return "I can't do that action.";
        }
        }
        return "Unknown tool.";
    }

    // Free VRAM while something is full screen (Settings > AI).
    readonly property bool fullscreen: Wallpaper.fullscreenAny
    onFullscreenChanged: if (fullscreen && cfg.unloadOnFullscreen && loaded.some(m => !m.external)) unloadAll()

    IpcHandler {
        target: "ai"
        function state(): string {
            return JSON.stringify({ gpus: root.gpus.map(g => `${g.name}: ${g.usedText} / ${g.totalText}`),
                                    loaded: root.loaded.map(m => `${m.providerLabel}: ${m.name}`),
                                    installed: root.installed.map(m => `${m.providerLabel}: ${m.name}`) }, null, 1);
        }
        function refresh(): void { root.refresh(); }
        function load(provider: string, model: string): void { root.load(provider, model); }
        function unload(provider: string, model: string): void { root.unload(provider, model); }
        function unloadAll(): void { root.unloadAll(); }
        // The AI menu's tab: loaded | installed | more (and a category id).
        function showTab(tab: string, category: string): void { root.tabRequested(tab, category); }
    }
}
