# hearth

A Quickshell desktop shell for Hyprland and niri/arbor, replacing Ben's
Plasma panel: a macOS-style glass menu bar (with the focused app's global
menu on arbor) and auto-hiding, magnifying Dock, or the classic bottom panel;
launcher, task manager with live previews and badges, pager, system tray,
indicators for everything the Plasma tray did, Settings and Help windows.

- Layout and every option: Settings window (system menu → hearth Settings…,
  `hearth-ipc call settings open`), saved to `~/.config/hearth/settings.json`
  (`layout`: `"mac"` default or `"panel"`). Scripts: `hearth-ipc call settings
  set dock.size 64`.
- Compositor: `shell/services/Compositor.qml` picks Hyprland or niri (via
  `$NIRI_SOCKET`; `HEARTH_COMPOSITOR` overrides). On niri/arbor include
  `niri/hearth-layer-rules.kdl` for blur.
- Global menu (arbor + mac layout): `helpers/hearth-appmenu` owns
  `com.canonical.AppMenu.Registrar` (so Qt apps export their menus) and relays
  com.canonical.dbusmenu; the address comes from niri IPC `Window.app_menu`.
- Help: the ? in the menu bar, `hearth-ipc call help shortcuts` (Super+/).

- `nix run` / `hearth`: run the installed shell. `hearth-ipc call launcher toggle` etc.
- `nix develop`, then `quickshell -p shell`: run from the checkout; QML hot-reloads on save.
- `scripts/test-session.sh start|run|shot|stop NAME`: headless KWin -> nested Hyprland
  -> hearth, for screenshots while the real screen is locked.

Layout: `shell/shell.qml` (root), `shell/bar/` (panel pieces),
`shell/bar/indicators/` (tray indicators), `shell/popups/` (notifications, OSD,
polkit), `shell/services/` (singletons), `shell/widgets/` (shared building
blocks), `helpers/` (small DBus relays Quickshell can't do itself).

Font: Apple's SF Pro when installed (never shipped: Apple-licensed),
otherwise Inter, which the wrapper passes in as `HEARTH_FONT_DIR` (nixpkgs
`inter`); Settings > Appearance > Font.

Text: every Text uses native rendering (`//@ pragma NativeTextRendering` plus
`widgets/Label.qml`), and every window/popup root carries a
`Translate { x: 0.001; y: 0.001 }` so text never lands on an exact half
device pixel at 130% scale.
