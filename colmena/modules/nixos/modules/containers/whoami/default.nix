{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.whoami;
in
{
  options = {
    myServices.whoami = {
      enable = mkEnableOption "Whoami container";

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port to expose the service on.";
      };

      image = mkOption {
        type = types.str;
        default = "traefik/whoami"; # renovate: docker
        description = "Docker image to run.";
      };
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.whoami = {
      image = cfg.image;
      ports = [ "${toString cfg.port}:80" ];
      autoStart = true;

      podman = {
        user = "container-user";
      };
    };

    # Automatically open the firewall for this port
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
