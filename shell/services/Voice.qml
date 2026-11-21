pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The voice assistant (README "Voice assistant"), like Siri but local:
// press the shortcut (Super+Alt+Space by default; Settings > Keyboard
// Shortcuts) or the menu bar's orb, speak, and it stops listening when you
// stop talking. Speech goes to whisper-typer's Whisper server through
// helpers/hearth-voice; the words go to the assistant model (services/Ai,
// Settings > AI), which can search files, open apps and files, change the
// volume, run desktop actions and answer questions. Replies are shown in
// the glowing overlay (popups/VoiceOverlay.qml) and, with Settings > Voice
// > Speak replies, read aloud by Piper.
//
//   hearth-ipc call voice toggle | start | stop | cancel | ask "TEXT"
Singleton {
    id: root

    readonly property var defaults: ({
        enabled: true,
        whisperUrl: "ws://127.0.0.1:9090",
        whisperModel: "small",
        language: "en",
        silenceMs: 1000,                // quiet after speech that ends listening
        maxSeconds: 15,
        speak: false,                   // read replies aloud (Piper)
        piperVoice: "en_US-ryan-high",
        sounds: true,                   // a chime when listening starts and ends
        edgeGlow: true                  // the glowing screen edge while listening
    })
    readonly property var cfg: { void Settings.data; return Object.assign({}, defaults, Settings.data.voice || {}); }

    // "idle" | "connecting" | "listening" | "transcribing" | "thinking" | "answer"
    property string phase: "idle"
    property real level: 0
    property string heard: ""           // live transcript
    property string reply: ""
    property bool replyError: false
    property var steps: []              // [{ name, text }] what the assistant did
    property bool speaking: false
    property bool visible: phase !== "idle"
    property int askId: 0
    property var history: []            // the conversation so far (until dismissed)
    property var voices: ({ installed: [], available: [] })
    property var download: null         // { voice, done, total }

    // The shortcut as Settings > Keyboard Shortcuts has it (arbor).
    readonly property string shortcutText: {
        const e = Binds.effective.find(b => !b.off && /"voice" "toggle"/.test(b.action));
        return e ? Binds.pretty(e.key) : "Super+Alt+Space";
    }

    function send(obj) {
        if (!proc.running) proc.running = true;
        proc.write(JSON.stringify(obj) + "\n");
    }

    function listen() {
        if (!cfg.enabled) {
            replyError = true;
            reply = "The voice assistant is turned off in Settings > Voice.";
            phase = "answer";
            return;
        }
        if (askId) { Ai.cancel(askId); askId = 0; }
        heard = "";
        reply = "";
        replyError = false;
        steps = [];
        phase = "connecting";
        chime("start");
        send({ cmd: "listen" });
    }
    function stop() { send({ cmd: "stop" }); }
    function toggle() {
        if (phase === "listening" || phase === "connecting") stop();
        else listen();
    }
    function dismiss() {
        send({ cmd: "cancel" });
        if (askId) Ai.cancel(askId);
        askId = 0;
        phase = "idle";
        history = [];
        level = 0;
    }

    // Typed questions (Spotlight's "Ask") skip the microphone.
    function ask(text) {
        text = (text || "").trim();
        if (!text) return;
        if (askId) Ai.cancel(askId);
        heard = text;
        reply = "";
        replyError = false;
        steps = [];
        phase = "thinking";
        const ctx = { place: Weather.hasLocation ? Weather.locationName : "" };
        const q = text;
        askId = Ai.ask(text, ctx, {
            history: root.history,
            onStep: (name, args) => root.steps = root.steps.concat([{ name: name, text: root.describe(name, args) }]),
            onReply: (answer, err) => {
                root.askId = 0;
                root.reply = answer;
                root.replyError = err;
                root.phase = "answer";
                if (!err) root.history = root.history.concat([{ role: "user", content: q }, { role: "assistant", content: answer }]).slice(-8);
                if (root.cfg.speak && !err) root.send({ cmd: "speak", text: answer });
            }
        });
    }

    function describe(name, a) {
        switch (name) {
        case "search_files": return "Searching for “" + (a.query || "") + "”" + (a.kind ? " (" + a.kind + ")" : "");
        case "open_file": return "Opening " + String(a.path || "").split("/").pop();
        case "reveal_file": return "Showing it in the file manager";
        case "launch_app": return "Opening " + (a.name || "the app");
        case "set_volume": return "Volume " + Math.round(a.percent) + "%";
        case "change_volume": return a.delta >= 0 ? "Volume up" : "Volume down";
        case "mute": return a.muted ? "Muting" : "Unmuting";
        case "get_weather": return "Checking the weather";
        case "calculate": return "Calculating " + (a.expression || "");
        case "web_search": return "Searching the web";
        case "desktop_action": return String(a.action || "").replace(/_/g, " ");
        }
        return name.replace(/_/g, " ");
    }

    function chime(which) {
        if (!cfg.sounds) return;
        const dir = Quickshell.env("HEARTH_SOUND_DIR");
        if (!dir) return;
        Quickshell.execDetached(["pw-play", "--volume", "0.5", dir + (which === "start" ? "/message-new-instant.oga" : "/complete.oga")]);
    }

    function refreshVoices() { send({ cmd: "voices" }); }
    function downloadVoice(v) { download = { voice: v, done: 0, total: 0 }; send({ cmd: "download", voice: v }); }
    function speak(text) { send({ cmd: "speak", text: text }); }
    function hush() { send({ cmd: "hush" }); }

    Process {
        id: proc
        command: ["hearth-voice"]
        running: false
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                root.handle(m);
            }
        }
        stderr: SplitParser { onRead: line => console.warn("hearth-voice:", line) }
    }

    function handle(m) {
        switch (m.type) {
        case "state":
            if (m.state === "connecting" || m.state === "listening" || m.state === "transcribing") root.phase = m.state;
            if (m.state === "transcribing") root.chime("end");
            break;
        case "level": root.level = m.level; break;
        case "partial": root.heard = m.text; break;
        case "final":
            root.level = 0;
            if (m.text) root.ask(m.text);
            else {
                root.reply = m.heard ? "Sorry, I didn't catch that." : "I didn't hear anything. Check the microphone in Sound settings.";
                root.replyError = true;
                root.phase = "answer";
            }
            break;
        case "error":
            root.reply = m.message;
            root.replyError = true;
            root.phase = "answer";
            break;
        case "speaking": root.speaking = m.on; break;
        case "voices": root.voices = m; break;
        case "download":
            root.download = m.finished ? null : { voice: m.voice, done: m.done, total: m.total };
            if (m.error) { root.reply = "Couldn't download the voice: " + m.error; }
            break;
        }
    }

    IpcHandler {
        target: "voice"
        function toggle(): void { root.toggle(); }
        function start(): void { root.listen(); }
        function stop(): void { root.stop(); }
        function cancel(): void { root.dismiss(); }
        function ask(text: string): void { root.ask(text); }
        function state(): string { return JSON.stringify({ phase: root.phase, heard: root.heard, reply: root.reply, steps: root.steps }); }
    }
}
