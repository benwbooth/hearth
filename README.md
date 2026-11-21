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
- Global menu (arbor + mac layout): the focused app's menus in the menu bar,
  like macOS and Unity. See "Global menu" below.
- Spotlight (Super+Space), the voice assistant (Super+Alt+Space) and the AI
  hub (models, VRAM): see "Spotlight", "AI" and "Voice assistant" below.
  NixOS: `imports = [ hearth.nixosModules.ai ]; services.hearth-ai.enable = true;`
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
- Lock screen (hearth's own, macOS 26 style; `services/Lock.qml`,
  `lock/`; Settings > Lock Screen): ext-session-lock surfaces on every
  screen with the current wallpaper (videos and shaders keep playing, then
  slow to a still and blur when you start typing; Wallpaper Engine shows
  its preview), date and a big thin clock, now playing, the notification
  count, keyboard layout / network / battery glyphs, your AccountsService
  picture (or `~/.face`, else initials) and name, a glass password field
  on any key or click (shake on a wrong password, Caps Lock warning),
  "Touch the fingerprint reader", Sleep / Restart / Shut Down (the last
  two ask first). Other screens show the wallpaper and clock. Locks on
  Super+L / the menus / hot corners (`hearth-ipc call lock lock`), after
  the idle time (`hearth-session lock idle`, swayidle), before sleep
  (`hearth-session lock sleep --wait`, which holds sleep until the lock is
  up) and for logind's Lock signal (`loginctl lock-session`, swayidle's
  `lock` event). "Require password after" gives idle locks a grace period;
  the screens go dark after a minute without input while locked.
  - Authentication: two PAM conversations at once, as kscreenlocker does,
    because pam_fprintd blocks its stack until a finger is read: the
    password one (`hearth-lock`, else KDE's `kde`) when you press Return,
    and the fingerprint one (`hearth-lock-fingerprint`, else
    `kde-fingerprint`) for as long as the screen is locked. NixOS:
    ```nix
    security.pam.services.hearth-lock = { unixAuth = true; fprintAuth = false; };
    security.pam.services.hearth-lock-fingerprint = {
      unixAuth = false; fprintAuth = true;
      rules.auth.fprintd.args = [ "max-tries=10" ];
    };
    ```
    No pam_kwallet is needed: KWallet stays open while the screen is locked.
    The password is kept only until it is handed to PAM and never logged.
  - Safety: only a PAM success (or the grace period) unlocks; nothing
    else in the shell can. If hearth dies while locked, arbor keeps the
    session locked (a dead ext-session-lock client leaves the screens
    blank) and accepts a new locker. hearth leaves
    `$XDG_RUNTIME_DIR/hearth-locked-$WAYLAND_DISPLAY` while locked and
    locks again when it starts and finds it. To recover by hand: Ctrl+Alt+F2,
    log in, `hearth-recover-lock` (restarts hearth in the arbor session;
    `--hyprlock` takes over with hyprlock instead), back with Ctrl+Alt+F1.
  - hyprlock is only a fallback: `hearth-session lock` runs it when hearth
    doesn't answer IPC, and hearth starts it if the compositor never
    confirms its lock.
  - Tests: `HEARTH_LOCK_PAM_DIR=<dir>` uses PAM files from `<dir>`
    (pam_exec with a test password) and turns on the `lock` IPC calls
    `testType`, `testKey`, `testClick`, `testShot` (arbor takes no
    screenshots while locked). Never lock the real session from a test.
- Your picture and name (Settings > Users & Accounts,
  `popups/settings/UsersPane.qml`): your picture and full name on top, then
  macOS-style categories of built-in pictures (Animals, Nature, Flowers,
  Food & Drink, Sports & Hobbies, Space, Abstract) and monograms of your
  initials; "Choose a Photo…" opens a round crop with drag and zoom (saved
  at 512x512), "Take a Photo…" uses the webcam (Qt Multimedia, 3-second
  countdown) and then the same crop. Saving goes through
  `helpers/hearth-user`: AccountsService on the system bus
  (`FindUserByName` → `User.SetIconFile` / `SetRealName`; polkit lets you
  change your own account, `org.freedesktop.accounts.change-own-user-data`)
  plus a copy at `~/.face` (and `~/.face.icon` when that exists). The lock
  screen and the login screen read AccountsService first. On NixOS a
  `users.users.<name>.description` in the config wins over a name set here
  at the next rebuild.
  - Built-in pictures: `avatars/` (58 PNGs, 512x512, about 3 MB),
    installed at `$out/share/hearth/avatars` (`HEARTH_AVATAR_DIR` in the
    `hearth` wrapper; the greeter can use the same path) with `index.json`
    (`id, category, title, file, author, licence, source` per picture) and
    `CREDITS.md`. Only clean licences: Microsoft Fluent Emoji 3D (MIT,
    `LICENSE.fluentui-emoji`) on generated gradient tiles, NASA images
    (public domain) and Wikimedia Commons photos marked CC0, plus
    generated gradients; no KDE artwork, people or trademarks. The images
    are committed; `scripts/build-avatars.sh [ids]` rebuilds them from
    `scripts/avatars/manifest.tsv` (pinned Fluent commit, Commons page
    ids with each licence checked through the Commons API, crop centres),
    with hearth's locked nixpkgs (Pillow, pngquant, oxipng).
  - Tests: `HEARTH_USER_MOCK_DIR=<dir>` keeps `hearth-user` off the system
    bus and out of `$HOME` (the account lives in `<dir>`; the lock screen
    reads `<dir>/icons` too), `HEARTH_USER_MOCK_FAIL=<message>` makes
    saving fail, `HEARTH_USER_TEST_NOCAM=1` shows the camera UI without
    opening the webcam, and the `users-test` IPC target (`pick`,
    `monogram`, `crop`, `zoom`, `pan`, `saveCrop`, `camera`, `setName`,
    `status`) stands in for clicks.
- Screenshots and screen recording (our own Spectacle; Settings >
  Screenshots): Print opens the capture overlay (`popups/Screenshot.qml`):
  every screen frozen, Region (magnifier, handles, real-pixel size, last
  region remembered), Window (hover + click), Screen, All Screens, pointer
  and delay toggles, Screenshot / Record. Region and Screen without a delay
  crop the frozen frame, so open menus stay in the picture; windows come
  from arbor's `ScreenshotWindow` IPC (the window alone even when covered,
  `decorations`/`shadow` for the title bar and shadow, `clipboard: false`
  so arbor leaves the clipboard alone); screens and delayed regions from
  grim. The result window (`popups/ScreenshotEditor.qml`) previews it with
  annotations (arrow, rectangle, ellipse, freehand, highlighter, text,
  numbered stamps, blur, pixelate, crop, undo/redo), Copy, Copy Path, Save
  (auto-named into ~/Pictures/Screenshots, `vips` converts to JPEG/WebP),
  Save As, show in folder, and drag the picture into other apps. Recording
  uses wf-recorder (wlr-screencopy, 30 fps H.264 MP4 or VP9 WebM, sound
  optional); the menu bar shows a red timer that stops it. Keys: Print,
  Shift+Print (screen), Super/Alt+Print (active window),
  Super+Shift+Print / Super+Shift+S (region), Super+Shift+R (record),
  Ctrl+Print (arbor's quick region). IPC: `hearth-ipc call screenshot
  open|printKey|region|screen|all|activeWindow|record|stopRecording`;
  `screenshot-overlay` and `screenshot-editor` targets script the open
  overlay / window.

- Wallpaper (Settings > Wallpaper, `services/Wallpaper.qml`,
  `desktop/Background.qml`, `helpers/hearth-wallpaper`): hearth draws the
  wallpaper itself on a background-layer surface per screen and cross-fades
  every change (no swaybg/hyprpaper). Sources: Bing, NASA APOD, Wikimedia
  Commons, NASA Earth Observatory, NOAA live Earth (GOES), Windows
  Spotlight, Google Earth View, Simon Stålenhag, David Revoy, Wallhaven
  (SFW unless you add a key), Reddit (often refused without sign-in),
  Unsplash/Pexels/Flickr with your own free key (kept by `secret-tool` in
  KWallet, else `~/.config/hearth/wallpaper-keys.json`, 0600), each with a
  refresh interval and a history (Previous/Next). Also a picture, folder
  slideshows (interval, shuffle, subfolders), dynamic sets (GNOME timed
  XML and light/dark pairs, macOS `.heic` dynamic desktops via libheif:
  `h24`, `solar` and light/dark metadata, or a folder with
  `dynamic.json`: `{"frames": [{"file": "a.jpg", "time": "06:30", "fade":
  30}]}` or `{"light": "l.jpg", "dark": "d.jpg"}`), videos (QtMultimedia,
  VA-API decoding with zero-copy textures), GLSL shaders (4 built in,
  `shaders/wallpaper/*.frag`; add any Shadertoy `mainImage` shader without
  `iChannel` textures, compiled with qsb), and Wallpaper Engine projects
  (Steam libraries found from `libraryfolders.vdf`, played by
  `linux-wallpaperengine` on its own layer surface). Fill uses a libvips
  "attention" smart crop sized to each screen. Animation pauses on a screen
  covered by windows, everywhere while an app is full screen, when idle or
  locked, on battery (Wallpaper Engine gets SIGSTOP); "Still image only"
  turns it all off. IPC: `hearth-ipc call wallpaper next|previous|info|state`,
  `set '{"type":"shader","path":"builtin:aurora"}' [OUTPUT]`.
- Wallpaper for the lock and login screens: `~/.cache/hearth/wallpaper` is
  always the current still (a link), `~/.cache/hearth/wallpaper.json`
  describes it (`type`: potd/image/folder/dynamic/video/shader/we, `kind`,
  `path` still, `video`, `shader` (.qsb), `wallpaperEngine`, `fit`,
  `title`, `copyright`, `link`, `source`, `outputs` per screen). With "Show
  on the lock screen and login screen" on, the still (and a video under 1
  GB) are copied to `/var/lib/hearth/wallpaper/` (`wallpaper.<ext>`,
  `video.<ext>`, `wallpaper.json` pointing at the copies) for the greeter.
  NixOS creates that directory with
  `systemd.tmpfiles.rules = [ "d /var/lib/hearth 0755 root root -" "d /var/lib/hearth/wallpaper 2775 root users -" ];`
  hearth skips the copy while it's missing.

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

## Global menu

The focused app's menus sit in the menu bar after its name (arbor with the
mac layout). Pieces:

- `helpers/hearth-appmenu` owns `com.canonical.AppMenu.Registrar` (Qt,
  Chromium, Electron and appmenu-gtk-module only export menus while that
  name has an owner; Plasma's kded owns it in Plasma, so the helper leaves it
  alone when `XDG_CURRENT_DESKTOP` is KDE without arbor) and reads three
  kinds of menus into one tree for `bar/GlobalMenu.qml`:
  - com.canonical.dbusmenu: address from arbor IPC `Window.app_menu` (KDE
    appmenu Wayland protocol).
  - GMenuModel (org.gtk.Menus + org.gtk.Actions, as Unity read GTK apps):
    address from arbor IPC `Window.gtk_menu`, which arbor gets through GTK's
    `gtk_shell1.set_dbus_properties`. arbor advertises the `global_menu_bar`
    capability while the registrar name is owned, so GTK 3/4 hide the
    in-window menu bar of `GtkApplicationWindow`s exactly while hearth shows
    it (`global_app_menu` too: a GNOME 3 style app menu shows at the top of
    the bold app-name menu).
  - X11 windows (xwayland-satellite): for a window whose Wayland client is
    the satellite, the helper takes `_NET_ACTIVE_WINDOW` and reads its
    `_KDE_NET_WM_APPMENU_*` / `_GTK_*` properties with `xprop`, or the menu
    the app registered for that window id with `RegisterWindow`.
- `nix/appmenu-gtk-module.nix` (`.#appmenu-gtk-module`, linked into hearth's
  `lib/gtk-3.0/modules`): vala-panel's appmenu-gtk-module (ex
  unity-gtk-module) for GTK 3 apps with plain GtkMenuBars, loaded by
  `GTK_MODULES` in `arbor/config.kdl`. Patched to work on Wayland (register
  after realize, `run-on-wayland` on, its own schema copy) and without
  DT_NEEDED on GTK/GLib, so it can't drag a second GTK into apps built
  against another nixpkgs. It hides menu bars only while the registrar
  name is owned.
- Every app also gets the bold app-name menu (About, the GTK app menu, New
  Window, Close Window, Hide, Hide Others, Show All, Quit) and, unless its
  own menus have one, a Window menu (Minimize, Zoom, Enter Full Screen,
  Float, Move to Workspace, Bring All to Front, the app's windows).
- A window without menus of its own (a dialog, a second X11 window) shows the
  last menu seen for its app id, like macOS. Titles that would run into the
  status items are left out. While a hearth menu has the keyboard (arbor
  then reports no focused window) the menu bar keeps the app it had.

Coverage on arbor (tested in a nested arbor on a private session bus,
2026-11-20; "before" is hearth/arbor before this work):

| App / toolkit | Before | Now | How |
|---|---|---|---|
| Qt 5/6 widgets, KDE apps (KWrite, Konsole, Okular, KeePassXC) on Wayland | yes* | yes | dbusmenu via KDE appmenu protocol |
| Qt on X11 (`QT_QPA_PLATFORM=xcb`) | no | yes | `_KDE_NET_WM_APPMENU_*` on the X window |
| Qt Quick with `Qt.labs.platform` MenuBar | yes | yes | dbusmenu (QPlatformMenuBar) |
| Qt Quick with QtQuick.Controls `MenuBar` (earshot, Kog, almanac, tessera have none) | no | fallback | Qt 6.11 makes it native on macOS only; use `Qt.labs.platform` MenuBar to export |
| GTK 3 GtkApplication menu bar (gtk3-demo-application, LibreOffice gtk3) | no | yes | GMenuModel via gtk_shell1 |
| GTK 3 plain GtkMenuBar (tested with a PyGObject app; Emacs pgtk, Inkscape, virt-manager, meld expected) | no | yes | appmenu-gtk-module |
| GTK 3 on X11 | no | yes | `_GTK_*` properties |
| GTK 4 GtkApplication menu bar | no | yes | GMenuModel via gtk_shell1 |
| GTK 4 / libadwaita apps without a menu bar (most GNOME apps) | fallback | fallback | they have none (hamburger menus) |
| LibreOffice (gtk3 VCL; kf6 VCL in Plasma) | no | yes | its own GMenuModel export |
| Brave / Chrome / Chromium, Wayland | no | yes | Chromium's dbusmenu via KDE appmenu protocol (needs the registrar) |
| Brave / Chromium, X11 | no | yes | RegisterWindow on our registrar |
| Electron on X11 (VS Code/Cursor with `"window.titleBarStyle": "native"`, Slack, Teams, Spotify, ChatGPT app) | no | yes | RegisterWindow; Electron hides its in-window bar |
| Electron on Wayland (Claude Desktop, VS Code, Cursor by default) | fallback | fallback | Electron has no Wayland global menu; run with `--ozone-platform=x11` to get it |
| Firefox, Thunderbird | fallback | fallback | no global menu upstream (only distro patches) |
| JetBrains IDEs (X11 by default) | no | expected yes, untested | IntelliJ's own dbusmenu + RegisterWindow on X11 |
| Java Swing/AWT | fallback | fallback | no export without jayatana (not packaged) |
| Wine / Proton games and apps | fallback | fallback | Wine draws its menus in the window |
| Steam, games, SDL/GLFW | fallback | fallback | no menu bar |
| Ghostty, Warp, other custom-drawn apps | fallback | fallback | no exported menu |

"fallback": the app-name and Window menus only. *Before, the helper took
`XDG_CURRENT_DESKTOP=arbor:KDE` for Plasma and left the registrar to a kded
that arbor sessions don't run, so Qt menus only showed if something else
owned it.

Testing: `helpers/hearth-appmenu` speaks JSON lines on stdin/stdout (see its
docstring), so a second copy with `HEARTH_APPMENU_REGISTRAR=0` can watch and
click any menu on the bus; `hearth-ipc call appmenu dump` prints what the
menu bar has. Never run the registrar on the live bus from a test session.

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

## Spotlight

Super+Space or the magnifier in the menu bar (`hearth-ipc call spotlight
toggle`, or `search "TEXT"`) opens a liquid-glass field near the top of the
screen. Results come grouped: Top Hit, Applications, System Settings,
Actions, Documents, Folders, Images, Other, the calculator, web suggestions
(off by default) and "Ask hearth", with a preview of the selected one
(thumbnail, kind, size, date, where, a matching snippet).

- Keys: ↑ ↓ choose; Tab, Shift+Tab or ⌘↑ ⌘↓ (Super or Ctrl) jump between
  groups; Return opens; ⌘Return shows the file in the file manager (grove,
  through `org.freedesktop.FileManager1.ShowItems`); ⌘C copies a path or
  result; Esc clears the field, then closes.
- Search words: `kind:pdf|image|folder|document|music|video|spreadsheet`,
  `date:today|yesterday|week|month|year|2026-11-20`. The last word is a
  prefix, and every word matches file names as well as contents.
- Calculator and conversions (libqalculate's `qalc`): `2^10`, `15% of 80`,
  `5 ft to m`, `72F in C`, `100 USD in EUR`. Return copies the result.
- Never blocks the shell: apps, settings panes and actions are matched in
  memory; files, sums and web suggestions come from `helpers/hearth-search`,
  a long-running helper that answers in JSON lines and streams files in
  batches. Each keystroke supersedes the last query.
- Indexer: recoll (Xapian), packaged without its GUI in `nix/recoll.nix`.
  It was chosen over localsearch/tracker3 (GNOME), Baloo (KDE) and
  plocate/fsearch (names only, root-run updatedb). recoll is standalone,
  reads document contents through its filters, keeps kind and dates, has a
  Python API and watches folders with inotify. `hearth-indexer.service`
  (`nixosModules.ai`) runs `recollindex -m` with one thread at idle CPU and
  I/O priority, capped at 25% of a core and 512 MB (the converters it runs
  count too). It only works while you're away: hearth freezes the unit
  (systemd's cgroup freezer: no CPU, no disk) while you use the computer and
  thaws it after 3 idle minutes. It stays frozen while a video or game holds
  an idle inhibitor, while anything is full screen, and on battery
  (Settings > Spotlight: "Only index while I'm away", "Away for", "Index on
  battery", "Index Now"). Measured on 190,000 files (103 GB of documents):
  the first full pass with contents took 10 minutes of one core uncapped
  (about 40 minutes of away time at the cap), peaked at 150 MB of RAM and
  made a 2.9 GB index. After that it only reads changed files, which reach
  the index within 2 s of being read. Config:
  `~/.config/hearth/recoll/recoll.conf`, written from Settings > Spotlight
  (folders, Privacy exclusions, contents on/off, hidden files); index in
  `~/.cache/hearth/recoll`. recollindex notices config changes by itself.
- Motion (macOS 26 Spotlight, matched by eye from recordings; est.): the
  field springs in from 92% with a slight overshoot while it fades in
  (340 ms OutBack, fade 180 ms). The results pane grows under it (220 ms
  ease-out). Closing fades and shrinks to 97% (160 ms).

## AI

One hub for every model the desktop uses: `helpers/hearth-ai`,
`services/Ai.qml`, Settings > AI and the AI item in the menu bar.

- Backends: Ollama (the system's `services.ollama`), llama.cpp
  (`hearth-llama-server.service`: llama-server in router mode over a models
  folder, Vulkan build; started and stopped from Settings > AI), any other
  running `llama-server` (found by its process; usable, and stoppable to
  free memory), and the coding-agent CLIs Claude Code, Codex and Gemini.
  The CLIs are cloud AI. They are off unless "Allow cloud AI" is on, and
  they run one prompt at a time without their own tools.
- Models: installed and loaded per backend, with parameters, quantisation,
  size and capabilities. You can load, unload, download (Ollama names) and
  delete (asks first). Models stay loaded for the "Keep models loaded" time
  and can be unloaded whenever something goes full screen.
- Graphics memory: used/total per GPU from amdgpu's sysfs, and per process
  from DRM fdinfo (`drm-memory-vram`). The helper polls every 2 s while a
  view shows it, otherwise every 30 s.
- Assistant: the model in Settings > AI > Assistant (default Ollama
  `qwen3.5:4b`) gets tools: search files (through hearth-search), open or
  reveal a file, launch an app, set or change the volume (wpctl), desktop
  actions (lock, sleep, dark mode, Do Not Disturb, screenshot, show desktop,
  overview, next wallpaper, brightness, open a Settings pane), the weather
  (hearth's Open-Meteo data), calculate, and web search or open a URL in the
  browser. Shell-side tools run in the shell; the rest run in the helper.
- `hearth-ai --state` prints everything; `hearth-ipc call ai state|unloadAll`.

## Voice assistant

Super+Alt+Space or the microphone in the menu bar: speak, and it stops by
itself after a second of quiet (press again to stop early). Like Siri, a
glow of shifting colour runs along the screen edges and swells with your
voice (`shaders/siri.frag`), and a glass card under the menu bar shows what
it heard, each step it took, and the answer.

- Speech to text: `helpers/hearth-voice` streams the microphone
  (`pw-record`, 16 kHz) to whisper-typer's WhisperLive server
  (`ws://127.0.0.1:9090`, GPU), so no second Whisper is loaded. The
  language, model, pause length and server are set in Settings > Voice
  Assistant. Nothing is recorded while it isn't listening, and there is no
  wake word.
- Understanding and actions: the assistant above (Settings > AI).
- Spoken replies (off by default): Piper, with voices downloaded from
  rhasspy/piper-voices into `~/.local/share/hearth/piper` from the Settings
  pane.
- Spotlight's "Ask hearth" row sends the typed text to the same assistant.
- `hearth-ipc call voice toggle|start|stop|cancel|ask "TEXT"|state`;
  `HEARTH_VOICE_INPUT=file.wav` replaces the microphone (tests).

## Login screen

hearth's own login screen, macOS style, replacing SDDM (`shell/greeter.qml`,
`shell/greeter/`, `nix/greeter.nix`). greetd starts a greeter-only arbor as
the `greeter` user, and arbor runs `hearth-greeter` (Quickshell's Greetd
service) in it. It looks like the lock screen and shares its pieces
(`lock/LockGlass.qml`, `lock/LockButton.qml`, `desktop/StillLayer.qml`):

- the wallpaper hearth copied to `/var/lib/hearth/wallpaper` (still, video
  or shader; Settings > Wallpaper > "Show on the lock screen and login
  screen"), else a built-in gradient (or `services.hearth-greeter.wallpaper`);
  it slows to a still and blurs once you type;
- date and the big thin clock;
- one person: picture, name and the glass password field straight away;
  several: a row of pictures (arrow keys + Return, or click), then the
  field, with "Other Users" (Esc) to go back. Pictures and real names come
  from AccountsService (the greeter can't read anyone's home), else one of
  hearth's built-in pictures (`share/hearth/avatars`, the same one for a
  name every time), else initials;
- a wrong password shakes the field and says so in plain words; Caps Lock
  shows ⇪ and "Caps Lock is on"; locked or expired accounts get their own
  message;
- the desktop session under the field (a menu when there are several:
  arbor, Plasma, ... from `services.displayManager.sessionData.desktops`);
  each person's last user and session are remembered in
  `/var/cache/hearth-greeter/state.json`;
- keyboard layout (when there are several) and Accessibility (Zoom In /
  Zoom Out / Actual Size, also Super+Alt+= / − / 0) at the top right;
- Sleep / Restart / Shut Down (the last two ask first), through logind,
  which polkit allows for the active local session; refused while someone
  else is still logged in, with a message.

The session starts with `XDG_SESSION_TYPE=wayland`, its `DesktopNames` as
`XDG_CURRENT_DESKTOP`, and `XDG_SESSION_DESKTOP`/`DESKTOP_SESSION`; greetd
sources `/etc/profile` and `~/.profile` first. The screens go dark after 5
minutes without input.

Displays and keyboard: hearth copies `~/.config/hearth/arbor-displays.kdl`
and `arbor-keyboard.kdl` to `/var/lib/hearth/greeter/` whenever they
change (Settings > Displays / Keyboard; `services/ArborConfig.qml`), and
the greeter's arbor includes them, so it starts in your resolution, scale
and layouts. Before the first copy (or without it): each screen's
preferred mode, arbor's automatic scale, HDR off;
`services.hearth-greeter.extraArborConfig` adds output blocks.

NixOS (hearth flake input):

```nix
imports = [ hearth.nixosModules.greeter ];
services.hearth-greeter.enable = true;   # turns SDDM off (mkForce)
```

The module enables greetd (VT 1, `default_session` = the greeter arbor as
`greeter`), the `greetd` PAM service with pam_kwallet (KWallet unlocks
with the login password, as with SDDM) and without fingerprint (the
password is needed for KWallet, like macOS's first login after a restart),
AccountsService, and `/var/lib/hearth/{wallpaper,greeter}` (2775 root:users)
and `/var/cache/hearth-greeter` (greeter's). Options: `defaultSession`
(else `services.displayManager.defaultSession`, else arbor), `wallpaper`,
`extraArborConfig`, `cursorTheme`, `kwallet`, `environment`, `package`,
`arborPackage` (default `programs.arbor.package`).

Back to SDDM: remove `services.hearth-greeter.enable = true;` and rebuild.

If it fails at boot (black screen, or the greeter keeps restarting):
Ctrl+Alt+F2, log in on the text console, set
`services.hearth-greeter.enable = false;` in /etc/nixos, and
`sudo nixos-rebuild switch` (or `sudo nixos-rebuild switch --rollback`);
`sudo systemctl restart display-manager` then brings SDDM back. Or pick the
previous generation in the boot menu. Logs:
`/var/cache/hearth-greeter/greeter.log` (arbor), `shell.log` (the greeter;
`*.old` for the start before), `journalctl -b -u greetd`. A greeter that
crashes is restarted up to three times, then arbor quits and greetd starts
it again.

Testing: a NixOS VM test (greetd + arbor + greeter, a test user) drives it
with QEMU key and mouse events and takes screenshots with grim (arbor
needs a real GPU: virtio-vga-gl with `-display egl-headless`, so the test
driver runs outside the Nix sandbox). `HEARTH_GREETER_DRYRUN=1` logs
instead of launching or powering off; with `HEARTH_GREETER_TEST=1`,
`quickshell ipc -p .../greeter.qml call greeter state|shot PATH`.

## Boot

`boot/` holds matching boot visuals, built from source (logos rendered from
nixos-icons' SVG with resvg, GRUB fonts made from Inter with grub-mkfont):

- `packages.x86_64-linux.plymouth-theme-hearth`: Plymouth theme `hearth`
  (script plugin). Black screen, a flat white NixOS snowflake (0.094 x screen
  height, fading in over 0.5 s), a thin rounded progress bar under it
  (0.205 x height wide, white over a 24% track, eased so it glides), all
  macOS boot proportions. A disk passphrase request swaps the bar for a
  FileVault-like pill field with white dots and an "Enter Password"
  placeholder; the disk's own prompt sits small above it. Shutdown and
  reboot show only the logo. Boot messages stay hidden: Esc toggles
  plymouth's text view. Images come in size ladders (logo every 8 px from 48
  to 512, pill caps, dots), so the script never scales a bitmap and stays
  sharp at any resolution; set `DeviceScale=1`.
- `packages.x86_64-linux.grub-theme-hearth`: GRUB theme after macOS's Startup
  Manager. Dark background, centred list of large icons with Inter labels, a
  rounded glass box on the selection, a small countdown and key hints at the
  bottom. Icons by GRUB class: `nixos` (colour snowflake), `submenu` (the
  "All configurations" list), `windows` (os-prober's Windows Boot Manager),
  `efi`/`uefi-firmware`, and `os` for anything else. GRUB can't scale fonts,
  so sizes are baked for 3840x1600; `grub-theme-hearth-5k` is the same at
  5120x2160 (`mkGrubTheme { scale = height / 1600; }` in `boot/default.nix`
  for others).
  GRUB's `boot_menu` only lays items out vertically, so macOS's horizontal
  row of disks becomes a centred column.
- `packages.x86_64-linux.boot-screenshots`: a NixOS VM test (OVMF -> GRUB ->
  Plymouth at 3840x1600, with fake Windows and firmware entries) that saves
  screenshots of the GRUB menu, the splash and the password prompt to
  `result/`. Nothing touches the host's bootloader.

Use in /etc/nixos:

```nix
boot.loader.grub.theme = inputs.hearth.packages.${system}.grub-theme-hearth;
boot.plymouth.theme = "hearth";
boot.plymouth.themePackages = [ inputs.hearth.packages.${system}.plymouth-theme-hearth ];
boot.plymouth.font = "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf";
boot.plymouth.extraConfig = "ShowDelay=0\nDeviceScale=1\n";
```
