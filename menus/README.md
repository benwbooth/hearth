# Menu modules

Global menus for apps that export none: one file per app, data only
(`hearth-menu-module/1`; format, safety and the catalog design in
`menu-survey/MODULES.md`). hearth-appmenu loads this folder (installed to
`share/hearth/menus`) and `~/.config/hearth/menus/`, which overrides it
file by file. A module applies to a window with no native menu address
(dbusmenu, GMenuModel), matched by its app id, desktop id or Flatpak id.

Action kinds: `keys` (arbor `send-keys` to that window), `gtk_action`
(`app.x`/`win.x` over org.gtk.Actions; its enabled/checked state is live),
`open_help` (an https URL). Progress per app: `menu-survey/checklist.tsv`.
