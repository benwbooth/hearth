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

## Impossible (no general way without patching the app)

| Group | Why | Examples |
|---|---|---|
| Run as root (pkexec) | Outside your session and its buses | GParted, Timeshift |
| GNOME-only | Refuses to start outside GNOME | GNOME Settings |
| JACK-only audio | Needs a JACK server to open a window | Calf |
| Self-drawn UI (GPU/canvas) | No accessibility tree, no menu export | Zed, Blender, Bforartists, Kodi, Neovide, Ardour, xemu's ImGui bar |
| FLTK, Tk, NTK | Toolkits without AT-SPI | TigerVNC, Nestopia, Maxima, ZynAddSubFX |
| .NET (Avalonia, WinForms on Mono) | No AT-SPI on Linux | Ryubing, KeePass 2, PKHeX |
| JavaFX | No AT-SPI on Linux | Cryptomator |
| Proprietary bundles | Their own Qt/GTK without accessibility | Adobe Reader, TeamSpeak 3, Minecraft Launcher |
| Qt Quick inside a QQuickWidget | Wrong widget positions, no press action on the ☰ | KDE System Settings, Info Center (both removed) |

## Open questions

1. **Java apps in Flatpaks** (JDownloader, Burp Suite, IntelliJ IDEA, CPU
   Info, TL): the bridge isn't loaded inside Flatpaks (the sandbox's JVM
   would load a host library built against another glibc, and a failure
   there ends the app). Leave them, or try per-app overrides after testing
   each?
2. **COSMIC/iced Flatpaks** (COSMIC Camera, fan-control, Startup
   Configuration, Writing Tools): like the COSMIC apps, only through
   hand-written modules per app. Write them?
3. **Wine front ends** (PortProton, WineCharm, WineZGUI) and the anime-game
   launchers: mostly first-run screens or web views; no general route yet.

## General fixes the survey produced (hearth/arbor)

Flatpak apps matched through their D-Bus proxy; GTK app actions and
shortcuts windows as menus; MPRIS Playback menu; Electron menus from the
app's own code; ☰ menus read unseen (arbor ProbeWindow), Qt popups by their
showing event, GTK 4 sliding submenus, Kirigami drawers (open or closed);
toolbars as an Actions menu; X11 windows read over AT-SPI (Java); the Java
ATK bridge; appmenu-gtk-module for GTK 2 and GTK 3; menu modules (mpv,
terminals, COSMIC); the system side as hearth.nixosModules.global-menu.
