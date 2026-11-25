# Global menu triage

What the survey couldn't make work, why, and what was decided. From
`checklist.tsv` (statuses `todo` and `blocked`), 2026-11-24, after the
general fixes listed at the end. App lists are examples, not exhaustive.

Every app still without a menu, by gap, with its route:
[TRIAGE-remaining.md](TRIAGE-remaining.md) (`scripts/checklist.py --triage`).

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

EFL apps (Enlightenment's Terminology, Ephoto, Evisum): EFL's AT-SPI bridge
starts only with both `ELM_ATSPI_MODE=1` and the a11y bus's
`org.a11y.Status.ScreenReaderEnabled` true (verified in the rig: Ephoto's
tree, buttons, check boxes, settings panel). ScreenReaderEnabled is
session-wide: it would also make Chromium, Electron and Firefox keep full
accessibility trees (CPU and memory in every such app). Waiting on Ben.

Generators in bulk (2026-11-25): gen-module.py over the 218 unsolved nixpkgs
apps without a tree gave modules for Terminology, Gmsh, Scid, Xcas (in
menus/); most others have no menu table with keys. Avalonia apps' access-key
modules (MSBuild Log Viewer, Libation) wait on a test: Avalonia draws an
empty window in the rig, so its Alt+letter navigation isn't verified.

Sound: the rig runs PipeWire (no devices, a dummy sink) with its PulseAudio
server and libjack, so apps that need a sound server or JACK start: Calf
(File, Add plugin), ptcollab, pulsemeeter. Your desktop has PipeWire's
PulseAudio but not its JACK (services.pipewire.jack.enable), so JACK apps
like Calf don't start there yet.

AppImages: Tauri apps check that their executable is under
"$TMPDIR/.mount_" (where the FUSE runtime mounts) whenever APPIMAGE/APPDIR
is set, and panic under appimage-run. Running appimage-run with
XDG_CACHE_HOME=$TMPDIR/.mount_cache extracts them there, which passes the
check: the ChatGPT desktop AppImage then shows its whole menu bar. AppImages needing
glibc 2.43 or host libraries run on menu-survey/appimage-run.nix
(unstable's appimage-run plus the missing libraries), which would fix them
for programs.appimage on the desktop as well.

ZynAddSubFX: nixpkgs' default build uses Zyn-Fusion (self-drawn OpenGL, no
keyboard menu commands); the module covers the FLTK/NTK builds
(`zynaddsubfx-fltk`, `zynaddsubfx-ntk`).

Still impossible: GNOME Settings (refuses to start outside GNOME), KDE System Settings and Info Center (Qt Quick in a
QQuickWidget: wrong positions, no press action; both removed).

Open (2026-11-25): GTK 3 apps whose ☰ is a classic GtkMenu (Catfish, Helvum's
GTK 4 button differs) don't open it in the rig: the accessible press and
arbor's synthetic click leave the button pressed but no popup maps. A
GtkMenu on Wayland needs a grab with a real input serial; whether arbor
grants it for synthetic input is the next thing to check (arbor side). These
show as "partial" (the ☰ found, unread).

## Proposed impossible (for Ben's triage, 2026-11-25)

Groups no general fix reaches, with why. Not decided: each needs your call.

| Group | Apps | Why |
|---|---|---|
| Other desktops' own parts | Spectacle (needs KWin), GNOME Settings (GNOME only), Cinnamon, Budgie Desktop, Budgie Control Center, Pantheon Gala | Shells and settings of another desktop: they refuse to run, or are a session, not an app. Proposal: not apps for this session (none needed) |
| Installers run as root | Calamares | Runs through pkexec, outside your session's buses; a one-shot installer. Proposal: none needed |
| Needs a real account | Nextcloud client, Jami, qTox, Syncthing GTK, Rare, Password Safe, ownCloud-style clients, Element-like Matrix clients (Schildi), Jellyflix, aMule, Ricochet Refresh, Nextcloud Passwords, Mukwa, Vite | Stop at a login screen; the main window comes after signing in. Mostly Qt/GTK, so the general route should apply after login, but the survey can't verify it. Proposal: "works after login, unverified" |
| Proprietary downloads that fail | VueScan, Todoist, QQ, MAX (Flathub) | Their Flatpak install downloads from the vendor and fails in the throwaway installation. Proposal: untestable |
| Needs PulseAudio's equalizer | qpaeq | Needs PulseAudio's module-equalizer-sink, which PipeWire doesn't provide. Proposal: impossible on PipeWire |
| Crash at start in the rig | GNOME Robots, asusctl's GUI, Nostalgia, pw3270, Myxer, xr-chaperone, windsend-rs, Loxodo, Freenukum | Crash before a window (hardware they look for, missing data). To be retested after the harness fixes; whatever still crashes would be proposed impossible |

## General fixes the survey produced (hearth/arbor)

Flatpak apps matched through their D-Bus proxy; GTK app actions and
shortcuts windows as menus; MPRIS Playback menu; Electron menus from the
app's own code; ☰ menus read unseen (arbor ProbeWindow), Qt popups by their
showing event, GTK 4 sliding submenus, Kirigami drawers (open or closed);
toolbars as an Actions menu; X11 windows read over AT-SPI (Java); the Java
ATK bridge; appmenu-gtk-module for GTK 2 and GTK 3; menu modules (mpv,
terminals, COSMIC); the system side as hearth.nixosModules.global-menu;
an X11 window's pid from the X server when it sets none (XRes: FLTK, AWT);
GTK 2 apps on AT-SPI (gail + atk-bridge); games recognized by their own
desktop Categories (Game with a genre), any toolkit. Survey harness:
Flatpaks share the portal's runtime dir (Chromium/Electron Flatpaks start).
Reader: named app-menu buttons ("Main menu (F10)", KDE dialogs' Help),
GTK 4 popovers' entries (deep, switches), a page's sidebar and header
actions (Kirigami: Arianna, KRecorder), page actions when a ☰ shows
nothing. Survey: login screens and other-desktop refusals classified from
the window's text. Generators: gen-module.py builds modules from Tk and
FLTK menu tables in source; Tk entries without keys through mnemonics.
