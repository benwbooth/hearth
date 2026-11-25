# hearth conventions

Quickshell 0.3.2 shell for Hyprland 0.55 (Lua config) and arbor. Read
README.md first.

## QML rules
- All text: `widgets/Label.qml` (native rendering). Text inputs set
  `renderType: Text.NativeRendering` themselves.
- Popups: use `widgets/Indicator.qml` (tray button + popup) or
  `widgets/BarPopup.qml`. They already carry the 0.001 px nudge and close on
  outside click via HyprlandFocusGrab. Any other top-level window/popup root
  needs `transform: Translate { x: 0.001; y: 0.001 }` (Ben's display is 4/3 under Hyprland, 130% under Plasma:
  text on an exact half device pixel smears).
- Colours/sizes from `Theme` (`import ".."` or `"../.."`), Breeze Dark.
- Icons: `widgets/Icon.qml` with freedesktop/Breeze icon names.
- Window/workspace state and actions go through `services/Compositor.qml`
  (Hyprland and arbor backends); Hyprland-only features check
  `Compositor.isHyprland` and must not touch `Quickshell.Hyprland` otherwise.
- User options live in `services/Settings.qml` (settings.json) and get a row
  in `popups/SettingsWindow.qml` with a one-line explanation; new actions and
  shortcuts go into `services/Help.qml` so the Help search finds them.
- Bars set `edge` ("top"/"bottom"/"left"/"right") on their window; BarPopup,
  Tooltip and previews open away from it. Never make a bar window change size
  or visibility per frame: animate content inside a fixed-size surface.
- Hyprland dispatches go through `services/Hypr.qml` (the Lua config means
  `hyprctl dispatch` takes Lua expressions such as `hl.dsp.focus({ workspace = 3 })`).
- Quickshell has no generic DBus. Shell out with `Process` (nmcli, udisksctl,
  busctl, ddcutil...) or add a small relay in `helpers/` (python3 with
  dbus-python + gi is in the runtime PATH) that prints JSON lines.
- Give each Indicator an `ipcName` (set in `bar/MenuBar.qml` and
  `bar/PanelIndicators.qml`) so `hearth-ipc call indicator-<name> toggle`
  opens it. A new menu bar item also gets an entry (same id) in
  `services/BarItems.qml`'s catalog, which Settings > Menu Bar lists and
  the bar's order, show/hide and overflow come from.
- Runtime tools must be in `runtimeDeps` in flake.nix.

## API reference
Exact property/method names: the qmltypes under
`$(nix build --no-link --print-out-paths .#quickshell)/lib/qt-6/qml/Quickshell`.
Docs: https://quickshell.org/docs/v0.3.2/types/

## Testing
Never start Hyprland (Ben doesn't use it; a test Hyprland once leaked its
display into the real session). `scripts/test-session.sh start NAME` starts a
headless arbor (`ARBOR_BACKEND=headless`, its own HOME and private bus,
nothing on the real screen), then `run NAME` after each change (prints QML
warnings), `ipc NAME call indicator-x toggle` to open a popup, `msg NAME ...`
for `arbor msg` on that instance, `shot NAME out.png` for a 3840x1620
screenshot. `HEARTH_LAYOUT=panel` forces the classic panel. The script gives
the shell its own `XDG_CONFIG_HOME`/`XDG_CACHE_HOME`/`XDG_STATE_HOME` under
the session dir and sets `HEARTH_POLKIT=0`, `HEARTH_APPMENU_REGISTRAR=0`,
`HEARTH_SESSION_DRYRUN=1` (test runs share the real session bus; a test shell
must never become the polkit agent of Ben's login session: the agent is per
session, not per display). The tray shows the real session's apps.
Use your own NAME so parallel sessions don't collide; `stop NAME` when done
(it kills each daemon's whole process group, the shell's helpers included).
For a fully isolated run (private bus too) use `scripts/smoke-test.sh`.

## Git
Commit and push every working piece right away. Only stage your own files
(`git add <paths>`, never `-A` while others work in the tree).
