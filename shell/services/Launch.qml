pragma Singleton
import QtQuick
import Quickshell

// Starts apps as their own user services (app-<id>-<n>.service), so they get
// the session's environment from the user manager rather than hearth's own.
// hearth may run inside a nix dev shell (devloop); apps launched straight
// from it inherited IN_NIX_SHELL, its TMPDIR and PATH, and missed session
// variables (2026-11-22). A service also gives each app its own cgroup, so
// per-app limits apply. ExitType=cgroup keeps launchers that fork and exit.
Singleton {
    id: root

    function app(entry, idHint) {
        if (!entry) return;
        const cmd = (entry.command || []).filter(a => !/^%[a-zA-Z]$/.test(a));
        if (cmd.length === 0 || entry.runInTerminal) { entry.execute(); return; }
        start(cmd, entry.id || idHint || cmd[0].split("/").pop(), entry.workingDirectory || "");
    }

    // Any other program the user starts from hearth (a file or link with its
    // default app, a URL): the same clean start as `app`. Started straight
    // from hearth it inherited hearth's environment and its raised priority
    // (Nice=-10, so the desktop stays responsive; an app shouldn't get it).
    function run(cmd, idHint) {
        if (!cmd || cmd.length === 0) return;
        start(cmd, idHint || cmd[0].split("/").pop(), "");
    }

    function start(cmd, idHint, workingDirectory) {
        const id = String(idHint).replace(/[^A-Za-z0-9:_.]/g, "_");
        const unit = "app-" + id + "-" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
        const args = ["systemd-run", "--user", "--collect", "--quiet", "--unit=" + unit,
                      "-p", "ExitType=cgroup"];
        // On hearth's own display: the user manager's WAYLAND_DISPLAY can be
        // stale (a nested test session had set it to its own, so apps from
        // the Dock opened there, or not at all).
        for (const v of ["WAYLAND_DISPLAY", "DISPLAY"]) {
            const val = Quickshell.env(v);
            if (val) args.push("--setenv=" + v + "=" + val);
        }
        if (workingDirectory) args.push("--working-directory=" + workingDirectory);
        if (Compositor.isArbor && Compositor.backend && Compositor.backend.socketPath) {
            // Under arbor, arbor itself runs systemd-run (its Spawn action),
            // which hands it a fresh xdg-activation token in
            // XDG_ACTIVATION_TOKEN / DESKTOP_STARTUP_ID; a bare --setenv=NAME
            // copies that into the app's unit. With the token the app can
            // bring a window forward: a new one, or an open one it hands the
            // work to (`tessera -e` opens a tab in the running Tessera and
            // raises it). hearth's own launches had no token, so arbor only
            // marked such windows urgent, behind the focused one.
            args.push("--setenv=XDG_ACTIVATION_TOKEN", "--setenv=DESKTOP_STARTUP_ID");
            Compositor.arborAction("Spawn", { command: args.concat(["--"], cmd) });
            return;
        }
        Quickshell.execDetached(args.concat(["--"], cmd));
    }
    // A file, folder or URL with its default app.
    function open(target) { run(["xdg-open", String(target)], "xdg-open"); }
}
