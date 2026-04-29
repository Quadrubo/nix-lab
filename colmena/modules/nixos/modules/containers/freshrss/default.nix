{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.freshrss;
in
{
  options.myServices.freshrss = {
    enable = mkEnableOption "FreshRSS";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "freshrss/freshrss:1-alpine"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgres:18-alpine"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for FreshRSS.";
    };

    dbLocalhostPort = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = "When set, publish the DB port to this loopback port on the host.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "FreshRSS";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "freshrss"; }
      ];
    };

    sops.secrets."freshrss-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "freshrss-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-freshrss-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/freshrss/data 0755 container-user users -"
      "d /mnt/storage/containers/freshrss/extensions 0755 container-user users -"
      "d /mnt/storage/containers/freshrss-db/data 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.freshrss-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=freshrss"
      ];

      ports = optional (cfg.dbLocalhostPort != null) "127.0.0.1:${toString cfg.dbLocalhostPort}:5432";

      environment = {
        POSTGRES_DB = "freshrss";
        POSTGRES_USER = "freshrss";
      };

      environmentFiles = [ config.sops.secrets."freshrss-db_env".path ];

      volumes = [
        "/mnt/storage/containers/freshrss-db/data:/var/lib/postgresql/data"
      ];
    };

    # App
    virtualisation.oci-containers.containers.freshrss = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=freshrss"
      ];

      environment = {
        TZ = cfg.timeZone;
      };

      volumes = [
        "/mnt/storage/containers/freshrss/data:/var/www/FreshRSS/data"
        "/mnt/storage/containers/freshrss/extensions:/var/www/FreshRSS/extensions"
      ];

      dependsOn = [ "freshrss-db" ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.freshrss.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.freshrss.entrypoints" = "websecure";
          "traefik.http.routers.freshrss.tls.certresolver" = "myresolver";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.freshrss-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.freshrss.middlewares" = "freshrss-allowlist@docker";
        };
    };

    systemd.services."podman-freshrss-db".after = [ "podman-network-freshrss-container-user.service" ];
    systemd.services."podman-freshrss-db".requires = [
      "podman-network-freshrss-container-user.service"
    ];

    systemd.services."podman-freshrss".after = [
      "podman-network-freshrss-container-user.service"
      "podman-freshrss-db.service"
    ];
    systemd.services."podman-freshrss".requires = [
      "podman-network-freshrss-container-user.service"
      "podman-freshrss-db.service"
    ];
  };
}
