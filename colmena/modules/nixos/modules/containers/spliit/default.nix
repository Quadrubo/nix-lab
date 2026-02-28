{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.spliit;
in
{
  options.myServices.spliit = {
    enable = mkEnableOption "Spliit";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/spliit-app/spliit:1.19.0"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgres:18-alpine"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Spliit.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
    };

    dbPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/spliit-db/data";
      description = "Path to store Spliit database data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "spliit"; }
      ];
    };

    sops.secrets."spliit_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "spliit_env";
      owner = "container-user";
      restartUnits = [
        "podman-spliit.service"
      ];
    };

    sops.secrets."spliit-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "spliit-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-spliit-db.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dbPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.spliit-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=spliit"
        "--health-cmd=pg_isready -h localhost -U spliit -d spliit"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=10"
      ];

      environment = {
        TZ = cfg.timeZone;
        POSTGRES_DB = "spliit";
        POSTGRES_USER = "spliit";
      };

      environmentFiles = [ config.sops.secrets."spliit-db_env".path ];

      volumes = [
        "${cfg.dbPath}:/var/lib/postgresql/data"
      ];
    };

    virtualisation.oci-containers.containers.spliit = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=spliit"
      ];

      environment = {
        TZ = cfg.timeZone;
      };

      environmentFiles = [ config.sops.secrets."spliit_env".path ];

      dependsOn = [ "spliit-db" ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.spliit.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.spliit.entrypoints" = "websecure";
        "traefik.http.routers.spliit.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-spliit-db".after = [ "podman-network-spliit-container-user.service" ];
    systemd.services."podman-spliit-db".requires = [ "podman-network-spliit-container-user.service" ];

    systemd.services."podman-spliit".after = [
      "podman-network-spliit-container-user.service"
      "podman-spliit-db.service"
    ];
    systemd.services."podman-spliit".requires = [
      "podman-network-spliit-container-user.service"
      "podman-spliit-db.service"
    ];
  };
}
