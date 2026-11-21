# Spotlight's indexer and the AI hub's llama.cpp server as systemd user
# units (README "Spotlight" and "AI"):
#
#   imports = [ hearth.nixosModules.ai ];
#   services.hearth-ai.enable = true;
#
# hearth-indexer.service starts with the graphical session and runs recoll
# at idle CPU and I/O priority, capped at 25% of a core and 512 MB: one
# catch-up pass, then inotify watches (no polling). hearth freezes it
# (cgroup freezer) while you use the computer, so it only works when you're
# away (Settings > Spotlight). Folders and exclusions come from Settings >
# Spotlight.
#
# hearth-llama-server.service is not started at login: Settings > AI starts
# and stops it (llama.cpp router mode over the models folder). Ollama stays
# the system's own service (services.ollama).
self:
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hearth-ai;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  options.services.hearth-ai = {
    enable = lib.mkEnableOption "hearth's Spotlight indexer and AI hub services";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.hearth;
      defaultText = lib.literalExpression "hearth.packages.\${system}.hearth";
      description = "The hearth package (provides hearth-indexer and hearth-llama-server).";
    };
    indexer.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Index files for Spotlight (recoll, started with the graphical session).";
    };
  };

  config = lib.mkIf cfg.enable {
    # recoll watches every indexed folder with inotify.
    boot.kernel.sysctl."fs.inotify.max_user_watches" = lib.mkDefault 1048576;

    systemd.user.services.hearth-indexer = lib.mkIf cfg.indexer.enable {
      description = "hearth Spotlight indexer (recoll)";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe' cfg.package "hearth-indexer";
        Restart = "on-failure";
        RestartSec = 30;
        # Never in the way: lowest CPU and I/O priority, at most a quarter
        # of one core, memory capped (the converters it runs, like
        # pdftotext, count too). hearth also freezes the whole unit while
        # you use the computer (services/Spotlight.qml).
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        CPUWeight = "idle";
        CPUQuota = "25%";
        IOSchedulingClass = "idle";
        IOWeight = 1;
        MemoryHigh = "384M";
        MemoryMax = "512M";
        MemorySwapMax = 0;
      };
    };

    systemd.user.services.hearth-llama-server = {
      description = "hearth AI hub: llama.cpp server (router mode)";
      serviceConfig = {
        ExecStart = lib.getExe' cfg.package "hearth-llama-server";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
