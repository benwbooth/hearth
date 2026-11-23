# Every app with a menu gets a global menu

Goal (Ben, 2026-11-22): every app that has menus shows them in hearth's
menu bar, live. **The product is the runtime system:** hearth-appmenu
probes any running app, in the catalog or not, and builds the best menus it
can from what the app exposes. The checklist (`checklist.tsv`) walks the
whole app list (~4,900) to find where the runtime system falls short. Each
app that fails is a test case for a *general* mechanism that also covers
every other app like it. Per-app modules are the last resort, for what no
general mechanism can reach, and they mark a gap the runtime system should
eventually close.

Constraints:
- No patching of apps or packages, and no `LD_LIBRARY_PATH` or other
  per-app runtime injection.
- The logic lives in arbor and hearth.
- Tests are nested only (private bus, never the live session).
- Prebuilt packages only; nothing is compiled to test.

## Working through the list

For each app, in popularity order:
1. **Measure it:** the nested probe. What did the runtime chain find, and
   what does the app expose? (menu bar or ☰ on AT-SPI, exported actions,
   MPRIS, shortcuts in its resources, tray, D-Bus services)
2. **If it falls short, classify the gap,** not the app, e.g.:
   - "Kirigami global drawer not read"
   - "SWT menu bar exported empty until the workbench is up"
   - "media player without menus, has MPRIS"
   - "GTK4 shortcuts window not harvested"

   The checklist's `gap` column names it.
3. **Fix the gap generally** in hearth or arbor, re-run every app with that
   gap, and mark them `general:<mechanism>`.
4. **Only if no general mechanism can exist,** write a module, and note why.

## How an app is solved

1. **General solutions:** a route that covers a whole toolkit. Most apps
   inherit one with no per-app work, and the checklist marks them
   `general:<route>`.

   | Route | Covers |
   |---|---|
   | `dbusmenu` | Qt widgets, KDE, Chromium, Electron when it exports |
   | `gtk` | GtkApplication menu bars, appmenu-gtk-module (GTK3 bars, SWT, wx) |
   | `atspi` | Gecko, Electron's in-window bar, menus drawn in a web page, ☰ buttons, Flutter |
   | `gtk-actions` | Settings / Shortcuts / Help of libadwaita apps (hearth 96cba68) |
   | `flatpak` | the same routes through a sandbox's D-Bus proxy (hearth 96cba68) |

2. **Modules:** `menus/<app-id>.yaml`, the declarative per-app format in
   MODULES.md, for apps no general route reaches. A module can also extend a
   general route: a ☰-only app gets a macOS-style File/Edit/View laid out
   around its ☰ items. Written by an agent from the app's AT-SPI tree,
   screenshots, shortcuts and docs, then verified in a nested session.

3. **none-needed:** apps with no menus at all (dialog tools, games without
   menus). Recorded, so they don't stay "todo".

## The runtime chain (every window, catalog or not)

Any window, catalog or not, goes through the same chain in hearth-appmenu.
The first source that gives menus wins, and the route found is remembered
per app id (with its binary path), so the next window starts there.

1. **Native exports:**
   - dbusmenu: the window's KDE appmenu address, its X11 properties, or a
     RegisterWindow from its process (the sandbox's D-Bus proxy for a
     Flatpak)
   - GMenuModel: through gtk_shell1 or X11 properties.
2. **A module**, from the catalog or `~/.config/hearth/menus`.
3. **AT-SPI:** the app's in-window menu bar (kept, live, or drawn in a web
   page), else its ☰ button.
4. **GTK app actions:** Settings…, Keyboard Shortcuts, Help as the app
   menu.
5. **Tray icon menu** as the app menu.
6. **MPRIS** (to build): any media player on the bus
   (`org.mpris.MediaPlayer2.*`, matched by pid) gets a Playback menu:
   - Play/Pause, Stop, Next, Previous
   - Shuffle and Loop as checkmarks
   - Raise/Quit and the volume.

   It's live through PropertiesChanged.
7. **Harvested shortcuts** (to build): a generated menu from what the
   app documents about itself:
   - a GTK app's shortcuts window (`help-overlay.ui` /
     `AdwShortcutsDialog`), read from the binary's GResource with
     `gresource list /proc/PID/exe`: titles, groups, accelerators, action
     names
   - KDE `.rc` files
   - an Electron app's `Menu.buildFromTemplate` in its `app.asar`.

   Items are `gtk_action` where the action is exported, `keys` otherwise.
8. **"Make Menus for <App>…"** in the bold menu: the AI agent (MODULES.md
   §4) writes a module into `~/.config/hearth/menus`, tests it nested, and
   offers to publish it.

## Dynamic menus

Menus change while an app runs: recent files, enabled/disabled items,
checkmarks, plugins adding menus. Each route keeps up without polling.

- **dbusmenu:** `LayoutUpdated` / `ItemsPropertiesUpdated`, plus
  `AboutToShow` before a submenu opens. Already done.
- **GMenuModel:** `org.gtk.Menus Changed` and `org.gtk.Actions Changed`
  (enabled and state). Already done.
- **AT-SPI, kept trees (Gecko, GTK menus that keep their items):** subscribe
  to `object:children-changed`, `object:state-changed:{enabled,checked}` and
  `object:property-change:accessible-name` on the menu bar's subtree, and
  update just those items. To do in hearth-atspi-menu, which reads once and
  caches today.
- **AT-SPI, live trees (Electron, GTK4 popovers, ☰ menus):** the items only
  exist while the app's own popup is open, so there's nothing to subscribe
  to. Read them **when the user opens the menu in hearth's bar**, not on a
  timer:
  - titles come from the cache, so the bar shows at once
  - the submenu's items are read at open time, so they're always current.

  arbor makes the read invisible with a *probe freeze*. While hearth
  reads, arbor:
  - keeps showing the window's last frame and doesn't map the app's popup
  - still configures and acks the popup and sends frame callbacks
  - keeps keyboard focus away from it.

  Nothing flickers and no keys are lost. A timer (every 5–10 s) would open
  app popups constantly: keyboard grabs, Electron rebuilding menus, CPU
  wakeups. The read-on-open with a freeze gives fresh menus at no idle cost.
- **Modules:** a module's structure is static data. Its live parts are:
  - state expressions (`enabled`, `checked`, `visible`, labels), evaluated
    when the menu opens and kept current by the events above
  - `menu_from` sections (recent files, windows, bookmarks, the ☰'s current
    items), read live on open.
- **Staleness:** the cache is keyed by the app's binary path. A click on a
  missing item re-reads; a version change re-reads; a module whose
  selectors stop resolving is flagged "outdated" for regeneration.

## Work

1. **Measure everything:** done when the run finishes (~4,770 apps). It
   gives each app's status and toolkit, and `none` apps get triaged:
   - no menus at all → none-needed
   - menus the general routes miss → general fix or module.
2. **General fixes, biggest wins first** (ranked in the README once all
   numbers are in):
   - SWT: wait for the workbench
   - KDE apps exporting an empty menu bar (KSystemLog)
   - Flutter apps whose ☰ isn't found
   - AccessKit (iced, egui, Slint) when an app enables it
   - GTK4 shortcuts windows as menus
   - the arbor probe freeze.
3. **Module engine:**
   - arbor IPC `send-keys --window ID` (a virtual keyboard scoped to one
     surface)
   - hearth-appmenu loads `menus/*.yaml` and runs the action kinds in
     MODULES.md (keys, gtk_action, dbusmenu, atspi, menu_from), with live
     state.
   - `hearth-ipc call appmenu click <path>` for tests.
4. **Module per app:** a generation loop over the checklist's `todo` rows by
   popularity. An agent writes a module, tests it in a nested rig, and the
   checklist row becomes `module:<file>` / `done` with the date. This needs
   many agent runs (see the cost note in the README); start with the top
   300.
5. **Re-verify:** after each hearth/arbor change, re-run the probe on the
   `done` rows (regressions) and the affected `todo` rows.
