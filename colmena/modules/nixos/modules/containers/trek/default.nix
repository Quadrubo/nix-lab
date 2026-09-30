{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.trek;

  # The entrypoint chowns the data dirs to the in-container `node` user (uid 1000)
  # before dropping privileges. Rootless podman maps that to a host subuid.
  nodeContainerUid = 1000;
  subUidBase = (builtins.head config.users.users.container-user.subUidRanges).startUid;
  nodeHostUid = subUidBase + nodeContainerUid - 1;
in
{
  options.myServices.trek = {
    enable = mkEnableOption "TREK";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "mauriceboe/trek:4.3.3"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for TREK.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
      description = "Time zone used by TREK for logs, reminders and scheduled tasks.";
    };

    dataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/trek/data";
      description = "Path to store TREK data (SQLite database, logs, keys).";
    };

    uploadsPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/trek/uploads";
      description = "Path to store TREK uploads.";
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
        name = "TREK";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.backups.sqliteDatabases = [
      {
        name = "trek";
        path = "${cfg.dataPath}/travel.db";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "trek"; }
      ];
    };

    sops.secrets."trek_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "trek_env";
      owner = "container-user";
      restartUnits = [
        "podman-trek.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/trek 0755 container-user users -"
      "d ${cfg.dataPath} 0755 ${toString nodeHostUid} ${toString nodeHostUid} -"
      "d ${cfg.uploadsPath} 0755 ${toString nodeHostUid} ${toString nodeHostUid} -"
    ];

    # App
    virtualisation.oci-containers.containers.trek = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=traefik"
        "--network=trek"
        # Hardening as in the upstream docker-compose.yml
        "--read-only"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=128m"
        "--security-opt=no-new-privileges"
        "--cap-drop=ALL"
        "--cap-add=CHOWN"
        "--cap-add=SETUID"
        "--cap-add=SETGID"
        "--health-cmd=wget -qO- http://localhost:3000/api/health"
        "--health-interval=30s"
        "--health-timeout=10s"
        "--health-retries=3"
        "--health-start-period=15s"
      ];

      environment = {
        NODE_ENV = "production";
        PORT = "3000";
        TZ = cfg.timeZone;
        LOG_LEVEL = "info";
        APP_URL = "https://${cfg.domain}";
        ALLOWED_ORIGINS = "https://${cfg.domain}";
        FORCE_HTTPS = "true";
        TRUST_PROXY = "1";
      };

      # The env file carries ENCRYPTION_KEY.
      environmentFiles = [ config.sops.secrets."trek_env".path ];

      volumes = [
        "${cfg.dataPath}:/app/data"
        "${cfg.uploadsPath}:/app/uploads"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.trek.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.trek.entrypoints" = "websecure";
          "traefik.http.routers.trek.tls.certresolver" = "myresolver";
          "traefik.http.services.trek.loadbalancer.server.port" = "3000";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.trek-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.trek.middlewares" = "trek-allowlist@docker";
        };
    };

    systemd.services."podman-trek".after = [ "podman-network-trek-container-user.service" ];
    systemd.services."podman-trek".requires = [ "podman-network-trek-container-user.service" ];
  };
}
