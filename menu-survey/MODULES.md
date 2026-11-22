# Menu modules: AI-written menus for apps that export none

The idea (Ben's): for an app that exports no menus, the user presses **Make
Menus for "<App>"…** in hearth's bold app-name menu. An AI agent inspects the
running app and writes a small declarative **module** that maps a macOS-style
menu bar to the app's real actions. hearth runs the module from then on.
Modules go into a shared catalog, so the next person with that app gets its
menus without running an agent.

The survey (README) puts this at the tail. It's for apps where no general
route works: Wine, CEF, Flutter, SDL/game launchers, custom-drawn, Kirigami
apps with only a drawer, and GTK4 apps whose shortcuts aren't machine
readable. It also adds a macOS-style File/Edit/View layout on top of a bare
☰ menu.

## 1. Module format: data, not code

A module is one YAML file (JSON-compatible; JSON Schema in
`schema/menu-module.schema.json` once built). It contains no scripts, no
shell commands and no expressions.

Why data:

- **Safety:** hearth runs a closed set of action kinds that it implements
  itself and aims only at the focused app (§2). A catalog module can't run
  code, read files or reach the network, so installing one is like
  installing a theme, not a plugin.
- **Review:** a diff of a YAML menu is readable by anyone. A diff of a
  script needs a security review.
- **Generation:** models fill a strict schema reliably. The validator
  rejects anything else, and the agent loop fixes what it rejects.
- **Testing:** every item's selector and key can be checked mechanically in
  a nested session (§4). Code can't be checked short of running it.
- **Durability:** the schema stays stable while hearth's internals change.
  The same module works in a future hearth, or in another shell that
  implements the same format.
- **Layering:** a user's local override merges with the catalog module item
  by item, by `id`.

### Example

```yaml
schema: hearth-menu-module/1
id: org.gnome.TextEditor
version: 3                       # module revision (catalog bumps it)
app:
  match:                         # any of these identifies the app
    app_id: [org.gnome.TextEditor]
    desktop: [org.gnome.TextEditor.desktop]
    flatpak: [org.gnome.TextEditor]
    nixpkgs: [gnome-text-editor]
  versions: ">=47 <52"           # app versions the module was tested on
  locales: [en]                  # accessible names below are English
provenance:
  generator: hearth-menu-agent 0.1 / claude-opus-5-5
  inputs: [atspi, gtk-actions, shortcuts-window, help-docs]
  tested: { hearth: "2026-11-22", app: "51.0", result: pass }
menus:
  - title: File
    items:
      - { id: new, label: New, shortcut: Ctrl+N, do: { keys: Ctrl+N } }
      - { id: new-window, label: New Window, shortcut: Ctrl+Shift+N, do: { gtk_action: app.new-window } }
      - { id: open, label: Open…, shortcut: Ctrl+O, do: { keys: Ctrl+O } }
      - separator
      - id: save
        label: Save
        shortcut: Ctrl+S
        do: { keys: Ctrl+S }
        enabled: { atspi: { role: push button, name: Save, state: sensitive } }
      - id: print
        label: Print…
        shortcut: Ctrl+P
        do:
          atspi:                 # open the ☰ menu, click "Print…"
            - { role: toggle button, name: Main Menu }
            - { role: menu item, name: Print… }
  - title: View
    items:
      - id: wrap
        label: Wrap Lines
        checked: { gtk_state: win.wrap-text }
        do: { gtk_action: win.wrap-text }
  - title: Help
    items:
      - { id: shortcuts, label: Keyboard Shortcuts, shortcut: Ctrl+?, do: { gtk_action: app.shortcuts } }
      - { id: about, label: About Text Editor, do: { gtk_action: app.about }, place: app-menu }
```

### Action kinds (the whole list)

| Kind | Does | Aimed at |
|---|---|---|
| `keys: "Ctrl+Shift+S"` | arbor delivers the key chord to **that window** (new arbor IPC action `send-keys --window ID`; virtual keyboard scoped to one surface) | the focused window only |
| `gtk_action: app.x` / `win.x` (+ `param`) | `org.gtk.Actions.Activate` on the app's application/window object path | the bus name arbor got through gtk_shell1 (needs arbor to keep the address without a menubar, strategy S2) |
| `dbusmenu: [labels…]` | `Event clicked` on an item of the app's own exported menu, found by label path | the window's app_menu / registration |
| `atspi: [selector…]` | find an accessible (role, name, index, path) in the window's tree, step by step (open a ☰ first), then `doAction(0)` | the AT-SPI application whose pid owns the window |
| `menu_from: {atspi: selector}` | a submenu whose items are read live from an app menu (recent files, open windows, ☰ contents) | same |
| `open_help: url` | opens a documentation URL (https only, or the app's own `file:///…/share/help`) | the default browser |

State expressions (`enabled`, `checked`, `visible`) use the same sources: an
AT-SPI state, a GTK action's enabled or state from `org.gtk.Actions
Describe`, or a dbusmenu item's state. An item without one is always
enabled.

There's deliberately no `run`/`exec` and no arbitrary D-Bus call. If a
real case comes up that needs a D-Bus call, it gets a typed kind with a
fixed interface (e.g. MPRIS `Play`), not a generic call.

## 2. How hearth runs modules safely

- **Matching:** hearth-appmenu loads modules for a window whose own routes
  gave nothing, or "fallback" plus ☰ only. It matches by app_id, desktop id
  and Flatpak id; for Nix it maps the pid's `/proc/PID/exe` store path to
  the attr. A module with `versions` that don't include the running version
  (from the store path name, the Flatpak commit or the desktop file's
  `X-AppVersion`) is still shown, marked untested.
- **Scope:** every action resolves its target from the focused window: the
  window's pid, the D-Bus name owned by that pid, the AT-SPI application
  with that pid. Nothing goes to another process. `keys` is delivered by
  arbor to that surface only, and never while a hearth menu or a lock
  screen has the keyboard. hearth closes its menu first, then sends.
- **No privilege:** it runs in the existing helper processes:
  `hearth-appmenu` for D-Bus, `hearth-atspi-menu` for AT-SPI. There's no
  new interpreter and no file or network access from module content. A
  module is parsed against the schema with unknown keys rejected, and size
  is capped at 256 KB with at most 2,000 items.
- **Trust labels:** each module shows where it came from in the bold menu,
  with the item "Menus from catalog (verified)" / "(community)" / "(local)"
  and a toggle to turn it off for that app. Verified means it passed the
  catalog's CI on that app version and a human reviewed it.
- **Failure:** an action whose target doesn't resolve shows an inline error
  under the menu bar ("Print… not found in Text Editor"). It's counted, and
  after repeated misses the item is greyed out with "module outdated", which
  invites a regenerate.

## 3. Catalog: sharing and versions

- **Repository:** a public git repo, e.g. `hearth-menus`:

  ```
  apps/<app-id>/module.yaml
  apps/<app-id>/tests/*.yaml
  apps/<app-id>/shots/*.png
  schema/
  index.json
  ```

  `index.json` is generated by CI and maps every match key (app_id,
  desktop id, Flatpak id, nixpkgs attr) to a file, its sha256, version and
  trust label.
- **Distribution:** hearth fetches `index.json` from a pinned URL. It checks
  a signature on the index with an SSH or minisign key that ships in
  hearth, then fetches only the modules for installed apps and caches them
  under `~/.cache/hearth/menus/`. The fetch happens no more than daily and
  never blocks the UI. It's also packaged as a Nix input (a flake with the
  repo as data), so a NixOS config can pin it like any other input and
  `nix flake update` brings new modules.
- **Local layers:** `~/.config/hearth/menus/<app-id>.yaml` (the user's own
  or agent-made) overrides the catalog item by item by `id`, and
  `hide: true` removes an item. "Publish…" opens a PR with the local module
  from the user's GitHub account. Nothing is sent without that click.
- **Versions:** `schema` (format major version; hearth reads 1.x),
  `version` (module revision, monotonically increasing), and `app.versions`
  (tested app range). An app update outside the range keeps the module,
  marked untested, and queues a CI re-test. A module can be split by range
  when an app redesign changes its UI: `module.yaml` + `module@<52.yaml`.
- **Locales:** AT-SPI names are localized. A module stores the English names
  plus `names: { de: …, fr: … }` per selector when known. Otherwise hearth
  matches by role + index path, and the CI test runs in each listed locale.
  `keys` and `gtk_action` don't depend on the locale; prefer them.

## 4. The agent and testing a module in a nested session

**Agent run:** `hearth-menu-agent <window-id>`, started by the menu item. It
uses any configured provider: Claude, Codex, Gemini, Grok, opencode, or a
local OpenAI-compatible endpoint (llama.cpp, Ollama), whatever hearth's AI
settings name.

It's given read-only tools. Each one only reads:

- `atspi_tree(window)`: roles, names, states, actions, key bindings; ☰
  menus opened and read the way hearth-atspi-menu already does
- `screenshot(window)`: the window only, via arbor
- `gtk_actions()`: `org.gtk.Actions DescribeAll`, app and window
- `dbusmenu()`: the app's exported menu, if partial
- `shortcuts()`: harvested from the app's GResource shortcuts window
  (`GtkShortcutsWindow`/`AdwShortcutsDialog`), KDE `.rc` files, an Electron
  app's `Menu.buildFromTemplate` in `app.asar`, and man pages
- `docs()`: `share/help`, the AppStream description, and the upstream docs
  URL from AppStream
- `catalog_lookup()`: modules for similar apps, as style examples.

It writes `module.yaml`, then calls `validate()` (schema) and `test()`
(below). It reads the failures and iterates, three rounds at most. The user
sees a preview of the menu bar with the agent's notes on what it couldn't
map, then chooses Keep or Discard. The screenshot and tree go to the
provider the user picked and nowhere else; a local model keeps everything on
the machine.

**Test in a nested session:** what `test()` and the catalog CI both run.
The rig is this survey's `menu-probe.py` with one more step:

1. Nested arbor + hearth on a private bus, AT-SPI registry,
   `HEARTH_MENU_MODULE_DIR` pointing at the candidate. The app runs with a
   throwaway HOME and, for apps that need a document, a fixture file from
   `tests/`.
2. `hearth-ipc call appmenu dump` must show the module's menus.
3. For each item, check that its target resolves:
   - the AT-SPI selector finds exactly one accessible
   - a `gtk_action` exists in `DescribeAll`
   - a `keys` chord is in the app's documented shortcuts, or is a standard
     one (Ctrl+C/V/X/Z/A/S/O/N/W/Q).
4. Items marked `safe: true` (not Quit, Delete, Close) are clicked through
   `hearth-ipc call appmenu click File/New`. The test then checks for an
   effect: a new window, an AT-SPI state change, a dialog opened then
   closed with Escape, or a screenshot that differs. Each run is recorded
   in `tests/<version>.yaml`.
5. Screenshots of each opened menu are saved for the PR.

The catalog CI runs the same thing for every module against the app from
nixpkgs (`nix build nixpkgs#attr`) or Flathub (`flatpak install --user` into
a throwaway `FLATPAK_USER_DIR`). It runs on each app update in nixpkgs-
unstable and Flathub, so a module goes untested within a day of the app
changing.
