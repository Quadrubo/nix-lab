{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.dawarich;

  baseEnv = {
    RAILS_ENV = "development";
    REDIS_URL = "redis://dawarich-redis:6379";
    DATABASE_HOST = "dawarich-db";
    DATABASE_USERNAME = "postgres";
    DATABASE_NAME = "dawarich_development";
    APPLICATION_HOSTS = "${cfg.domain},127.0.0.1";
    APPLICATION_PROTOCOL = "http";
    PROMETHEUS_EXPORTER_ENABLED = "false";
    PROMETHEUS_EXPORTER_PORT = "9394";
    SELF_HOSTED = "true";
    STORE_GEODATA = "true";
  };
in
{
  options.myServices.dawarich = {
    enable = mkEnableOption "Dawarich";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "freikin/dawarich:0.37.3"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgis/postgis:17-3.5-alpine"; # renovate: docker
    };

    redisImage = mkOption {
      type = types.str;
      default = "redis:7.4-alpine"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for the Dawarich ingress.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
    };

    appCpuLimit = mkOption {
      type = types.str;
      default = "0.50";
      description = "CPU limit for the app container.";
    };

    appMemoryLimit = mkOption {
      type = types.str;
      default = "4g";
      description = "Memory limit for the app container.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "dawarich"; }
      ];
    };

    sops.secrets."dawarich-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "dawarich-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-dawarich-db.service"
      ];
    };

    sops.secrets."dawarich-app_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "dawarich-app_env";
      owner = "container-user";
      restartUnits = [
        "podman-dawarich-app.service"
        "podman-dawarich-sidekiq.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/dawarich/shared 0755 container-user users -"
      "d /mnt/storage/containers/dawarich/public 0755 container-user users -"
      "d /mnt/storage/containers/dawarich/watched 0755 container-user users -"
      "d /mnt/storage/containers/dawarich/storage 0755 container-user users -"
      "d /mnt/storage/containers/dawarich_db/data 0755 container-user users -"
    ];

    # Redis
    virtualisation.oci-containers.containers.dawarich-redis = {
      image = cfg.redisImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=dawarich"
        "--health-cmd=redis-cli --raw incr ping"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=10s"
      ];

      volumes = [
        "/mnt/storage/containers/dawarich/shared:/data"
      ];
    };

    # Database
    virtualisation.oci-containers.containers.dawarich-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=dawarich"
        "--shm-size=1g"
        "--health-cmd=pg_isready -U postgres -d dawarich_development"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=10s"
      ];

      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "dawarich_development";
      };

      environmentFiles = [ config.sops.secrets."dawarich-db_env".path ];

      volumes = [
        "/mnt/storage/containers/dawarich_db/data:/var/lib/postgresql/data"
        "/mnt/storage/containers/dawarich/shared:/var/shared"
      ];
    };

    # App
    virtualisation.oci-containers.containers.dawarich-app = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      entrypoint = "web-entrypoint.sh";
      cmd = [
        "bin/rails"
        "server"
        "-p"
        "3000"
        "-b"
        "::"
      ];

      extraOptions = [
        "--network=traefik"
        "--network=dawarich"
        "--health-cmd=sh -c \"wget -qO - http://127.0.0.1:3000/api/v1/health | grep -q ok\""
        "--health-interval=10s"
        "--health-retries=30"
        "--health-start-period=30s"
        "--health-timeout=10s"
        "--cpus=${cfg.appCpuLimit}"
        "--memory=${cfg.appMemoryLimit}"
      ];

      environment = baseEnv // {
        MIN_MINUTES_SPENT_IN_CITY = "60";
        TIME_ZONE = cfg.timeZone;
        PROMETHEUS_EXPORTER_HOST = "0.0.0.0";
      };

      environmentFiles = [ config.sops.secrets."dawarich-app_env".path ];

      volumes = [
        "/mnt/storage/containers/dawarich/public:/var/app/public"
        "/mnt/storage/containers/dawarich/watched:/var/app/tmp/imports/watched"
        "/mnt/storage/containers/dawarich/storage:/var/app/storage"
        "/mnt/storage/containers/dawarich_db/data:/dawarich_db_data"
      ];

      dependsOn = [
        "dawarich-db"
        "dawarich-redis"
      ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.dawarich-app-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.dawarich-app.middlewares" = "dawarich-app-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.dawarich-app.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.dawarich-app.entrypoints" = "websecure";
        "traefik.http.routers.dawarich-app.tls.certresolver" = "myresolver";
      };
    };

    # Sidekiq
    virtualisation.oci-containers.containers.dawarich-sidekiq = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      entrypoint = "sidekiq-entrypoint.sh";
      cmd = [ "sidekiq" ];

      extraOptions = [
        "--network=dawarich"
        "--health-cmd=pgrep -f sidekiq"
        "--health-interval=10s"
        "--health-retries=30"
        "--health-start-period=30s"
        "--health-timeout=10s"
      ];

      environment = baseEnv // {
        BACKGROUND_PROCESSING_CONCURRENCY = "10";
        PROMETHEUS_EXPORTER_HOST = "dawarich-app";
      };

      environmentFiles = [ config.sops.secrets."dawarich-app_env".path ];

      volumes = [
        "/mnt/storage/containers/dawarich/public:/var/app/public"
        "/mnt/storage/containers/dawarich/watched:/var/app/tmp/imports/watched"
        "/mnt/storage/containers/dawarich/storage:/var/app/storage"
      ];

      dependsOn = [
        "dawarich-db"
        "dawarich-redis"
        "dawarich-app"
      ];
    };

    systemd.services."podman-dawarich-redis".after = [ "podman-network-dawarich-container-user.service" ];
    systemd.services."podman-dawarich-redis".requires = [ "podman-network-dawarich-container-user.service" ];

    systemd.services."podman-dawarich-db".after = [ "podman-network-dawarich-container-user.service" ];
    systemd.services."podman-dawarich-db".requires = [ "podman-network-dawarich-container-user.service" ];

    systemd.services."podman-dawarich-app".after = [
      "podman-network-dawarich-container-user.service"
      "podman-dawarich-db.service"
      "podman-dawarich-redis.service"
    ];
    systemd.services."podman-dawarich-app".requires = [
      "podman-network-dawarich-container-user.service"
      "podman-dawarich-db.service"
      "podman-dawarich-redis.service"
    ];

    systemd.services."podman-dawarich-sidekiq".after = [
      "podman-network-dawarich-container-user.service"
      "podman-dawarich-db.service"
      "podman-dawarich-redis.service"
      "podman-dawarich-app.service"
    ];
    systemd.services."podman-dawarich-sidekiq".requires = [
      "podman-network-dawarich-container-user.service"
      "podman-dawarich-db.service"
      "podman-dawarich-redis.service"
      "podman-dawarich-app.service"
    ];
  };
}
