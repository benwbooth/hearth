self:
# The keyring and password dialogs of the Hearth desktop (README "Keyring"):
#
#   imports = [ hearth.nixosModules.keyring ];
#   hearth.keyring.enable = true;
#
# - oo7-daemon is the Secret Service (org.freedesktop.secrets), a systemd
#   user service (2026-11-23, replacing KWallet). hearth's login screen
#   hands it the login password (pam_oo7 on greetd, nixosModules.greeter),
#   so it's unlocked with no prompt; hearth answers its prompts
#   (services/KeyringPrompter). Keyring file:
#   ~/.local/share/keyrings/v1/login.keyring. This is what nixpkgs-unstable's
#   services.oo7 module does, minus its pam_oo7 on `login` (text consoles).
#   Flatpaks reach it through oo7's portal (nixosModules.portal routes
#   Secret there).
# - gcr-ssh-agent is the SSH agent (GNOME's gcr library, standalone, no
#   GNOME session; replaces OpenSSH's agent + a login-time ssh-add). It
#   offers every key in ~/.ssh with a .pub and unlocks each the first time
#   it's used with the passphrase from the keyring (Generic schema,
#   unique=ssh-store:<key path>); otherwise hearth asks (it serves GNOME's
#   org.gnome.keyring.SystemPrompter), with "unlock automatically" to
#   remember it.
# - SSH_ASKPASS / SUDO_ASKPASS: hearth's own password dialog
#   (helpers/hearth-askpass). sudo -A: "Administrator password" naming the
#   command, never remembered. ssh: host passwords, `ssh -i` keys, host
#   keys and `ssh-add -c` confirmations; "SSH key passphrase" is answered
#   from the keyring when saved there, and "Remember in my keyring" saves
#   it. With no hearth running it asks on the terminal.
{ config, lib, options, pkgs, ... }:
let
  cfg = config.hearth.keyring;
  hearth = self.packages.${pkgs.stdenv.hostPlatform.system}.hearth;
  askpass = "${hearth}/bin/hearth-askpass";
in
{
  options.hearth.keyring = {
    enable = lib.mkEnableOption "the oo7 keyring, gcr's SSH agent and hearth's password dialogs";
    serverPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.oo7-server;
      defaultText = lib.literalExpression "pkgs.oo7-server";
      description = "oo7's daemon (needs one with libexec/oo7-daemon and its user units).";
    };
    portalPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.oo7-portal;
      defaultText = lib.literalExpression "pkgs.oo7-portal";
      description = "oo7's portal backend (Flatpaks' secrets).";
    };
    pamPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.oo7-pam or null;
      defaultText = lib.literalExpression "pkgs.oo7-pam or null";
      description = "pam_oo7, which unlocks the keyring at hearth's login screen (null: no unlock at login).";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.user.services.oo7-daemon.wantedBy = [ "default.target" ];
      security.wrappers.oo7-daemon = {
        owner = "root";
        group = "root";
        capabilities = "cap_ipc_lock=ep"; # keeps secrets out of swap
        source = "${cfg.serverPackage}/libexec/oo7-daemon";
      };
      # oo7-server installs its user units in share/systemd/user, where
      # NixOS doesn't look. (oo7-portal ships lib/systemd/user itself; the
      # portal module adds it.)
      systemd.packages = [
        (pkgs.runCommand "oo7-user-units" { } ''
          mkdir -p $out/lib/systemd/user
          # -P keeps its dbus-org.freedesktop.secrets alias a symlink.
          cp -P ${cfg.serverPackage}/share/systemd/user/* $out/lib/systemd/user/
        '')
      ];
      xdg.portal.extraPortals = [ cfg.portalPackage ];

      services.gnome.gcr-ssh-agent.enable = true;
      # Keep unlocked keys across nixos-rebuild switch (a restart forgets them).
      systemd.user.services.gcr-ssh-agent.restartIfChanged = false;
      systemd.user.services.gcr-ssh-agent.environment.SSH_ASKPASS = config.programs.ssh.askPassword;
      # The socket sets SSH_AUTH_SOCK in systemd's user environment; shells
      # and anything started before that get it here.
      environment.extraInit = ''
        if [ -z "''${SSH_AUTH_SOCK:-}" ] && [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
          export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gcr/ssh"
        fi
      '';

      programs.ssh.askPassword = askpass;
      environment.variables.SUDO_ASKPASS = askpass;
      security.sudo.extraConfig = ''
        Defaults env_keep += "SUDO_ASKPASS"
      '';
    }
    (lib.optionalAttrs (options ? services.hearth-greeter) {
      services.hearth-greeter.keyring.pamPackage = lib.mkIf (cfg.pamPackage != null) cfg.pamPackage;
    })
  ]);
}
