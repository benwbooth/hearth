# Global menu triage

What the survey couldn't make work, why, and what was decided. From
`checklist.tsv` (statuses `todo` and `blocked`), 2026-11-24, after the
general fixes listed at the end. App lists are examples, not exhaustive.

## Decided

| Group | Decision | Examples |
|---|---|---|
| Games (SDL, GLFW, own engines, LWJGL) | No global menu needed: their menus are in the game (Ben, 2026-11-23) | SuperTuxKart, Luanti, OpenTTD, Xonotic, Mindustry, Shattered Pixel Dungeon |
| Emulators with a Qt/GTK front end | Measured like any app; most work | Dolphin, melonDS, mGBA, DeSmuME, ares |
| Java Swing | Java ATK bridge loaded into every JVM, session-wide (Ben) | jadx, Sweet Home 3D, Freeplane |
| Terminals that draw themselves | Menu modules from their default shortcuts (Ben) | kitty, Alacritty, foot, WezTerm |
| COSMIC apps with a menu bar | Menu modules from their key bindings (nixpkgs builds libcosmic without accessibility) | COSMIC Files, Edit, Terminal |
| COSMIC apps without a menu bar | No menu needed | COSMIC Settings, Calculator, Examine, Forecast |
| Apps needing session services | The test rig starts them privately (Ben); measured like any app | GNOME Contacts, GNOME Terminal, Evolution |
| Tray-only apps | No menu needed: their menu is the tray icon's | Flameshot, KTeaTime, Sunshine |
| Apps with only a toolbar | Their toolbar buttons as an Actions menu | ScreenGrab |

## Decided 2026-11-24 (Ben)

| Group | Decision |
|---|---|
| Apps with no general route (root-only, self-drawn, FLTK/Tk, .NET, JavaFX, proprietary bundles) | Menu modules from each app's documented shortcuts, like the terminals |
| Java apps as Flatpaks | Try the Java bridge per app through a Flatpak override; keep it only where the app runs |
| COSMIC/iced apps from Flathub | Menu modules from their key bindings |
| Wine front ends and game launchers | Look at each past its first run for a readable route |

Why these have no general route:

| Group | Why | Examples |
|---|---|---|
| Run as root (pkexec) | Outside your session's buses (keys still reach the window) | GParted, Timeshift |
| Self-drawn UI (GPU/canvas) | No accessibility tree, no menu export | Zed, Blender, Kodi, Neovide, Ardour |
| FLTK, Tk, NTK | Toolkits without AT-SPI | TigerVNC, Maxima, ZynAddSubFX |
| .NET (Avalonia, WinForms on Mono) | No AT-SPI on Linux | Ryubing, KeePass 2 |
| JavaFX | No AT-SPI on Linux | Cryptomator |
| Proprietary bundles | Their own Qt/GTK without accessibility | Adobe Reader, TeamSpeak 3 |

Wine front ends and game launchers, looked at one by one (2026-11-24):

| App | Finding |
|---|---|
| An Anime Game Launcher (and its sister launchers) | GTK 4, readable; the first-run wizard is clicked through (Continue), then it downloads game components, which the offline test rig can't. Its main window gets the general ☰ route |
| TwinTail Launcher | Tauri (GTK + web view): readable, no menus: none needed |
| WineZGUI, WineCharm | Start with Wine's own prefix-setup dialog ("Wine"): Wine has no AT-SPI, nothing readable until it closes |
| PortProton | First start downloads its Wine components (DXVK, VKD3D-Proton) behind a progress window that doesn't register on the accessibility bus; its main window comes after. Like the anime launchers: measurable only after a full first run |

Still impossible: GNOME Settings (refuses to start outside GNOME), Calf
(needs a JACK server), KDE System Settings and Info Center (Qt Quick in a
QQuickWidget: wrong positions, no press action; both removed).

## General fixes the survey produced (hearth/arbor)

Flatpak apps matched through their D-Bus proxy; GTK app actions and
shortcuts windows as menus; MPRIS Playback menu; Electron menus from the
app's own code; ☰ menus read unseen (arbor ProbeWindow), Qt popups by their
showing event, GTK 4 sliding submenus, Kirigami drawers (open or closed);
toolbars as an Actions menu; X11 windows read over AT-SPI (Java); the Java
ATK bridge; appmenu-gtk-module for GTK 2 and GTK 3; menu modules (mpv,
terminals, COSMIC); the system side as hearth.nixosModules.global-menu.
