{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.immich;
in
{
  options.myServices.immich = {
    enable = mkEnableOption "Immich";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Immich.";
    };

    serverImage = mkOption {
      type = types.str;
      default = "ghcr.io/immich-app/immich-server:v2.5.2"; # renovate: docker
    };

    machineLearningImage = mkOption {
      type = types.str;
      default = "ghcr.io/immich-app/immich-machine-learning:v2.5.2"; # renovate: docker
    };

    redisImage = mkOption {
      type = types.str;
      default = "docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23"; # renovate: docker
    };

    enableMachineLearning = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the Immich machine learning container.";
    };

    uploadPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/immich-server/data";
      description = "Path to store uploaded files.";
    };

    dbPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/immich-db/data";
      description = "Path to store database data.";
    };

    modelCachePath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/immich-machine-learning/cache";
      description = "Path to store machine learning cache.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
      description = "Timezone for Immich containers.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "immich"; }
      ];
    };

    sops.secrets."immich-server_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "immich-server_env";
      owner = "container-user";
      restartUnits = [
        "podman-immich-server.service"
      ]
      ++ optional cfg.enableMachineLearning "podman-immich-machine-learning.service";
    };

    sops.secrets."immich-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "immich-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-immich-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d ${cfg.uploadPath} 0755 container-user users -"
      "d ${cfg.dbPath} 0755 container-user users -"
      "d ${cfg.modelCachePath} 0755 container-user users -"
    ];

    # Redis
    virtualisation.oci-containers.containers.immich-redis = {
      image = cfg.redisImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=immich"
        "--health-cmd=redis-cli ping || exit 1"
        "--health-interval=30s"
        "--health-timeout=10s"
        "--health-retries=3"
      ];
    };

    # Database
    virtualisation.oci-containers.containers.immich-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=immich"
        "--shm-size=128mb"
      ];

      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
        DB_STORAGE_TYPE = "HDD";
      };

      environmentFiles = [ config.sops.secrets."immich-db_env".path ];

      volumes = [
        "${cfg.dbPath}:/var/lib/postgresql/data"
      ];
    };

    # Server
    virtualisation.oci-containers.containers.immich-server = {
      image = cfg.serverImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=immich"
      ];

      environment = {
        TZ = cfg.timeZone;
        DB_USERNAME = "postgres";
        DB_DATABASE_NAME = "immich";
        REDIS_HOSTNAME = "immich-redis";
        DB_HOSTNAME = "immich-db";
      };

      environmentFiles = [ config.sops.secrets."immich-server_env".path ];

      volumes = [
        "${cfg.uploadPath}:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];

      dependsOn = [
        "immich-redis"
        "immich-db"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.immich.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.immich.entrypoints" = "websecure";
        "traefik.http.routers.immich.tls.certresolver" = "myresolver";
      };
    };

    virtualisation.oci-containers.containers.immich-machine-learning = mkIf cfg.enableMachineLearning {
      image = cfg.machineLearningImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=immich"
      ];

      environment = {
        TZ = cfg.timeZone;
      };

      environmentFiles = [ config.sops.secrets."immich-server_env".path ];

      volumes = [
        "${cfg.modelCachePath}:/cache"
      ];
    };

    systemd.services."podman-immich-redis".after = [ "podman-network-immich-container-user.service" ];
    systemd.services."podman-immich-redis".requires = [ "podman-network-immich-container-user.service" ];

    systemd.services."podman-immich-db".after = [ "podman-network-immich-container-user.service" ];
    systemd.services."podman-immich-db".requires = [ "podman-network-immich-container-user.service" ];

    systemd.services."podman-immich-server".after = [
      "podman-network-immich-container-user.service"
      "podman-immich-redis.service"
      "podman-immich-db.service"
    ];
    systemd.services."podman-immich-server".requires = [
      "podman-network-immich-container-user.service"
      "podman-immich-redis.service"
      "podman-immich-db.service"
    ];

    systemd.services."podman-immich-machine-learning" = mkIf cfg.enableMachineLearning {
      after = [ "podman-network-immich-container-user.service" ];
      requires = [ "podman-network-immich-container-user.service" ];
    };
  };
}
