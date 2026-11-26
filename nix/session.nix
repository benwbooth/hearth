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
# the session bus and the portal answers (dark mode); every app-*.service (the autostart units, and the apps
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
      # The portal answering, not just started: apps ask it once, at start,
      # for dark mode (Claude stayed light all session when it didn't answer
      # in time, 2026-11-25). Asking also starts it (D-Bus activation).
      if [ -z "$missing" ] && ! ${pkgs.systemd}/bin/busctl --user --timeout=2 call \
          org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
          org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme >/dev/null 2>&1; then
        missing=" org.freedesktop.portal.Desktop (Settings)"
      fi
      [ -z "$missing" ] && { echo "hearth is ready"; exit 0; }
      sleep 0.25
    done
    echo "hearth isn't ready after 30 s (missing:$missing); starting apps anyway"
  '';
in
{
  # The portal (dark mode, file dialogs, screenshots for apps) starts as soon
  # as the session does, not when the first app asks: arbor has imported
  # WAYLAND_DISPLAY by then, and its backends are quick (grove claims its
  # name before Qt starts, grove 35b9e78). Pulled in by
  # xdg-desktop-autostart.target, not graphical-session.target: a target is
  # ordered after what it wants, and the portal waits at start for backends
  # ordered after graphical-session.target (oo7-portal), so that deadlocked
  # every login until D-Bus gave up after 25 s (boot VM test, 2026-11-26).
  # Autostart apps still wait for it (hearth-ready).
  systemd.user.services.xdg-desktop-portal.wantedBy = [ "xdg-desktop-autostart.target" ];

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
  # (A unit package: /etc/systemd/user is generated whole by NixOS.)
  systemd.packages = [
    (pkgs.runCommand "hearth-ready-dropin" { } ''
      mkdir -p $out/lib/systemd/user/app-.service.d
      printf '[Unit]\nWants=hearth-ready.service\nAfter=hearth-ready.service\n' \
        > $out/lib/systemd/user/app-.service.d/50-hearth-ready.conf
    '')
  ];
}
