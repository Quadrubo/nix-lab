{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.chartdb;
in
{
  options.myServices.chartdb = {
    enable = mkEnableOption "ChartDB";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/chartdb/chartdb:1.19.0"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for ChartDB.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "chartdb"; }
      ];
    };

    virtualisation.oci-containers.containers.chartdb = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=traefik"
        "--network=chartdb"
        "--health-cmd=wget -O - http://localhost:80 || exit 1"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=3"
        "--health-start-period=20s"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.chartdb.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.chartdb.entrypoints" = "websecure";
        "traefik.http.routers.chartdb.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-chartdb".after = [ "podman-network-chartdb-container-user.service" ];
    systemd.services."podman-chartdb".requires = [ "podman-network-chartdb-container-user.service" ];
  };
}
