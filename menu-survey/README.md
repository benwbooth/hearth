# Global menu coverage survey

Can hearth's global menu bar show real menus for most desktop apps, and what
would close the gap? This folder holds the survey of nixpkgs and Flathub GUI
apps, the scripts that produced it, and the data. Nothing in hearth or arbor
was changed for it.

Date: 2026-11-22. nixpkgs: /etc/nixos's `nixpkgs` input (ab5c18f, 2026-11-20).
hearth: the installed build (`a6096d9` era: dbusmenu, GMenuModel,
appmenu-gtk-module, X11 properties/RegisterWindow, AT-SPI menu bars and ☰).

<!-- RESULTS -->

## Method

### 1. App list (`scripts/rank_apps.py` → `data/apps.tsv`)

- **nixpkgs:** every package that cache.nixos.org has built and that ships
  `share/applications/*.desktop` (nix-locate over the nix-index database:
  4,485 desktop files in 3,354 attrs). Each desktop file was read straight
  from the binary cache (`scripts/fetch_desktop.py`). An app needs one entry
  with `Type=Application` that isn't `NoDisplay`/`Hidden` and isn't a demo.
  `Terminal=true`-only packages are kept but marked `tui` and left out of
  the percentages, since the terminal's menu covers them.
- Unfree and uncached nixpkgs apps (Discord, VS Code, Chrome, Steam,
  Thunderbird...) come in through Flathub: a Flathub app that matches a
  nixpkgs attr (by homepage domain, or by name for unfree attrs, or through
  `data/manual_map.tsv`) is added with that attr.
- **Flathub:** every Flathub app with no nixpkgs counterpart is added as
  `flathub:<app-id>`.
- Duplicates (`foo-unwrapped`, `foo-esr`, version sets) collapse to one app.
  Libraries, daemons and desktop-shell parts that ship desktop files are
  listed with reasons in `data/not_apps.tsv`.

Result: 5,000 apps, 4,895 in the universe.

### 2. Popularity

There's no single source, so each one is turned into an estimated share of
Linux desktops that have the app installed:

| Source | Measure | Misses |
|---|---|---|
| Arch pkgstats (Oct 2026) | % of submitting systems | proprietary/AUR apps |
| Debian popcon | installs / submissions (not "vote": it needs atime) | Flatpak/AppImage installs; server-heavy |
| Flathub `installs_last_month` | mapped to % with a log-log fit against Arch over 731 apps in both | distro-packaged apps |

`pop` is the maximum of the three: each source undercounts a different set
of apps. Library packages (`gtk3`, `kio`, `cups`...) only get Flathub
numbers, so a library's install count can't make its demo app popular. The
coverage tables also show unweighted counts and Flathub-only weighting.
Desktop defaults (GNOME's and KDE's own apps) rank high because they're
installed with the desktop; that's real installs, not usage.

### 3. Static toolkit classification (`scripts/classify.py`)

Nothing is run or downloaded in full. For each app's store path:

- **Closure:** `nix path-info -r --store https://cache.nixos.org`.
- **Files:** `nix store ls -R`, for bundled `app.asar`, `libcef.so`,
  `libxul.so`, `libflutter_linux_gtk.so`, `.jar`.
- **Binary:** the first 4 MiB of the desktop entry's program, after
  following nixpkgs' shell wrappers and `makeBinaryWrapper` ELF stubs to
  the real ELF. `.dynstr` sits near the start of an ELF, so the needed
  libraries and imported symbols show there: `libQt6Widgets` vs
  `libQt6Quick`, `libKF6XmlGui`, `gtk_application_set_menubar` vs
  `gtk_menu_bar_new`, gtkmm's mangled `Gtk::Application::set_menubar`,
  `adw_application_new`, `libwx_gtk3u`, and so on.

The program's own links decide, and the closure only adds bundles: KDE apps
pull a JRE into their closure through dependencies, and Audacity pulls Qt.
Unfree packages with no cache entry use their derivation's inputs (Electron
in the inputs, or the nss+alsa+libdrm+gtk3 set of a bundled Chromium).
Flathub-only apps use their build manifest from github.com/flathub/<id>
(`scripts/classify_flathub.py`: Electron BaseApp, KDE or GNOME runtime,
openjdk extension...). `data/toolkit_overrides.tsv` fixes the few that
can't be read: Steam, VS Code, Zoom, Chrome-family, and uncached Kirigami
apps.

Usage: `scripts/classify.py STORE_PATH [EXEC]` for one app, or
`--apps data/apps.tsv --top N` for a batch.

### 4. Measured in a nested session (`scripts/menu-probe.py` → `data/probe*.jsonl`)

Every prebuilt nixpkgs app in the ranking, one by one:

- A nested arbor + the installed hearth on a **private session bus**
  (menu-rig.sh from the global-menu notes), never Ben's display or bus.
- An AT-SPI bus and registry on that private bus. at-spi-bus-launcher's
  dbus-broker can't activate the registry there, so the harness starts
  `at-spi2-registryd` itself.
- Apps run with the arbor session's environment: `GTK_MODULES`,
  `QT_QPA_PLATFORMTHEME=kde`, `QT_QPA_PLATFORM=wayland;xcb`,
  `ELECTRON_OZONE_PLATFORM_HINT=auto`, `DISPLAY` for xwayland-satellite, and
  a11y on. Each app runs in its own systemd scope, so a kill takes all of
  it.

For each app the harness:

- waits until the app's set of windows stops changing (splash screens), then
  focuses each new window and reads arbor's `app_menu`/`gtk_menu` and
  hearth's `appmenu dump`
- presses Escape once if a start screen is in front (Inkscape, GIMP's
  Welcome)
- when there's no menu, retries with the general levers for its toolkit,
  none of which patch the app:
  - Electron with libdbusmenu on its library path
  - `--force-renderer-accessibility`
  - X11 through xwayland-satellite
- infers the route: hearth's "x11" watch covers an X11 window, an Electron
  registration from a Wayland window's process, or AT-SPI
- saves a screenshot (`data/shots/`, not committed).

"Full" means two or more of the app's own top-level menus with items. "☰"
means one top-level menu, the app's primary or hamburger menu read over
AT-SPI.

<!-- STRATEGIES -->

<!-- MODULES -->

## Files

| Path | What |
|---|---|
| `scripts/fetch_sources.sh` | downloads popcon, pkgstats, Flathub; nix-locate list; nixpkgs meta dump |
| `scripts/fetch_desktop.py` | reads every desktop file from the cache → `data/desktop_entries.jsonl` |
| `scripts/rank_apps.py` | app universe + popularity → `data/apps.tsv` |
| `scripts/classify.py` | static toolkit classifier (reusable) → `data/classified.jsonl` |
| `scripts/classify_flathub.py` | Flathub-only apps from their manifests |
| `scripts/scan_shortcuts.py` | GTK4 apps that embed a shortcuts window → `data/shortcuts.jsonl` |
| `scripts/menu-probe.py` | nested per-app measurement → `data/probe*.jsonl` |
| `scripts/coverage.py` | the coverage tables |
| `data/manual_map.tsv`, `data/not_apps.tsv`, `data/toolkit_overrides.tsv` | hand-kept corrections, each with a reason |

To rebuild everything: `scripts/fetch_sources.sh && scripts/fetch_desktop.py && scripts/rank_apps.py && scripts/classify.py --apps data/apps.tsv --top 600 && scripts/classify_flathub.py && scripts/menu-probe.py --count 300 && scripts/coverage.py`.
