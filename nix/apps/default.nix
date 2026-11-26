self:
# Hearth's changes to other people's apps, one file per app, so each fix
# has a home, a reason written next to it, and an on/off switch:
#
#   imports = [ hearth.nixosModules.apps ];
#   hearth.apps.spotify.enable = true;
#
# Hearth is the desktop (shell, session, apps); arbor is its window
# manager. A change belongs here when an app needs it to work right on the
# Hearth desktop (Wayland, the side area, global menu, theme), rather than
# being a personal preference of one machine.
{ ... }:
{
  imports = [
    (import ./spotify.nix self)
  ];
}
