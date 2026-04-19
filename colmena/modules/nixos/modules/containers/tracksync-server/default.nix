{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.tracksync-server;
in
{
  options.myServices.tracksync-server = {
    enable = mkEnableOption "Tracksync Server";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/quadrubo/tracksync/server:1.0.1"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Tracksync Server.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "tracksync-server"; }
      ];
    };

    sops.secrets."tracksync-server_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "tracksync-server_env";
      owner = "container-user";
      restartUnits = [
        "podman-tracksync-server.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/tracksync-server 0755 container-user users -"
      "d /mnt/storage/containers/tracksync-server/data 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.tracksync-server = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=traefik"
        "--network=tracksync-server"
        "--network=dawarich"
        "--health-cmd=wget -qO- http://127.0.0.1:8080/health || exit 1"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=10s"
        "--health-timeout=5s"
      ];

      environment = {
        ACCOUNT__0__DEVICE_ID = "columbus-p10-pro-julian";
        ACCOUNT__0__TARGET_URL = "http://dawarich-app:3000";
        CLIENT__0__ID = "framy";
        CLIENT__0__ALLOWED_DEVICES = "columbus-p10-pro-julian";
        CLIENT__1__ID = "compy";
        CLIENT__1__ALLOWED_DEVICES = "columbus-p10-pro-julian";
      };

      environmentFiles = [ config.sops.secrets."tracksync-server_env".path ];

      volumes = [
        "/mnt/storage/containers/tracksync-server/data:/app/data"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.tracksync-server.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.tracksync-server.entrypoints" = "websecure";
          "traefik.http.routers.tracksync-server.tls.certresolver" = "myresolver";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.tracksync-server-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.tracksync-server.middlewares" = "tracksync-server-allowlist@docker";
        };
    };

    systemd.services."podman-tracksync-server".after = [
      "podman-network-tracksync-server-container-user.service"
    ];
    systemd.services."podman-tracksync-server".requires = [
      "podman-network-tracksync-server-container-user.service"
    ];
  };
}
