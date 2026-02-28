{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.kitchenowl;
in
{
  options.myServices.kitchenowl = {
    enable = mkEnableOption "KitchenOwl";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for KitchenOwl.";
    };

    webImage = mkOption {
      type = types.str;
      default = "tombursch/kitchenowl-web:v0.7.6"; # renovate: docker
    };

    backendImage = mkOption {
      type = types.str;
      default = "tombursch/kitchenowl-backend:v0.7.6"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgres:18"; # renovate: docker
    };

    backendDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/kitchenowl-backend/data";
      description = "Path to store KitchenOwl backend data.";
    };

    dbDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/kitchenowl-db/data";
      description = "Path to store KitchenOwl database data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "kitchenowl"; }
      ];
    };

    sops.secrets."kitchenowl-backend_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "kitchenowl-backend_env";
      owner = "container-user";
      restartUnits = [
        "podman-kitchenowl-backend.service"
      ];
    };

    sops.secrets."kitchenowl-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "kitchenowl-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-kitchenowl-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d ${cfg.backendDataPath} 0755 container-user users -"
      "d ${cfg.dbDataPath} 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.kitchenowl-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=kitchenowl"
        "--health-cmd=pg_isready -d $POSTGRES_DB -U $POSTGRES_USER"
        "--health-interval=30s"
        "--health-timeout=60s"
        "--health-retries=5"
        "--health-start-period=80s"
      ];

      environment = {
        POSTGRES_DB = "kitchenowl";
        POSTGRES_USER = "kitchenowl";
      };

      environmentFiles = [ config.sops.secrets."kitchenowl-db_env".path ];

      volumes = [
        "${cfg.dbDataPath}:/var/lib/postgresql/data"
      ];
    };

    # Backend
    virtualisation.oci-containers.containers.kitchenowl-backend = {
      image = cfg.backendImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=kitchenowl"
      ];

      environment = {
        FRONT_URL = "https://${cfg.domain}";
        DB_DRIVER = "postgresql";
        DB_HOST = "kitchenowl-db";
        DB_NAME = "kitchenowl";
        DB_USER = "kitchenowl";
      };

      environmentFiles = [ config.sops.secrets."kitchenowl-backend_env".path ];

      volumes = [
        "${cfg.backendDataPath}:/data"
      ];

      dependsOn = [ "kitchenowl-db" ];
    };

    # Web
    virtualisation.oci-containers.containers.kitchenowl-web = {
      image = cfg.webImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=kitchenowl"
      ];

      environment = {
        BACK_URL = "kitchenowl-backend:5000";
      };

      dependsOn = [ "kitchenowl-backend" ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.kitchenowl.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.kitchenowl.entrypoints" = "websecure";
        "traefik.http.routers.kitchenowl.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-kitchenowl-db".after = [ "podman-network-kitchenowl-container-user.service" ];
    systemd.services."podman-kitchenowl-db".requires = [ "podman-network-kitchenowl-container-user.service" ];

    systemd.services."podman-kitchenowl-backend".after = [
      "podman-network-kitchenowl-container-user.service"
      "podman-kitchenowl-db.service"
    ];
    systemd.services."podman-kitchenowl-backend".requires = [
      "podman-network-kitchenowl-container-user.service"
      "podman-kitchenowl-db.service"
    ];

    systemd.services."podman-kitchenowl-web".after = [
      "podman-network-kitchenowl-container-user.service"
      "podman-kitchenowl-backend.service"
    ];
    systemd.services."podman-kitchenowl-web".requires = [
      "podman-network-kitchenowl-container-user.service"
      "podman-kitchenowl-backend.service"
    ];
  };
}
