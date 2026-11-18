# FanzyZones on Hyprland

A port of the KWin script from `~/src/fanzyzones-kde` (FancyZones-style
zones, macsimize, dynamic desktops) to Hyprland 0.55's Lua config. It has
three parts:

| Piece | File | Job |
|---|---|---|
| Hyprland side | `hypr/fanzyzones.lua` | the `lua:fanzyzones` tiled layout, drag tracking, keyboard snapping, macsimize, dynamic workspaces |
| Tray picker | `shell/bar/indicators/Zones.qml` | active layout as a tray glyph; popup with layout previews, options and a layout editor |
| Drag overlay | `shell/popups/ZoneOverlay.qml` | zone rectangles with numbers while dragging; highlights the zone under the cursor |

The Lua side and the shell share `~/.config/hearth/zones.json` (same keys as
the KWin script's `settingsJson`; seeded with Ben's layouts and settings).
Hyprland's Lua can't draw, so it tells the shell what to show through
socket2 `custom` events (`hl.dsp.event`), and the shell drives Lua through
`hyprctl dispatch 'FanzyZones.cmd(...)'`.

## Wiring it into hyprland.lua

```lua
-- Zones, macsimize and dynamic workspaces (hearth/hypr/fanzyzones.lua).
local fz = dofile(os.getenv("HOME") .. "/src/hearth/hypr/fanzyzones.lua")
fz.setup()          -- registers lua:fanzyzones, drag tracking, events
fz.bind_keys()      -- shortcuts below; bind_keys({ layout_keys = true }) adds SUPER+SHIFT+1..9
hl.config({ general = { layout = "lua:fanzyzones" } })
```

`require` only searches the directory of hyprland.lua, hence `dofile` with
the checkout path (or copy/symlink the file next to hyprland.lua and
`require("fanzyzones")`). If `hearth` is installed from the flake, point
`dofile` at wherever the package ships `hypr/fanzyzones.lua` instead.

To keep another layout as the default and use zones only on some
workspaces: `hl.workspace_rule({ workspace = "1", layout = "lua:fanzyzones" })`.
On non-zones workspaces snapping still works: the window floats and is
moved/resized onto the zone rectangle (what the KWin script did).

`setup()` options: `config_path`, `state_path`, `tick_ms` (drag poll,
default 16), `drag_binds` (default true; set false to skip the LMB and
modifier-key binds), `debug` (log to `$XDG_RUNTIME_DIR/hearth-fanzyzones.log`).

Config hints:
- `hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })`
  (in the stock example config) stops apps maximizing themselves; macsimize
  then only applies to your own `hl.dsp.window.fullscreen({ mode = "maximized" })`.
- `gaps_in`/`gaps_out` still apply on top of zones; zones.json `gap` and
  `outer_padding` add more (both 0 for Ben).

## How it behaves

**Zones layout.** Every tiled window on a `lua:fanzyzones` workspace has a
home zone (kept per window address). New windows take the next empty zone,
or the least crowded one; windows sharing a zone overlap, as in FancyZones.
Each monitor uses `display_layouts[monitor]`, else `default_layout`.
Switching layout keeps each window's zone number (clamped to the new count).

**Drag snapping.** Hyprland has no drag events, so the Lua side starts a
16 ms poll when a drag may begin (LMB pressed, the snap modifier pressed, or
a tiled zone window going floating — Hyprland floats tiled windows while
they're dragged) and stops it when the drag ends. A window keeping a fixed
offset from the moving cursor is being dragged.
- Tiled window (SUPER+LMB, or dragging a client-side title bar): the overlay
  shows and the drop lands it in the zone under the cursor.
- Floating window: with Shift held (`snap_mode: "modifier"`,
  `modifiers: ["shift"]`) the overlay shows and releasing the button tiles it
  into the highlighted zone; without Shift it stays a free floating window.
  `snap_mode: "auto"` snaps every floating drag.
- To free a window from its zone, float it (SUPER+V); Hyprland restores its
  last floating size. Un-floating puts it back in its old zone.

**Keys** (`fz.default_keys`, from the KWin script):

| Key | Action |
|---|---|
| Ctrl+Alt+Left / Right | previous / next zone for the focused window |
| Super+Ctrl+1..9 | snap focused window to zone N |
| Super+Shift+PgUp / PgDown | previous / next layout on the focused monitor |
| Super+Shift+Space | snap focused window to its nearest zone |
| Super+Space | snap all floating windows on the workspace |
| Ctrl+Alt+C | toggle the zone overlay |
| Super+Shift+1..9 | use layout N (opt-in: `layout_keys = true`; clashes with the usual move-to-workspace binds) |

Override or drop keys with `fz.bind_keys({ ["SUPER + Z"] = "snap_focused", ["SUPER + space"] = false })`.
Action names: `next_zone`, `prev_zone`, `zone N`, `layout N`, `next_layout`,
`prev_layout`, `snap_focused`, `snap_all`, `toggle_overlay`. On a zones
workspace `hl.dsp.layout("zone 2" | "next" | "prev" | "layout next")` works too.

**Macsimize** (`macsimize_fullscreen`, `macsimize_maximized`). Fullscreening
or maximizing a window that shares its workspace moves it to a new
workspace right after the current one (later workspaces shift up; with
`macsimize_move_to_last_desktop`, after the last one) and follows it.
Restoring moves it back and returns there; closing it returns to the
original workspace. Windows that open already maximized/fullscreen get the
same treatment. With `macsimize_exclusive_desktops`, a new tiled window
opening on a macsimized workspace is sent to the original one (floating
dialogs stay with their fullscreen parent).

**Dynamic workspaces** (`dynamic_workspaces`). Numbered workspaces are kept
contiguous: when one in the middle empties, the later ones move down
(the one you're looking at is kept until you leave it), and the workspace
after the last occupied one is made persistent so the pager always shows one
empty workspace at the end. With more than one monitor only the trailing
workspace is maintained (ids are global, so renumbering would move windows
between screens). `keep_empty_middle_desktops` disables the renumbering.

**Tray picker.** Glyph = active layout of that bar's display. Scroll on it
cycles layouts; right-click toggles the overlay. The popup lists every
layout (click a row to use it on the display; with several screens, pills
pick the display), click a zone in a preview to snap the focused window
there, toggles for Shift-snapping / overlay / macsimize / dynamic
workspaces, and "New custom layout…": a columns × rows editor taking
relative sizes (`1 2 1` columns and `1` row = the ultrawide 25/50/25).
Custom layouts get Edit/Delete. The KWin applet's free-form zone editor
(drag/split/resize zones) isn't ported.

**Shell commands** (`hyprctl dispatch 'FanzyZones.cmd(...)'`): `reload`,
`set_layout <monitor> <id|N|next|prev>`, `snap <zone> [address]`,
`preview <monitor> <zone>`, `hide`, `toggle_overlay`, `dump` (state to
`$XDG_RUNTIME_DIR/hearth-fanzyzones-debug.json`), and for headless tests
`sim_key <keysym> <0|1>` / `sim_button <0|1>`.

Runtime state (zones per window, macsimized windows, the trailing
workspace) is saved to `$XDG_RUNTIME_DIR/hearth-fanzyzones-<instance>.json`
so `hyprctl reload` (which rebuilds the Lua state) keeps it.

## Not ported from the KWin version

- Free-form layout editor (LayoutEditorWindow); per-zone app memory
  (`applications`); zone selector strip at the top of the screen; edge
  snapping; per-desktop layout tracking; restoring a floating window's
  pre-snap size on non-zones workspaces (Hyprland's own float-size memory
  covers zones workspaces).
- The nested "Trellis" workspace.

## Testing notes

Headless (`scripts/test-session.sh`), verified: zone placement and
next-empty-zone, keyboard/`cmd` snapping, layout switching (+ overlay
flash events), float-place on a dwindle workspace, macsimize/restore with
workspace shifting, trailing persistent workspace and renumbering, the
tiled-drag path (window floated and moved in lockstep with the cursor →
overlay show/hover events → drop into the zone under the cursor), the
Shift + floating drag path via `sim_key`/`sim_button`, the LMB bind firing
on a (virtual) click, the overlay rendering, and the picker popup rendering.
Not verifiable headless: a real SUPER+LMB / title-bar drag, real Shift key
binds (wtype's virtual keyboard doesn't trigger Hyprland binds), and clicks
inside the picker (virtual-pointer clicks don't reach Quickshell surfaces
in the nested session).
