# hearth

A Quickshell desktop shell for Hyprland and arbor, replacing Ben's
Plasma panel: a macOS-style glass menu bar (with the focused app's global
menu on arbor) and auto-hiding, magnifying Dock, or the classic bottom panel;
launcher, task manager with live previews and badges, pager, system tray,
indicators for everything the Plasma tray did, Settings and Help windows.

- Layout and every option: Settings window (system menu → hearth Settings…,
  `hearth-ipc call settings open`), saved to `~/.config/hearth/settings.json`
  (`layout`: `"mac"` default or `"panel"`). Scripts: `hearth-ipc call settings
  set dock.size 64`.
- Compositor: `shell/services/Compositor.qml` picks Hyprland or arbor (via
  `$ARBOR_SOCKET`; `HEARTH_COMPOSITOR` overrides). On arbor include
  `arbor/hearth-layer-rules.kdl` for blur.
- Global menu (arbor + mac layout): `helpers/hearth-appmenu` owns
  `com.canonical.AppMenu.Registrar` (so Qt apps export their menus) and relays
  com.canonical.dbusmenu; the address comes from arbor IPC `Window.app_menu`.
- Help: the ? in the menu bar, `hearth-ipc call help shortcuts` (Super+/).
- Clipboard history (like Klipper): the clipboard icon in the menu bar or
  Super+V (`hearth-ipc call clipboard toggle`); kept by cliphist, fed by
  `wl-paste --watch helpers/hearth-clipboard store` (needs the compositor's
  data-control protocol). Settings > Clipboard. Vicinae's is on Super+Shift+V.
- arbor settings from the GUI (Settings > Displays, Keyboard, Keyboard
  Shortcuts, Window Rules; the arbor config itself is a read-only nix-store
  file): hearth writes `~/.config/hearth/arbor-{displays,keyboard,binds,rules}.kdl`
  (checked with `arbor validate` on a temp file first), which
  `arbor/config.kdl` includes optionally: displays before its output blocks
  (arbor takes the first block per output), the rest after their defaults.
  Displays apply over IPC at once, then a 15 s "Keep these settings?"
  prompt reverts unless kept (`hearth-ipc call displays keep|revert`).
- Hot corners (Settings > Hot Corners): invisible 1 px layer surfaces, only
  in corners that have an action. Sleep & Power: hearth runs swayidle
  itself under arbor with the chosen times (restarted on change); the power
  button runs `hearth-ipc call power button`.

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

## Look

hearth follows macOS 26 Tahoe ("Liquid Glass"). The numbers below are the spec;
Theme.qml holds them, so change them there.

**Sources.** The menu bar height comes from Apple's HIG ("The menu bar": 24 pt).
The Liquid Glass material is described in the HIG "Materials" page and the
WWDC25 sessions 219 and 310. Menu metrics come from Firefox's native-matching
Tahoe values (`nsCocoaWindow.mm` `GetMenuCornerRadius()` returns 12 pt on
Tahoe; `menu.css`/`popup.css`). Dock defaults come from macOS's `com.apple.dock`
(`tilesize` 48, `autohide-delay` 0.5 s). Reviews were used for the rest
(MacStories, Six Colors, 9to5Mac, MacRumors). Anything no source gives exactly
is marked as an estimate (est.).

**Scale.** 1 pt = 1.125 logical px (`Theme.pt`). Apple's 5K at 2x shows 109
pt per inch. Ben's 34" 5120x2160 at 4/3 shows about 122 logical px per inch.
So every pt value below keeps its physical size from a Mac.

**Type.** SF Pro when it is installed, otherwise Inter. Inter is about 4%
larger at the same size, so it is set at 0.962x.
- Menu bar, menus and Dock labels: 13 pt, which is 14.6 px for SF and 14 px
  for Inter.
- Tooltips, Control Center captions and menu section headers: 11 pt.
- Tracking: -0.6%, SF's -0.08 pt at 13 pt (Inter's dynamic metrics agree).
- Weights: menu titles regular, the app name bold, menu section headers
  bold, and the clock uses tabular figures.

**Menu bar.**
- Height: 24 pt (27 px).
- Default style: transparent, as in Tahoe. Items float on the wallpaper over
  a faint shade, lifted by a soft shadow. They turn white or black with the
  brightness of the wallpaper's top 4%.
- Other styles: "Glass" (macOS's "Show menu bar background") or "Solid".
- Title padding: about 9.5 pt on each side. The open title gets a capsule of
  white at 22% (black at 11% on light) that is 2 px inset vertically. There
  is no hover highlight (macOS has none).
- Status items: 31 px slots holding 17 px monochrome glyphs (template-image
  look). Apps' colour tray pictures keep their colours.
- Clock: "Fri Nov 20  4:50 PM" in the locale's date order, or 24 h
  (Settings).
- Control Center: the switch.2 glyph next to the clock.

**Menus.**
- Glass panel: 12 pt corners (continuous), 4 pt padding.
- Rows: 24 pt tall. Text is inset 10 pt, or 20 pt when the menu has a
  checkmark or icon column.
- Selection: filled with the accent colour, 8 pt corners (concentric:
  12 - 4), white text.
- Separators: 1 px, white 13% / black 11%, inset like the text, 9 pt total.
- Shortcuts: right-aligned in the secondary colour, written ⌃⌥⇧⌘ + key.
- Submenus: a chevron, and a 3 pt overlap with the parent.
- Disabled rows: about 27% opacity text.
- Behaviour (macOS):
  - Menus open on press. Press-drag-release picks an item.
  - Hovering another title while a menu is open switches to it instantly.
  - Keys: arrows, Return/Space, Esc, Home/End and type-ahead. Left/Right
    move between menu bar menus or into and out of submenus.
  - Submenus open after 120 ms of hover. A safe triangle keeps diagonal
    moves from switching them.
  - Choosing an item blinks it once (2 x 55 ms) before it runs.

**Glass** (`shaders/glass.frag`, used by `widgets/GlassFrame.qml` for every
pane):
- Tint over the compositor's blur. Menus are regular glass at 72-74% opacity
  in dark mode; the Dock is clearer at about 60%. Hyprland blur: size 8, 3
  passes, vibrancy 0.35, noise 0.015. arbor: saturation 1.6.
- Sheen in the top part.
- Lensing: light gathered along the edges, fading inwards over about 5 px.
- Specular rim: 1.6 px wide, lit from the top-left (light vector (-0.55,
  -0.83)), with a weaker reflection at the bottom-right.
- Hairline outline.
- Drop shadow: 26 px blur, 9 px down, opacity 0.27 dark / 0.17 light. It
  stays under Hyprland's `ignore_alpha` of 0.3 so the blur never spreads into
  it. On arbor without real glass the compositor draws the shadow instead,
  because its layer-rule blur covers the whole layer rectangle.
- Reduce transparency makes all glass solid.
- **Real glass (arbor).** arbor draws macOS 26 Liquid Glass itself: every
  visible GlassFrame reports its pane (window coordinates after transforms,
  effective opacity) through `services/RealGlass.qml`, which sends one
  `SetGlass` per window over arbor's IPC (a persistent socket in
  `ArborBackend.qml`, probed at connect), at most once per rendered frame
  (`afterAnimating`, coalesced per window) and only when something moved.
  Tooltips and previews (xdg pop-ups) go as `popup` shapes of their parent
  layer. arbor then refracts the backdrop under exactly those shapes:
  bending along the rim, dispersion, blur, vibrancy and a specular rim
  (arbor's ARBOR.md, "Liquid glass"). The shell drops its own sheen and
  edge lensing there, draws 55% of its tint (legibility), a faint rim,
  the outline and the drop shadow. Panes are regular glass; the Dock gets
  real glass too (its slab follows magnification and the auto-hide slide).
  The transparent menu bar stays unglassed (macOS 26); its Glass style gets
  real glass. Settings > Appearance: "Real glass (arbor)" on/off and "Glass
  strength". Hyprland is unchanged (compositor blur + shell glass).

**Dock.**
- Icons: 48 pt (54 px), spaced 17% of an icon.
- Slab: a third of an icon thicker than the icons, with corners at 38% of
  its thickness, floating 4 pt off the screen edge. Clearer glass, 30 px
  shadow.
- Separator: a hairline across 55% of the slab.
- Running dots: 4 pt, white in dark mode and black in light, in the slab's
  lower padding.
- Name label: a 13 pt glass capsule about 8 pt above the (magnified) icon.
- Magnification: cosine falloff over 2.6 icons. It eases in over 150 ms and
  out over 230 ms, and follows the pointer with no lag in between.

**Motion.**
- Menus and popovers: fade in over 160 ms, OutCubic, while scaling from 0.94
  at their anchor over 220 ms, OutBack with a slight overshoot. They fade
  out over 180 ms.
- Switching between open menu bar menus: no animation.
- Submenus: slide 6 px and fade over 120-160 ms.
- Menu bar auto-hide: slides in 250 ms, InOutCubic.
- Tooltips (help tags): appear after 800 ms (macOS is about 1 s), fade in
  over 110 ms and out over 160 ms.
- Dock label: fades in over 120 ms and moves to the next icon over 70 ms.
- Dock auto-hide: a 500 ms show delay (macOS `autohide-delay`) and a 300 ms
  slide, decelerating in and accelerating out. Both can be set in Settings
  > Dock.
- Launch bounce: half an icon high, 300 ms up (OutQuad) and 300 ms down
  (InQuad). It repeats until the first window appears, for at most 10
  bounces or 6 s. An app asking for attention bounces 3 times.

**Pointer.**
- macOS-style: the open apple-cursor theme `macOS` (black arrow, white
  outline) at size 28. Its arrow is 23 px, which is macOS's arrow size at
  1.125 px/pt.
- Breeze at 24 otherwise.
- Settings > Appearance > Pointer applies it live (`hyprctl setcursor`, or
  arbor's cursor block in `~/.config/hearth/arbor-input.kdl`). It needs
  `apple-cursor` in the system packages.
- `hypr/hyprland.lua` picks it for XCURSOR_THEME when it is installed.

**Not matched.**
- True refraction (the background bending at the edges) needs the backdrop
  as a texture, which a layer-shell client doesn't get. On arbor the
  compositor draws it (Real glass above); on Hyprland the compositor's blur
  plus the edge lensing highlight stands in for it.
- The Genie minimize effect is left to the compositor.
- SF Pro and Apple's cursors aren't shipped (Apple-licensed).
