#!/usr/bin/env bash
# After the survey: stop workers, timer and rigs, then remove everything it
# downloaded (tested apps' store paths, tool roots, the Flatpak installation).
set -u
cd "$(dirname "$0")/.."
systemctl --user stop 'hearth-menu-probe-*' hearth-menu-janitor.timer hearth-menu-janitor.service 2>/dev/null
R=$(dirname "$(readlink -f "$0")")/menu-rig.sh
for d in "$XDG_RUNTIME_DIR"/menu-rig-survey* /var/tmp/menu-rig-"$USER"/menu-rig-survey*; do [ -d "$d" ] && MENU_RIG_DIR=$XDG_RUNTIME_DIR/$(basename "$d") "$R" stop; done
rm -rf ~/.cache/hearth-menu-survey/roots          # tools' GC roots (grim, wtype, libdbusmenu)
scripts/janitor.sh
rm -rf ~/.cache/hearth-menu-survey/flatpak
echo "done: $(df -h /nix | awk 'NR==2 {print $4}') free"
