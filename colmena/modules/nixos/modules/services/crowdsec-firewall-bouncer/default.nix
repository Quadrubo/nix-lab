{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.crowdsec-firewall-bouncer;
in
{
  options.myServices.crowdsec-firewall-bouncer = {
    enable = mkEnableOption "CrowdSec Firewall Bouncer";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing the API key";
    };
  };

  config = mkIf cfg.enable {
    services.crowdsec-firewall-bouncer = {
      enable = true;

      # Don't auto register because crowdsec is running in a container
      registerBouncer.enable = false;

      # Use the following command to retrieve the key
      # sudo -u container-user podman exec -it crowdsec cscli bouncers add firewall-bouncer
      secrets.apiKeyPath = config.sops.secrets."crowdsec_firewall_bouncer_key".path;

      settings = {
        api_url = "http://127.0.0.1:9876";

        mode = "iptables";

        disable_ipv6 = false;
        deny_action = "DROP";
        deny_log = true;
        deny_log_prefix = "crowdsec: ";

        iptables_chains = [
          "INPUT"
          "FORWARD"
        ];
      };
    };

    sops.secrets."crowdsec_firewall_bouncer_key" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "crowdsec_firewall_bouncer_key";
      owner = "container-user";
    };

    networking.firewall.enable = true;
  };
}
