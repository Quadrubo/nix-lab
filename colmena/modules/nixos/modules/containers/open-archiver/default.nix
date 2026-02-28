{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.open-archiver;
in
{
  options.myServices.open-archiver = {
    enable = mkEnableOption "Open Archiver";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Open Archiver.";
    };

    appImage = mkOption {
      type = types.str;
      default = "logiclabshq/open-archiver:v0.4.2"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgres:17-alpine"; # renovate: docker
    };

    valkeyImage = mkOption {
      type = types.str;
      default = "valkey/valkey:8-alpine"; # renovate: docker
    };

    meilisearchImage = mkOption {
      type = types.str;
      default = "getmeili/meilisearch:v1.15"; # renovate: docker
    };

    appDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/open-archiver/data";
      description = "Path to store Open Archiver data.";
    };

    dbDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/open-archiver-db/data";
      description = "Path to store Open Archiver database data.";
    };

    valkeyDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/open-archiver-valkey/data";
      description = "Path to store Open Archiver Valkey data.";
    };

    meilisearchDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/open-archiver-meilisearch/data";
      description = "Path to store Open Archiver Meilisearch data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "open-archiver"; }
      ];
    };

    sops.secrets."open-archiver_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "open-archiver_env";
      owner = "container-user";
      restartUnits = [
        "podman-open-archiver.service"
      ];
    };

    sops.secrets."open-archiver-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "open-archiver-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-open-archiver-db.service"
      ];
    };

    sops.secrets."open-archiver-valkey_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "open-archiver-valkey_env";
      owner = "container-user";
      restartUnits = [
        "podman-open-archiver-valkey.service"
      ];
    };

    sops.secrets."open-archiver-meilisearch_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "open-archiver-meilisearch_env";
      owner = "container-user";
      restartUnits = [
        "podman-open-archiver-meilisearch.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.appDataPath} 0755 container-user users -"
      "d ${cfg.dbDataPath} 0755 container-user users -"
      "d ${cfg.valkeyDataPath} 0755 container-user users -"
      "d ${cfg.meilisearchDataPath} 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.open-archiver-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=open-archiver"
        "--health-cmd=pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];

      environment = {
        POSTGRES_DB = "open_archive";
        POSTGRES_USER = "admin";
      };

      environmentFiles = [ config.sops.secrets."open-archiver-db_env".path ];

      volumes = [
        "${cfg.dbDataPath}:/var/lib/postgresql/data"
      ];
    };

    # Valkey
    virtualisation.oci-containers.containers.open-archiver-valkey = {
      image = cfg.valkeyImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=open-archiver"
      ];

      entrypoint = "sh";
      cmd = [ "-c" "valkey-server --requirepass \"$REDIS_PASSWORD\"" ];

      environmentFiles = [ config.sops.secrets."open-archiver-valkey_env".path ];

      volumes = [
        "${cfg.valkeyDataPath}:/data"
      ];
    };

    # Meilisearch
    virtualisation.oci-containers.containers.open-archiver-meilisearch = {
      image = cfg.meilisearchImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=open-archiver"
      ];

      environmentFiles = [ config.sops.secrets."open-archiver-meilisearch_env".path ];

      volumes = [
        "${cfg.meilisearchDataPath}:/meili_data"
      ];
    };

    # App
    virtualisation.oci-containers.containers.open-archiver = {
      image = cfg.appImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=open-archiver"
      ];

      environment = {
        NODE_ENV = "production";
        PORT_BACKEND = "4000";
        PORT_FRONTEND = "3000";
        SYNC_FREQUENCY = "* * * * *";
        POSTGRES_HOST = "open-archiver-db";
        POSTGRES_DB = "open_archive";
        POSTGRES_USER = "admin";
        MEILI_HOST = "http://open-archiver-meilisearch:7700";
        REDIS_HOST = "open-archiver-valkey";
        REDIS_PORT = "6379";
        REDIS_TLS_ENABLED = "false";
        STORAGE_TYPE = "local";
        BODY_SIZE_LIMIT = "100M";
        STORAGE_LOCAL_ROOT_PATH = "/var/data/open-archiver";
        JWT_EXPIRES_IN = "7d";
      };

      environmentFiles = [ config.sops.secrets."open-archiver_env".path ];

      volumes = [
        "${cfg.appDataPath}:/var/data/open-archiver"
      ];

      dependsOn = [
        "open-archiver-db"
        "open-archiver-valkey"
        "open-archiver-meilisearch"
      ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.open-archiver-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.open-archiver.middlewares" = "open-archiver-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.open-archiver.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.open-archiver.entrypoints" = "websecure";
        "traefik.http.routers.open-archiver.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-open-archiver-db".after = [ "podman-network-open-archiver-container-user.service" ];
    systemd.services."podman-open-archiver-db".requires = [ "podman-network-open-archiver-container-user.service" ];

    systemd.services."podman-open-archiver-valkey".after = [ "podman-network-open-archiver-container-user.service" ];
    systemd.services."podman-open-archiver-valkey".requires = [ "podman-network-open-archiver-container-user.service" ];

    systemd.services."podman-open-archiver-meilisearch".after = [ "podman-network-open-archiver-container-user.service" ];
    systemd.services."podman-open-archiver-meilisearch".requires = [ "podman-network-open-archiver-container-user.service" ];

    systemd.services."podman-open-archiver".after = [
      "podman-network-open-archiver-container-user.service"
      "podman-open-archiver-db.service"
      "podman-open-archiver-valkey.service"
      "podman-open-archiver-meilisearch.service"
    ];
    systemd.services."podman-open-archiver".requires = [
      "podman-network-open-archiver-container-user.service"
      "podman-open-archiver-db.service"
      "podman-open-archiver-valkey.service"
      "podman-open-archiver-meilisearch.service"
    ];
  };
}
