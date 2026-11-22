#!/usr/bin/env bash
# After the survey: stop workers, timer and rigs, then remove everything it
# downloaded (tested apps' store paths, tool roots, the Flatpak installation).
set -u
cd "$(dirname "$0")/.."
systemctl --user stop 'hearth-menu-probe-*' hearth-menu-janitor.timer hearth-menu-janitor.service 2>/dev/null
R=~/.config/Claude/side-session-notes/local_3249e068-f6b4-44ca-966b-72365fe5da97/menu-rig.sh
for d in "$XDG_RUNTIME_DIR"/menu-rig-survey*; do [ -d "$d" ] && MENU_RIG_DIR=$d "$R" stop; done
rm -rf ~/.cache/hearth-menu-survey/roots          # tools' GC roots (grim, wtype, libdbusmenu)
scripts/janitor.sh
rm -rf ~/.cache/hearth-menu-survey/flatpak
echo "done: $(df -h /nix | awk 'NR==2 {print $4}') free"
