{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.forgejo;
in
{
  options.myServices.forgejo = {
    enable = mkEnableOption "Forgejo";

    image = mkOption {
      type = types.str;
      default = "codeberg.org/forgejo/forgejo:15.0.3"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Forgejo.";
    };

    sshPort = mkOption {
      type = types.port;
      default = 9022;
      description = "Host port for Forgejo SSH.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
      description = "Timezone for the Forgejo container.";
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
        name = "Forgejo";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.backups.sqliteDatabases = [
      {
        name = "forgejo";
        path = "/mnt/storage/containers/forgejo/data/gitea/forgejo.db";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "forgejo"; }
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/forgejo 0755 container-user users -"
      "d /mnt/storage/containers/forgejo/data 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.forgejo = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=forgejo"
      ];

      ports = [
        "${toString cfg.sshPort}:22"
      ];

      environment = {
        TZ = cfg.timeZone;
        USER_UID = "1000";
        USER_GID = "100";
        FORGEJO__database__DB_TYPE = "sqlite3";
        # Pin the SQLite file to a fixed path so borgmatic can back it up.
        # Must live under /data/gitea (owned by the `git` runtime user); the
        # /data mount root is owned by container-root and is not writable by git.
        FORGEJO__database__PATH = "/data/gitea/forgejo.db";
        # Behind Traefik (TLS terminated upstream); set the public URL so
        # generated links and the SSH clone host are correct.
        FORGEJO__server__DOMAIN = cfg.domain;
        FORGEJO__server__ROOT_URL = "https://${cfg.domain}/";
        FORGEJO__server__SSH_DOMAIN = cfg.domain;
        FORGEJO__server__SSH_PORT = toString cfg.sshPort;
      };

      volumes = [
        "/mnt/storage/containers/forgejo/data:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.forgejo.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.forgejo.entrypoints" = "websecure";
          "traefik.http.routers.forgejo.tls.certresolver" = "myresolver";
          "traefik.http.services.forgejo.loadbalancer.server.port" = "3000";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.forgejo-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.forgejo.middlewares" = "forgejo-allowlist@docker";
        };
    };

    systemd.services."podman-forgejo".after = [ "podman-network-forgejo-container-user.service" ];
    systemd.services."podman-forgejo".requires = [ "podman-network-forgejo-container-user.service" ];
  };
}
