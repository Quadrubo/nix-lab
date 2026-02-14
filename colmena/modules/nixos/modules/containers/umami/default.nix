{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.umami;
in
{
  options.myServices.umami = {
    enable = mkEnableOption "Umami Analytics";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/umami-software/umami:postgresql-v2"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      default = "analytics.julweb.dev";
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgres:15-alpine"; # renovate: docker
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [ "umami" ];
    };

    sops.secrets."umami_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "umami_env";
      owner = "container-user";
      restartUnits = [
        "podman-umami.service"
      ];
    };

    sops.secrets."umami-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "umami-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-umami-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/umami-db/data 0755 container-user users -"
    ];

    # Database Container
    virtualisation.oci-containers.containers.umami-db = {
      image = cfg.dbImage;
      autoStart = true;

      extraOptions = [
        "--network=umami"
        "--health-cmd=pg_isready -U umami -d umami"
        "--health-interval=5s"
        "--health-retries=5"
        "--health-timeout=5s"
      ];

      podman.user = "container-user";

      environment = {
        POSTGRES_DB = "umami";
        POSTGRES_USER = "umami";
      };

      environmentFiles = [ config.sops.secrets."umami-db_env".path ];

      volumes = [
        "/mnt/storage/containers/umami-db/data:/var/lib/postgresql/data"
      ];
    };

    # App Container
    virtualisation.oci-containers.containers.umami = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=traefik"
        "--network=umami"
        # Healthcheck
        "--health-cmd=curl -f http://localhost:3000/api/heartbeat || exit 1"
        "--health-interval=5s"
        "--health-retries=5"
        "--health-timeout=5s"
      ];

      podman.user = "container-user";

      environment = {
        DATABASE_TYPE = "postgresql";
      };

      environmentFiles = [ config.sops.secrets."umami_env".path ];

      dependsOn = [ "umami-db" ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.umami.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.umami.entrypoints" = "websecure";
        "traefik.http.routers.umami.tls.certresolver" = "myresolver";
      };
    };

    # Systemd Service Ordering
    systemd.services."podman-umami".after = [
      "podman-network-umami.service"
      "podman-umami-db.service"
    ];
    systemd.services."podman-umami".requires = [
      "podman-network-umami.service"
      "podman-umami-db.service"
    ];

    systemd.services."podman-umami-db".after = [ "podman-network-umami.service" ];
    systemd.services."podman-umami-db".requires = [ "podman-network-umami.service" ];
  };
}
