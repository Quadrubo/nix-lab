{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.speedtest-tracker;
in
{
  options.myServices.speedtest-tracker = {
    enable = mkEnableOption "Speedtest Tracker";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/speedtest-tracker:version-v1.13.5"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "mariadb:11"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Speedtest Tracker.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
    };

    schedule = mkOption {
      type = types.str;
      default = "0 4 * * *";
      description = "Cron schedule for speed tests.";
    };

    configPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/speedtest-tracker/config";
      description = "Path to store Speedtest Tracker config.";
    };

    dbPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/speedtest-tracker-db/mysql";
      description = "Path to store Speedtest Tracker database data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "speedtest-tracker"; }
      ];
    };

    sops.secrets."speedtest-tracker_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "speedtest-tracker_env";
      owner = "container-user";
      restartUnits = [
        "podman-speedtest-tracker.service"
      ];
    };

    sops.secrets."speedtest-tracker-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "speedtest-tracker-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-speedtest-tracker-db.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 container-user users -"
      "d ${cfg.dbPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.speedtest-tracker-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=speedtest-tracker"
      ];

      environment = {
        MARIADB_DATABASE = "speedtest_tracker";
        MARIADB_USER = "speedtest";
        MARIADB_RANDOM_ROOT_PASSWORD = "true";
      };

      environmentFiles = [ config.sops.secrets."speedtest-tracker-db_env".path ];

      volumes = [
        "${cfg.dbPath}:/var/lib/mysql"
      ];
    };

    virtualisation.oci-containers.containers.speedtest-tracker = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=speedtest-tracker"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = cfg.timeZone;
        DB_CONNECTION = "mysql";
        DB_HOST = "speedtest-tracker-db";
        DB_PORT = "3306";
        DB_DATABASE = "speedtest_tracker";
        DB_USERNAME = "speedtest";
        SPEEDTEST_SCHEDULE = cfg.schedule;
      };

      environmentFiles = [ config.sops.secrets."speedtest-tracker_env".path ];

      volumes = [
        "${cfg.configPath}:/config"
      ];

      dependsOn = [ "speedtest-tracker-db" ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.speedtest-tracker-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.speedtest-tracker.middlewares" = "speedtest-tracker-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.speedtest-tracker.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.speedtest-tracker.entrypoints" = "websecure";
        "traefik.http.routers.speedtest-tracker.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-speedtest-tracker-db".after = [ "podman-network-speedtest-tracker-container-user.service" ];
    systemd.services."podman-speedtest-tracker-db".requires = [ "podman-network-speedtest-tracker-container-user.service" ];

    systemd.services."podman-speedtest-tracker".after = [
      "podman-network-speedtest-tracker-container-user.service"
      "podman-speedtest-tracker-db.service"
    ];
    systemd.services."podman-speedtest-tracker".requires = [
      "podman-network-speedtest-tracker-container-user.service"
      "podman-speedtest-tracker-db.service"
    ];
  };
}
