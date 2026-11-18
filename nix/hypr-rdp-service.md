# hypr-rdp in /etc/nixos (replacing KRDP)

hearth builds hypr-rdp as `packages.x86_64-linux.hypr-rdp` (nix/hypr-rdp.nix,
upstream tag v0.1.8). It is not in nixpkgs. The tray indicator
(`shell/bar/indicators/Rdp.qml`) appears as soon as a user unit called
`hypr-rdp.service` exists and drives it with `systemctl --user`.

## 1. Package + systemd user unit

/etc/nixos has no hearth input yet (checked 2026-11-17). Add one next to the
other inputs, following nixpkgs (hearth's own flake comment explains why: one Qt):

```nix
inputs.hearth = {
  url = "github:benwbooth/hearth";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

add `hearth` to the `outputs = { ... }@inputs` argument list, then in the
main system module (the inline one with `services.desktopManager.plasma6`):

```nix
{ inputs, pkgs, ... }:
let
  hypr-rdp = inputs.hearth.packages.${pkgs.system}.hypr-rdp;
in {
  environment.systemPackages = [ hypr-rdp ];

  # The package ships $out/lib/systemd/user/hypr-rdp.service:
  #   ExecStart=<pkg>/bin/hypr-rdp   (all settings from ~/.config/hypr-rdp/config.toml)
  #   PartOf/After=graphical-session.target, Restart=on-failure, RestartSec=3
  #   [Install] WantedBy=graphical-session.target
  # Installing it this way (instead of systemd.user.services) keeps the
  # [Install] section, so the tray's "Start at login" can run
  # `systemctl --user enable/disable hypr-rdp` (symlink in ~/.config).
  # NixOS-defined user units have no [Install] section; with those the tray
  # shows the switch read-only.
  systemd.packages = [ hypr-rdp ];

  # Receiving files from the client's clipboard uses the setuid
  # /run/wrappers/bin/fusermount3, which NixOS provides by default; nothing
  # to add. VA-API: hardware.graphics already supplies radeonsi_drv_video.so
  # (seen working in the test below), no LIBVA_DRIVER_NAME needed.

  # The firewall is currently off (`networking.firewall.enable = false;`),
  # so 3389 is reachable on the LAN as soon as hypr-rdp binds 0.0.0.0. If the
  # firewall is ever turned on, open it:
  networking.firewall.allowedTCPPorts = [ 3389 ];
}
```

KRDP also uses 3389. It ships with plasma6 and runs as the user unit
`app-org.kde.krdpserver.service` (currently enabled + running), turned on in
Plasma's System Settings > Remote Desktop rather than in /etc/nixos. Turn it
off there, or `systemctl --user disable --now app-org.kde.krdpserver.service`,
before starting hypr-rdp, or the bind fails.

The unit needs `WAYLAND_DISPLAY` (and ideally `HYPRLAND_INSTANCE_SIGNATURE`)
in the systemd user manager's environment. uwsm does that; otherwise the
Hyprland config must run
`dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP`
at startup. Check with `systemctl --user show-environment | grep -E 'WAYLAND|HYPRLAND'`.
Without it the service fails and the tray shows "Failed".

Then, as Ben: `systemctl --user daemon-reload`, set credentials (below), and
use the tray (or `systemctl --user enable --now hypr-rdp`).

## 2. Credentials (Ben runs these, nothing is set by Nix)

hypr-rdp has two auth modes. **Without credentials it accepts unauthenticated
connections**, so set one of them before opening the port.

### a) Separate RDP username/password (works with every client, NLA ok)

```sh
mkdir -p ~/.config/hypr-rdp && chmod 700 ~/.config/hypr-rdp
# pick a password; stored in a 0600 file, not in the Nix store
install -m600 /dev/null ~/.config/hypr-rdp/password
$EDITOR ~/.config/hypr-rdp/password          # one line, the password
cat > ~/.config/hypr-rdp/config.toml <<'EOF'
bind = "0.0.0.0:3389"    # hypr-rdp's default is 127.0.0.1:3389 (local only)
username = "ben"
password_file = "/home/ben/.config/hypr-rdp/password"
# domain = "WORKGROUP"   # only if a Windows client insists on sending one
fps = 60
# audio_mode = "redirect"   # default: play on the client; "mirror" = both
EOF
systemctl --user restart hypr-rdp
```

### b) Ben's Linux password via PAM

```toml
auth_mode = "pam"      # and no username/password/password_file/domain
```

plus a PAM service in /etc/nixos (upstream ships an Arch one; the NixOS
equivalent):

```nix
security.pam.services.hypr-rdp = { };   # default auth/account stack (unix)
```

PAM mode needs a TLS client without NLA (FreeRDP `/sec:tls`; mstsc may want
saved credentials) and only allows the user who owns the desktop.

## 3. TLS certificate

Nothing to do: on first start hypr-rdp writes a self-signed RSA cert to
`~/.config/hypr-rdp/{cert,key}.pem` (key 0600) and reuses it after. Clients
will ask to trust it once. To use a real one: `cert = "/path/cert.pem"` and
`key = "/path/key.pem"` in config.toml (or `--cert/--key`).

## 4. Display, lock screen, and the local monitor

- By default hypr-rdp creates a **separate headless Hyprland output** named
  `hypr-rdp` (1920x1080 until a client resizes it, placed at x=-9999) with its
  own workspace. The remote client sees *that* output, not Ben's monitor, so
  it is an extra screen, unlike KRDP which mirrored the desktop. The output
  stays while the service runs (hearth's bar appears on it too). To get
  KRDP's behaviour, capture the real monitor instead: `output = "DP-1"`
  (`hyprctl monitors` for the name); `resolution`/`scale` fix the headless size.
- One session at a time: a new authenticated connection replaces the current.
- **Lock screen:** hyprlock (ext-session-lock) covers every output, including
  the headless one, so a locked session shows the lock screen to the remote
  client, and you unlock by typing the password over RDP. Input arrives through
  a virtual keyboard; hyprlock should accept it, but this has not been tested
  here. hypridle may lock / DPMS-off during a remote session because RDP input
  goes through the virtual keyboard/pointer (which normally counts as
  activity). If it doesn't, add an inhibitor in the hooks below.
- The local monitor keeps showing the desktop while someone is connected. To
  blank it, use session hooks in config.toml (name a monitor that is *not*
  captured; with Ben's Lua config dispatches are Lua expressions; check the
  exact dpms dispatcher name with the Hyprland 0.55 docs):

  ```toml
  on_session_start = "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\", monitor = \"DP-1\" })'"
  on_session_end   = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\",  monitor = \"DP-1\" })'"
  ```

## 5. hearth tray

`shell/bar/indicators/Rdp.qml` shows while `hypr-rdp.service` exists: dimmed
when stopped, blue dot when listening, green dot plus a highlighted client row
while connected (clients come from `ss`, matched on the unit's MainPID). Popup:
Start/Stop, "Start at login" (`systemctl --user enable/disable`, takes ~2 s),
listening address. Binds: `hearth-ipc call rdp toggle|start|stop|enable|disable|status`.
"Start at login" is read-only if the unit has no `[Install]` section (a
NixOS `systemd.user.services` unit); use the packaged unit as above.

## 6. Checks after switching

```sh
systemctl --user start hypr-rdp
journalctl --user -u hypr-rdp -f            # "Starting hypr-rdp on 0.0.0.0:3389"
ss -tlnp | grep 3389
vainfo                                       # radeonsi, H264 encode entrypoints
```

Logging: `RUST_LOG=hypr_rdp=debug` in `environment` for more detail;
`--h264-backend vaapi` forces VA-API (fails loudly instead of silently using
OpenH264).
