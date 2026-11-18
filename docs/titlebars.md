# Title bars

KDE-style title bars for every window, so Hyprland can be driven with the
mouse: a Breeze Dark bar with minimize / maximize / close on the right,
drag to move, double-click to maximize. They are drawn inside Hyprland by
the **hyprbars** plugin (nixpkgs `hyprlandPlugins.hyprbars` 0.55.0, built
against the same Hyprland 0.55.4 as the system), configured from
`hypr/titlebars.lua`.

| Piece | Where | Job |
|---|---|---|
| Plugin | `hyprlandPlugins.hyprbars` | draws the bar, hit-tests buttons, drag / double-click |
| Lua module | `hypr/titlebars.lua` | loads the plugin, Breeze look, buttons, window rules, actions |
| Optional patch | appendix below | left button only for move/buttons; middle- and right-click commands |

## Wiring

hyprland.lua:

```lua
-- Title bars (hyprbars; the plugin path comes from $HEARTH_HYPRBARS).
require("titlebars").setup()
```

/etc/nixos `home/hyprland.nix`, next to fanzyzones.lua:

```nix
xdg.configFile."hypr/titlebars.lua".source = "${hearth}/share/hearth/hypr/titlebars.lua";
# Read once when Hyprland starts (uwsm sources this file), so a rebuild
# never swaps the plugin under a running session.
xdg.configFile."uwsm/env-hyprland".text = ''
  export HEARTH_HYPRBARS=${pkgs.hyprlandPlugins.hyprbars}/lib/libhyprbars.so
'';
```

`pkgs.hyprlandPlugins.hyprbars` must come from the same nixpkgs as
`programs.hyprland.package` (it is built against that Hyprland; a mismatch
makes the plugin refuse to load with a "version mismatch" notification).
`setup({ plugin = "/path" })` overrides the variable; a package directory
works as well as the `.so`.

Why an environment variable and not a generated file: changing the plugin
path in a running session makes Hyprland unload one hyprbars and load
another on the next reload, and in testing that crashed Hyprland (SIGSEGV).
The variable is fixed for the session, so `nixos-rebuild` + reload keeps the
loaded plugin; a new one is picked up at the next login. For the same
reason don't drop `setup()` from the config and reload in a live session.

## How it loads (Lua config)

`hl.plugin.load(path)` only queues the path. After the config has run,
Hyprland loads queued plugins and runs the config again. On that first pass
`hl.plugin.hyprbars` and the `plugin.hyprbars.*` config keys don't exist
yet, so `setup()` queues the load and returns; on the second pass it sets
the options with `hl.config({ plugin = { hyprbars = { ... } } })` and adds
buttons with `hl.plugin.hyprbars.add_button({ bg_color, fg_color, size,
icon, action })` (the Lua form of the old `hyprbars-button = ...` line).
Reloads clear and re-add the buttons. No config errors on either pass.

The plugin runs button and double-click actions as shell commands, so they
come back into Lua as `hyprctl dispatch 'Titlebars.cmd("maximize")'`.
`hyprctl` is the one next to the running Hyprland binary
(`/proc/$PPID/exe`), so it works without hyprctl on PATH.

## Behaviour

| Input | Result |
|---|---|
| Minimize button | `hl.dsp.window.move({ workspace = "special:minimized", silent = true })`, as Super+PgDn |
| Maximize button, double-click on the bar | `hl.dsp.window.fullscreen({ mode = "maximized" })`, as Super+PgUp: fanzyzones' `window.fullscreen` handler macsimizes (own workspace after the current one) and restores |
| Close button | `hl.dsp.window.close()` |
| Drag the bar | Hyprland's move mode, as Super+drag; a tiled window floats under the cursor and fanzyzones snaps it back into the zone under the cursor |
| Middle click | lower (floating windows only) *with the patched plugin* |
| Right click | `custom>>titlebars menu <address> <x> <y>` on socket2 for a hearth window menu *with the patched plugin* (hearth doesn't draw that menu yet) |

Actions act on the active window; the plugin focuses the clicked window
before running them. `Titlebars.actions` / `Titlebars.cmd(name)` can be
used from binds or the shell too.

Look: 28 px bar, `#31363b` with `#fcfcfc` title when focused, `#202326` /
`#a1a9b1` unfocused (a dynamic `focus = false` window rule setting
`hyprbars:bar_color` / `hyprbars:title_color`), Noto Sans 13 px centred,
Hyprland's 1 px accent border drawn around bar and window together.
Buttons: `∨` `∧` on a transparent background and `✕` on a light circle,
like Breeze's close button. Limits of the plugin: no hover/pressed colours,
icons come from a font (no Breeze SVGs), the icon colour is picked from
the button background (Lua `fg_color` is ignored), and the close circle
stays bright on unfocused windows (`inactive_button_color` would recolour
every button).

### When there is no bar

- **Fullscreen** (internal state 2 or 3): `hyprbars:no_bar`. Hyprland
  doesn't draw decorations on fullscreen windows anyway; the rule also
  drops the reserved height. Maximized windows keep their bar, as in KDE.
  (`match = { fullscreen = true }` would also hit maximized windows, hence
  `fullscreen_state_internal`.)
- **Client-side decorations**: Hyprland offers server-side decorations
  through xdg-decoration and most toolkits accept: Qt/KDE apps (Konsole,
  Kate) and GTK4 apps without a header bar (pavucontrol) draw no title bar
  of their own and get a hyprbars bar, verified. Apps that always draw
  their own (GTK header bars / libadwaita, Firefox and Chromium with tabs
  in the title bar, Electron apps with a custom frame such as VS Code's
  default `window.titleBarStyle: "custom"`) would get two title bars.
  Hyprland exposes nothing that says a window uses CSD, so `M.csd_classes`
  lists them by class and a `hyprbars:no_bar` rule removes the bar
  (verified with Firefox: no bar, its own tab strip and buttons).
  Add classes with `table.insert(require("titlebars").csd_classes, "myapp")` before
  `setup()`, or `setup({ csd_bars = true })` to keep bars everywhere.
  weston-terminal always draws its own frame (it's only a test client).

## Testing

```sh
scripts/test-session.sh start bars
# append to $XDG_RUNTIME_DIR/hearth-test/bars/hyprland.lua (copy
# titlebars.lua and fanzyzones.lua next to it):
#   require("titlebars").setup({ plugin = "<hyprbars store path>" })
scripts/test-session.sh hyprctl bars reload
scripts/test-session.sh hyprctl bars configerrors
```

Clicks can be driven with `wlrctl pointer move/click` (nixpkgs `wlrctl`,
`WAYLAND_DISPLAY` of the nested Hyprland). Verified that way: double-click
maximizes into a new workspace (macsimize) and restores, minimize moves to
`special:minimized`, close closes, right-click on a button with the patched
plugin no longer triggers it and emits the menu event. Not verifiable with
wlrctl (click only, no press-hold): dragging the bar. wlrctl clicks don't
reach client surfaces either, so app content can't be clicked that way.

Known: `hyprctl reload` un-maximizes windows and leaves fanzyzones'
macsimize record behind (also without hyprbars; fanzyzones' business).

## Appendix: middle/right-click patch for hyprbars 0.55.0

Stock hyprbars treats every mouse button like the left one: right- or
middle-clicking a button presses it, and any button starts a move. This
patch keeps the left button for that and gives middle and right their own
`on_middle_click` / `on_right_click` commands (the event is swallowed on
the bar, passed through elsewhere). `titlebars.lua` sets them only when
the keys exist, so the stock plugin keeps working. Built and tested
against nixpkgs' hyprbars 0.55.0 / Hyprland 0.55.4:

```nix
HEARTH_HYPRBARS=${pkgs.hyprlandPlugins.hyprbars.overrideAttrs (o: {
  patches = (o.patches or [ ]) ++ [ ./hyprbars-buttons.patch ];
})}/lib/libhyprbars.so
```

`hyprbars-buttons.patch` (paths relative to the hyprbars directory):

```diff
diff -ru a/barDeco.cpp b/barDeco.cpp
--- a/barDeco.cpp
+++ b/barDeco.cpp
@@ -1,3 +1,4 @@
+#include <linux/input-event-codes.h>
 #include "barDeco.hpp"
 
 #include <hyprland/src/Compositor.hpp>
@@ -120,6 +121,13 @@
     if (!inputIsValid())
         return;
 
+    // Only the left button moves / presses buttons; middle and right run their
+    // own commands (KWin-style title bar actions).
+    if (e.button != BTN_LEFT) {
+        handleOtherButton(info, e);
+        return;
+    }
+
     if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
         handleUpEvent(info);
         return;
@@ -128,6 +136,37 @@
     handleDownEvent(info, std::nullopt);
 }
 
+void CHyprBar::handleOtherButton(Event::SCallbackInfo& info, const IPointer::SButtonEvent& e) {
+    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
+        if (m_otherButtonDown == e.button) {
+            info.cancelled    = true;
+            m_otherButtonDown = 0;
+        }
+        return;
+    }
+
+    if (m_hidden || m_bDraggingThis || !validMapped(m_pWindow))
+        return;
+
+    const auto HEIGHT = g_pGlobalState->config.barHeight->value();
+    const auto COORDS = cursorRelativeToBar();
+    if (!VECINRECT(COORDS, 0, 0, assignedBoxGlobal().w, HEIGHT - 1))
+        return;
+
+    const auto PWINDOW = m_pWindow.lock();
+    if (Desktop::focusState()->window() != PWINDOW)
+        Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);
+
+    info.cancelled    = true;
+    m_otherButtonDown = e.button;
+
+    const auto CMD = e.button == BTN_MIDDLE ? g_pGlobalState->config.onMiddleClick->value() :
+        e.button == BTN_RIGHT                ? g_pGlobalState->config.onRightClick->value() :
+                                               std::string{};
+    if (!CMD.empty())
+        Config::Supplementary::executor()->spawn(CMD);
+}
+
 void CHyprBar::onTouchDown(Event::SCallbackInfo& info, ITouch::SDownEvent e) {
     // Don't do anything if you're already grabbed a window with another finger
     if (!inputIsValid() || e.touchID != 0)
diff -ru a/barDeco.hpp b/barDeco.hpp
--- a/barDeco.hpp
+++ b/barDeco.hpp
@@ -92,6 +92,7 @@
 
     void handleDownEvent(Event::SCallbackInfo& info, std::optional<ITouch::SDownEvent> touchEvent);
     void handleUpEvent(Event::SCallbackInfo& info);
+    void handleOtherButton(Event::SCallbackInfo& info, const IPointer::SButtonEvent& e);
     void handleMovement();
     bool doButtonPress(Config::INTEGER barPadding, Config::INTEGER barButtonPadding, Config::INTEGER barHeight, Vector2D COORDS, bool BUTTONSRIGHT);
 
@@ -110,6 +111,7 @@
     bool                m_bTouchEv       = false;
     bool                m_bDragPending   = false;
     bool                m_bCancelledDown = false;
+    uint32_t            m_otherButtonDown = 0;
     int                 m_touchId        = 0;
 
     // store hover state for buttons as a bitfield
diff -ru a/globals.hpp b/globals.hpp
--- a/globals.hpp
+++ b/globals.hpp
@@ -35,7 +35,7 @@
         SP<Config::Values::CIntValue>    barPadding;
         SP<Config::Values::CIntValue>    barButtonPadding;
         SP<Config::Values::CBoolValue>   barBlur, barTitleEnabled, barPartOfWindow, barPrecedenceOverBorder, enabled, iconOnHover;
-        SP<Config::Values::CStringValue> barTextFont, barTextAlign, barButtonsAlignment, onDoubleClick;
+        SP<Config::Values::CStringValue> barTextFont, barTextAlign, barButtonsAlignment, onDoubleClick, onMiddleClick, onRightClick;
     } config;
 };
 
diff -ru a/main.cpp b/main.cpp
--- a/main.cpp
+++ b/main.cpp
@@ -246,6 +246,10 @@
     HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.enabled);
     HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.iconOnHover);
     HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onDoubleClick);
+    g_pGlobalState->config.onMiddleClick = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_middle_click", "Command to run on middle click of the bar", "");
+    g_pGlobalState->config.onRightClick  = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_right_click", "Command to run on right click of the bar", "");
+    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onMiddleClick);
+    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onRightClick);
 
     if (Config::mgr()->type() == Config::CONFIG_LEGACY)
         HyprlandAPI::addConfigKeyword(PHANDLE, "plugin:hyprbars:hyprbars-button", onNewButton, Hyprlang::SHandlerOptions{});
```
