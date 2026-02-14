{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.myModules.maintenance;
in
{
  options.myModules.maintenance = {
    enable = mkEnableOption "Maintenance";
  };

  config = mkIf cfg.enable {
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    boot.loader.grub.configurationLimit = 10;
  };
}
