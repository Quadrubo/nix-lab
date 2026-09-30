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
      default = "lscr.io/linuxserver/speedtest-tracker:version-v1.15.0"; # renovate: docker
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

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "Speedtest Tracker";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

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

    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 container-user users -"
    ];

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
        DB_CONNECTION = "sqlite";
        SPEEDTEST_SCHEDULE = cfg.schedule;
      };

      environmentFiles = [ config.sops.secrets."speedtest-tracker_env".path ];

      volumes = [
        # :U so podman chowns the mount to the container's PUID. SQLite needs to
        # create its journal alongside the database, which requires write access
        # on the directory itself, not just the file.
        "${cfg.configPath}:/config:U"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.speedtest-tracker.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.speedtest-tracker.entrypoints" = "websecure";
          "traefik.http.routers.speedtest-tracker.tls.certresolver" = "myresolver";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.speedtest-tracker-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.speedtest-tracker.middlewares" = "speedtest-tracker-allowlist@docker";
        };
    };

    systemd.services."podman-speedtest-tracker".after = [
      "podman-network-speedtest-tracker-container-user.service"
    ];
    systemd.services."podman-speedtest-tracker".requires = [
      "podman-network-speedtest-tracker-container-user.service"
    ];
  };
}
