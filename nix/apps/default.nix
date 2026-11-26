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
    (import ./libreoffice.nix self)
    (import ./antigravity.nix self)
    (import ./brave.nix self)
    (import ./chatgpt.nix self)
    (import ./claude-desktop.nix self)
    (import ./cursor.nix self)
    (import ./google-chrome.nix self)
    (import ./heroic.nix self)
    (import ./mailspring.nix self)
    (import ./slack.nix self)
    (import ./teams-for-linux.nix self)
    (import ./vscode.nix self)
    (import ./zcode.nix self)
  ];
}
