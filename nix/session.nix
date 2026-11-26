self:
# A desktop session without startup races: apps start once the desktop
# services they look for are there.
#
# Apps check some services only once, when they start, and quietly do
# without them for the rest of their life: a tray icon
# (org.kde.StatusNotifierWatcher), notifications
# (org.freedesktop.Notifications) and the global menu bar
# (com.canonical.AppMenu.Registrar). hearth provides all three, but the
# session's autostart apps (XDG autostart, started with
# graphical-session.target as soon as arbor is up) used to start before
# hearth: canopy got no tray icon, tessera no global menu (2026-11-25).
#
# hearth-ready.service waits (at most 30 s) until the three names are on
# the session bus; every app-*.service (the autostart units, and the apps
# hearth itself starts, which find it long done) is ordered after it.
# arbor's session restore waits for hearth's menu bar the same way, and
# arbor starts the menu registrar first thing (hearth/arbor/config.kdl).
{ pkgs, ... }:
let
  wait = pkgs.writeShellScript "hearth-ready" ''
    names="org.kde.StatusNotifierWatcher org.freedesktop.Notifications com.canonical.AppMenu.Registrar"
    for _ in $(seq 120); do
      missing=""
      for n in $names; do
        # status asks for the owner's credentials: it never starts (D-Bus
        # activates) anything.
        ${pkgs.systemd}/bin/busctl --user status "$n" >/dev/null 2>&1 || missing="$missing $n"
      done
      [ -z "$missing" ] && { echo "hearth is ready"; exit 0; }
      sleep 0.25
    done
    echo "hearth isn't ready after 30 s (missing:$missing); starting apps anyway"
  '';
in
{
  systemd.user.services.hearth-ready = {
    description = "Wait until hearth's tray, notifications and global menu are up";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "xdg-desktop-autostart.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${wait}";
      TimeoutStartSec = 40;
    };
  };

  # Every app-*.service (systemd applies "app-.service.d" to all units whose
  # name starts with "app-"): the XDG autostart units and hearth's launches.
  environment.etc."systemd/user/app-.service.d/50-hearth-ready.conf".text = ''
    [Unit]
    Wants=hearth-ready.service
    After=hearth-ready.service
  '';
}
