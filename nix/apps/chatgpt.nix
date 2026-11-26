self:
# The ChatGPT/Codex desktop app on Wayland with the Secret Service
# (electron.nix says why). Its menus are exported, so no global-menu
# flags. No package in nixpkgs that matches: pass one.
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "chatgpt";
  description = "ChatGPT desktop, adjusted for the Hearth desktop (Wayland, Secret Service)";
  wrap = { package, extraWrapperArgs }: e.wrapWayland {
    exe = "chatgpt"; inherit package;
    args = extraWrapperArgs;
  };
} args
