{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.photon;
in
{
  options.myServices.photon = {
    enable = mkEnableOption "Photon";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/rtuszik/photon-docker:2.1.1"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Photon.";
    };

    region = mkOption {
      type = types.str;
      default = "planet";
      description = "Geographic region for Photon geocoding data.";
    };

    updateStrategy = mkOption {
      type = types.str;
      default = "SEQUENTIAL";
      description = "Update strategy for Photon index (PARALLEL, SEQUENTIAL, or DISABLED).";
    };

    updateInterval = mkOption {
      type = types.str;
      default = "30d";
      description = "Interval between Photon index update checks.";
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
        { name = "photon"; }
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/photon 0755 container-user users -"
      "d /mnt/storage/containers/photon/data 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.photon = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=photon"
      ];

      environment = {
        REGION = cfg.region;
        UPDATE_STRATEGY = cfg.updateStrategy;
        UPDATE_INTERVAL = cfg.updateInterval;
        PUID = "1000";
        PGID = "1000";
      };

      volumes = [
        "/mnt/storage/containers/photon/data:/photon/data"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.photon.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.photon.entrypoints" = "websecure";
          "traefik.http.routers.photon.tls.certresolver" = "myresolver";
          "traefik.http.services.photon.loadbalancer.server.port" = "2322";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.photon-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.photon.middlewares" = "photon-allowlist@docker";
        };
    };

    systemd.services."podman-photon".after = [ "podman-network-photon-container-user.service" ];
    systemd.services."podman-photon".requires = [ "podman-network-photon-container-user.service" ];
  };
}
