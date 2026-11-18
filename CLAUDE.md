# hearth conventions

Quickshell 0.3.2 shell for Hyprland 0.55 (Lua config). Read README.md first.

## QML rules
- All text: `widgets/Label.qml` (native rendering). Text inputs set
  `renderType: Text.NativeRendering` themselves.
- Popups: use `widgets/Indicator.qml` (tray button + popup) or
  `widgets/BarPopup.qml`. They already carry the 0.001 px nudge and close on
  outside click via HyprlandFocusGrab. Any other top-level window/popup root
  needs `transform: Translate { x: 0.001; y: 0.001 }` (Ben's display is 130%:
  text on an exact half device pixel smears).
- Colours/sizes from `Theme` (`import ".."` or `"../.."`), Breeze Dark.
- Icons: `widgets/Icon.qml` with freedesktop/Breeze icon names.
- Hyprland dispatches go through `services/Hypr.qml` (the Lua config means
  `hyprctl dispatch` takes Lua expressions such as `hl.dsp.focus({ workspace = 3 })`).
- Quickshell has no generic DBus. Shell out with `Process` (nmcli, udisksctl,
  busctl, ddcutil...) or add a small relay in `helpers/` (python3 with
  dbus-python + gi is in the runtime PATH) that prints JSON lines.
- Give each Indicator an `ipcName` (set in `bar/Tray.qml`) so
  `hearth-ipc call indicator-<name> toggle` opens it.
- Runtime tools must be in `runtimeDeps` in flake.nix.

## API reference
Exact property/method names: the qmltypes under
`$(nix build --no-link --print-out-paths .#quickshell)/lib/qt-6/qml/Quickshell`.
Docs: https://quickshell.org/docs/v0.3.2/types/

## Testing
`scripts/test-session.sh start NAME`, then `run NAME` after each change
(prints QML warnings), `ipc NAME call indicator-x toggle` to open a popup,
`shot NAME out.png` for a 3938x1662 screenshot (bar is the bottom 44 px).
Use your own NAME so parallel sessions don't collide; `stop NAME` when done.
The tray shows the real session's apps (same session bus).

## Git
Commit and push every working piece right away. Only stage your own files
(`git add <paths>`, never `-A` while others work in the tree).
