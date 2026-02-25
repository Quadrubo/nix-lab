{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.hemmelig;
in
{
  options.myServices.hemmelig = {
    enable = mkEnableOption "Hemmelig";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "hemmeligapp/hemmelig:v7"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Hemmelig.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "hemmelig"; }
      ];
    };

    sops.secrets."hemmelig_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "hemmelig_env";
      owner = "container-user";
      restartUnits = [
        "podman-hemmelig.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/hemmelig/database 0755 container-user users -"
      "d /mnt/storage/containers/hemmelig/uploads 0755 container-user users -"
    ];

    # App
    virtualisation.oci-containers.containers.hemmelig = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--init"
        "--network=traefik"
        "--network=hemmelig"
        "--health-cmd=wget --no-verbose --tries=1 --spider http://localhost:3000/api/health/ready"
        "--health-interval=30s"
        "--health-timeout=10s"
        "--health-retries=3"
        "--health-start-period=10s"
      ];

      environment = {
        DATABASE_URL = "file:/app/database/hemmelig.db";
        BETTER_AUTH_URL = "https://${cfg.domain}";
        HEMMELIG_BASE_URL = "https://${cfg.domain}";
        NODE_ENV = "production";
        HEMMELIG_ALLOW_REGISTRATION = "false";
        HEMMELIG_ANALYTICS_ENABLED = "false";
      };

      environmentFiles = [ config.sops.secrets."hemmelig_env".path ];

      volumes = [
        "/mnt/storage/containers/hemmelig/database:/app/database"
        "/mnt/storage/containers/hemmelig/uploads:/app/uploads"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.hemmelig.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.hemmelig.entrypoints" = "websecure";
        "traefik.http.routers.hemmelig.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-hemmelig".after = [ "podman-network-hemmelig-container-user.service" ];
    systemd.services."podman-hemmelig".requires = [ "podman-network-hemmelig-container-user.service" ];
  };
}
