{
  description = "hearth: a Quickshell desktop shell for Hyprland";

  # /etc/nixos sets `inputs.nixpkgs.follows`, so Quickshell links the same Qt
  # as Plasma's platform theme and the KDE apps; a second Qt would fail to load
  # the `kde` platform theme plugin.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.quickshell-src = {
    url = "https://git.outfoxxed.me/quickshell/quickshell/archive/refs/tags/v0.3.2.tar.gz";
    flake = false;
  };

  outputs = { self, nixpkgs, quickshell-src }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = pkgs.lib;

    # 26.05 ships 0.3.0; 0.3.2 adds the NativeTextRendering pragma.
    quickshell = pkgs.quickshell.overrideAttrs (_: {
      version = "0.3.2";
      src = quickshell-src;
    });

    # RDP server for the Hyprland session (replaces KRDP); not in nixpkgs.
    hypr-rdp = pkgs.callPackage ./nix/hypr-rdp.nix { };

    python = pkgs.python3.withPackages (p: [ p.dbus-python p.pygobject3 ]);

    # Everything the shell's widgets shell out to.
    runtimeDeps = with pkgs; [
      quickshell
      cliphist wl-clipboard
      ddcutil hyprsunset
      udisks networkmanager
      curl jq libnotify xdg-utils pciutils cups
      wlogout libqalculate hyprpaper
      pipewire wireplumber
      systemd procps coreutils gnugrep gawk util-linux iproute2
      python
    ];

    hearth = pkgs.stdenvNoCC.mkDerivation {
      pname = "hearth";
      version = "0.1.0";
      src = lib.cleanSource ./.;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hearth $out/bin
        cp -r shell helpers hypr $out/share/hearth/
        chmod +x $out/share/hearth/helpers/*
        patchShebangs $out/share/hearth/helpers
        for exe in hearth hearth-ipc; do
          args=""
          [ $exe = hearth-ipc ] && args="ipc"
          makeWrapper ${quickshell}/bin/quickshell $out/bin/$exe \
            --add-flags "-p $out/share/hearth/shell $args" \
            --prefix PATH : ${lib.makeBinPath runtimeDeps}:$out/share/hearth/helpers
        done
        runHook postInstall
      '';
      meta.mainProgram = "hearth";
    };
  in {
    packages.${system} = {
      default = hearth;
      inherit hearth quickshell hypr-rdp;
    };

    # `nix develop`, then `quickshell -p shell` runs straight from the
    # checkout and hot-reloads on every save.
    devShells.${system}.default = pkgs.mkShell {
      packages = runtimeDeps ++ [ pkgs.kdePackages.qtdeclarative ];
      shellHook = ''
        export PATH="$PWD/helpers:$PATH"
      '';
    };
  };
}
