# hypr-rdp: native RDP server for Hyprland (IronRDP; H.264 via VA-API with a
# bundled OpenH264 fallback; PipeWire audio; clipboard incl. files).
# Not in nixpkgs; this follows upstream's pkg/nix/package.nix, pinned to a tag.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  clang,
  makeWrapper,
  libdrm,
  libgbm,
  libva,
  libxkbcommon,
  mesa,
  pipewire,
  pam,
  pulseaudio,
  wayland,
}:

rustPlatform.buildRustPackage rec {
  pname = "hypr-rdp";
  version = "0.1.8";

  src = fetchFromGitHub {
    owner = "MuNeNICK";
    repo = "hypr-rdp";
    rev = "v${version}";
    hash = "sha256-s3kQqnn1Ljg2tp/r5zohvrFbv2SUkxq28UMnMr+xosk=";
  };

  cargoHash = "sha256-QIacYWd/hzVYv/bbqj1Vo76prTl2/xJGEd1CuwgEWhw=";

  nativeBuildInputs = [
    pkg-config
    cmake
    clang
    makeWrapper
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    libdrm
    libgbm
    libva
    libxkbcommon
    mesa
    pipewire
    pam
    wayland
  ];

  # pactl for the default `redirect` audio mode; the setuid fusermount3
  # wrapper for receiving clipboard files from the client.
  postInstall = ''
    install -Dm644 LICENSE $out/share/licenses/hypr-rdp/LICENSE
    install -Dm644 pkg/pam/hypr-rdp.arch $out/share/hypr-rdp/pam/hypr-rdp

    # User unit with an [Install] section, so `systemctl --user enable` (the
    # hearth tray's "Start at login") works when NixOS installs it through
    # `systemd.packages`. Settings live in ~/.config/hypr-rdp/config.toml.
    mkdir -p $out/lib/systemd/user
    cat > $out/lib/systemd/user/hypr-rdp.service <<EOF
    [Unit]
    Description=hypr-rdp: RDP server for the Hyprland session
    Documentation=https://github.com/MuNeNICK/hypr-rdp
    PartOf=graphical-session.target
    After=graphical-session.target pipewire.service wireplumber.service

    [Service]
    ExecStart=$out/bin/hypr-rdp
    Restart=on-failure
    RestartSec=3

    [Install]
    WantedBy=graphical-session.target
    EOF
    wrapProgram $out/bin/hypr-rdp \
      --run 'if test -z "''${FUSERMOUNT_PATH-}" && test -x /run/wrappers/bin/fusermount3; then export FUSERMOUNT_PATH=/run/wrappers/bin/fusermount3; fi' \
      --prefix PATH : ${lib.makeBinPath [ pulseaudio ]}
  '';

  # The test suite spins up Wayland/RDP fixtures; upstream skips it too.
  doCheck = false;

  meta = {
    description = "Native RDP server for Hyprland";
    homepage = "https://github.com/MuNeNICK/hypr-rdp";
    license = lib.licenses.mit;
    mainProgram = "hypr-rdp";
    platforms = lib.platforms.linux;
  };
}
