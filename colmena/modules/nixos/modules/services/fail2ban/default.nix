{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.fail2ban;
in
{
  options.myServices.fail2ban = {

    enable = mkEnableOption "Fail2Ban";
  };

  config = mkIf cfg.enable {
    services.fail2ban = {
      enable = true;
      bantime = "24h";
      maxretry = 5;
    };
  };
}
