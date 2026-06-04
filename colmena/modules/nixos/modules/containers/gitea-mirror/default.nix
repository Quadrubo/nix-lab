{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.gitea-mirror;

  # Host subuid that the in-container `gitea-mirror` user (uid 1001) maps to.
  appContainerUid = 1001;
  subUidBase = (builtins.head config.users.users.container-user.subUidRanges).startUid;
  appHostUid = subUidBase + appContainerUid - 1;
in
{
  options.myServices.gitea-mirror = {
    enable = mkEnableOption "Gitea Mirror";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/raylabshq/gitea-mirror:v3.17.0"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Gitea Mirror.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };

    starredLists = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "GitHub Star List names to mirror. Empty disables starred mirroring.";
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "Gitea Mirror";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "gitea-mirror"; }
      ];
    };

    sops.secrets."gitea-mirror_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "gitea-mirror_env";
      owner = "container-user";
      restartUnits = [
        "podman-gitea-mirror.service"
      ];
    };

    # Directories. The data dir is owned by appHostUid because the image runs as
    # a non-root user (uid 1001) with no root entrypoint to fix permissions.
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/gitea-mirror 0755 container-user users -"
      "d /mnt/storage/containers/gitea-mirror/data 0755 ${toString appHostUid} ${toString appHostUid} -"
    ];

    virtualisation.oci-containers.containers.gitea-mirror = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=gitea-mirror"
      ];

      environment = {
        NODE_ENV = "production";
        HOST = "0.0.0.0";
        PORT = "4321";
        DATABASE_URL = "file:data/gitea-mirror.db";
        BETTER_AUTH_URL = "https://${cfg.domain}";
        PUBLIC_BETTER_AUTH_URL = "https://${cfg.domain}";
        BETTER_AUTH_TRUSTED_ORIGINS = "https://${cfg.domain}";
        GITEA_URL = "http://forgejo:3000";
        SCHEDULE_ENABLED = "true";
        GITEA_MIRROR_INTERVAL = "8h";
        AUTO_IMPORT_REPOS = "true";
        AUTO_MIRROR_REPOS = "true";
        SCHEDULE_NOTIFY_ON_FAILURE = "true";
        SCHEDULE_NOTIFY_ON_SUCCESS = "true";
        PRIVATE_REPOSITORIES = "true";
        MIRROR_STARRED = if cfg.starredLists != [ ] then "true" else "false";
        AUTO_MIRROR_STARRED = if cfg.starredLists != [ ] then "true" else "false";
        MIRROR_STARRED_LISTS = lib.concatStringsSep "," cfg.starredLists;
        MIRROR_METADATA = "true";
        MIRROR_ISSUES = "true";
        MIRROR_PULL_REQUESTS = "true";
        MIRROR_LABELS = "true";
        MIRROR_MILESTONES = "true";
        MIRROR_WIKI = "true";
        MIRROR_RELEASES = "true";
      };

      environmentFiles = [ config.sops.secrets."gitea-mirror_env".path ];

      volumes = [
        "/mnt/storage/containers/gitea-mirror/data:/app/data"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.gitea-mirror.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.gitea-mirror.entrypoints" = "websecure";
          "traefik.http.routers.gitea-mirror.tls.certresolver" = "myresolver";
          "traefik.http.services.gitea-mirror.loadbalancer.server.port" = "4321";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.gitea-mirror-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.gitea-mirror.middlewares" = "gitea-mirror-allowlist@docker";
        };
    };

    systemd.services."podman-gitea-mirror".after = [
      "podman-network-gitea-mirror-container-user.service"
      "podman-forgejo.service"
    ];
    systemd.services."podman-gitea-mirror".requires = [
      "podman-network-gitea-mirror-container-user.service"
    ];
  };
}
