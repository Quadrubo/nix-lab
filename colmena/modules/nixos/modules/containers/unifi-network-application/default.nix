{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.unifi-network-application;

  initMongoScript = pkgs.writeText "init-mongo.sh" (builtins.readFile ./init-mongo.sh);
in
{
  options.myServices.unifi-network-application = {
    enable = mkEnableOption "UniFi Network Application";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/unifi-network-application:latest"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "mongo:8.0.12-noble"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for UniFi Network Application.";
    };

    dbLocalhostPort = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = "When set, publish the MongoDB port to this loopback port on the host.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Etc/UTC";
    };

    configPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/unifi-network-application/config";
      description = "Path to store UniFi Network Application config.";
    };

    dbPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/unifi-db/db";
      description = "Path to store UniFi MongoDB data.";
    };

    memLimit = mkOption {
      type = types.str;
      default = "1024";
      description = "Memory limit for UniFi application (MB).";
    };

    memStartup = mkOption {
      type = types.str;
      default = "1024";
      description = "Startup memory for UniFi application (MB).";
    };
  };

  config = mkIf cfg.enable {
    myServices.traefik.serversTransports = {
      unifi-network-application = {
        insecureSkipVerify = true;
      };
    };

    myServices.podman = {
      enable = true;
      networks = [
        { name = "unifi-network-application"; }
      ];
    };

    sops.secrets."unifi-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "unifi-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-unifi-db.service"
      ];
    };

    sops.secrets."unifi-network-application_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "unifi-network-application_env";
      owner = "container-user";
      restartUnits = [
        "podman-unifi-network-application.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 container-user users -"
      "d ${cfg.dbPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.unifi-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=unifi-network-application"
      ];

      ports = lib.optional (cfg.dbLocalhostPort != null) "127.0.0.1:${toString cfg.dbLocalhostPort}:27017";

      environment = {
        MONGO_USER = "unifi";
        MONGO_DBNAME = "unifi";
        MONGO_AUTHSOURCE = "admin";
      };

      environmentFiles = [ config.sops.secrets."unifi-db_env".path ];

      volumes = [
        "${cfg.dbPath}:/data/db"
        "${initMongoScript}:/docker-entrypoint-initdb.d/init-mongo.sh:ro"
      ];
    };

    # TODO: switch to unifi os server which replaces this
    virtualisation.oci-containers.containers.unifi-network-application = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=unifi-network-application"
      ];

      ports = [
        # Changed from default 8080 to avoid conflict with Traefik
        # Set unifi.http.port=8100 in /mnt/storage/containers/unifi-network-application/config/data/system.properties
        "8100:8100" # Device inform
        # "8443:8443" # Web GUI HTTPS
        "3478:3478/udp" # STUN
        # not needed, use set-inform or DNS instead
        # "10001:10001/udp" # L2 device discovery
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = cfg.timeZone;
        MONGO_USER = "unifi";
        MONGO_HOST = "unifi-db";
        MONGO_PORT = "27017";
        MONGO_DBNAME = "unifi";
        MONGO_AUTHSOURCE = "admin";
        MEM_LIMIT = cfg.memLimit;
        MEM_STARTUP = cfg.memStartup;
        MONGO_TLS = "";
      };

      environmentFiles = [ config.sops.secrets."unifi-network-application_env".path ];

      volumes = [
        "${cfg.configPath}:/config"
      ];

      dependsOn = [ "unifi-db" ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.unifi-network-application.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.unifi-network-application.entrypoints" = "websecure";
          "traefik.http.routers.unifi-network-application.tls.certresolver" = "myresolver";
          "traefik.http.services.unifi-network-application.loadbalancer.server.port" = "8443";
          "traefik.http.services.unifi-network-application.loadbalancer.server.scheme" = "https";
          "traefik.http.services.unifi-network-application.loadbalancer.serverstransport" = "unifi-network-application@file";
          "traefik.http.routers.unifi-network-application.service" = "unifi-network-application";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.unifi-network-application-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.unifi-network-application.middlewares" = "unifi-network-application-allowlist@docker";
        };
    };

    systemd.services."podman-unifi-db".after = [ "podman-network-unifi-network-application-container-user.service" ];
    systemd.services."podman-unifi-db".requires = [ "podman-network-unifi-network-application-container-user.service" ];

    systemd.services."podman-unifi-network-application".after = [
      "podman-network-unifi-network-application-container-user.service"
      "podman-unifi-db.service"
    ];
    systemd.services."podman-unifi-network-application".requires = [
      "podman-network-unifi-network-application-container-user.service"
      "podman-unifi-db.service"
    ];

    networking.firewall.allowedTCPPorts = [
      8100 # UniFi device inform (changed from default 8080 via system.properties)
    ];
    networking.firewall.allowedUDPPorts = [
      3478 # UniFi STUN
      # only needed for automatic discovery of new devices on the same subnet. use set-inform or DNS instead
      # 10001 # UniFi L2 discovery
    ];
  };
}
