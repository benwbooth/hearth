# hearth

A Quickshell desktop shell for Hyprland, replacing Ben's Plasma panel:
launcher, icon task manager with live previews and badges, pager, system
tray, and indicators for everything the Plasma tray did.

- `nix run` / `hearth`: run the installed shell. `hearth-ipc call launcher toggle` etc.
- `nix develop`, then `quickshell -p shell`: run from the checkout; QML hot-reloads on save.
- `scripts/test-session.sh start|run|shot|stop NAME`: headless KWin -> nested Hyprland
  -> hearth, for screenshots while the real screen is locked.

Layout: `shell/shell.qml` (root), `shell/bar/` (panel pieces),
`shell/bar/indicators/` (tray indicators), `shell/popups/` (notifications, OSD,
polkit), `shell/services/` (singletons), `shell/widgets/` (shared building
blocks), `helpers/` (small DBus relays Quickshell can't do itself).

Text: every Text uses native rendering (`//@ pragma NativeTextRendering` plus
`widgets/Label.qml`), and every window/popup root carries a
`Translate { x: 0.001; y: 0.001 }` so text never lands on an exact half
device pixel at 130% scale.
