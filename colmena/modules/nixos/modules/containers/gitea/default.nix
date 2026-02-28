{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.gitea;
in
{
  options.myServices.gitea = {
    enable = mkEnableOption "Gitea";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "gitea/gitea:1"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "mariadb:12"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Gitea.";
    };

    sshPort = mkOption {
      type = types.port;
      default = 9022;
      description = "Host port for Gitea SSH.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
      description = "Timezone for the Gitea container.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "gitea"; }
      ];
    };

    sops.secrets."gitea_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "gitea_env";
      owner = "container-user";
      restartUnits = [
        "podman-gitea.service"
      ];
    };

    sops.secrets."gitea-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "gitea-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-gitea-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/gitea/data 0755 container-user users -"
      "d /mnt/storage/containers/gitea-db/mysql 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.gitea-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=gitea"
      ];

      environment = {
        MARIADB_DATABASE = "gitea";
        MARIADB_USER = "gitea";
        MARIADB_RANDOM_ROOT_PASSWORD = "true";
      };

      environmentFiles = [ config.sops.secrets."gitea-db_env".path ];

      volumes = [
        "/mnt/storage/containers/gitea-db/mysql:/var/lib/mysql"
      ];
    };

    # App
    virtualisation.oci-containers.containers.gitea = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=gitea"
      ];

      ports = [
        "${toString cfg.sshPort}:22"
      ];

      environment = {
        TZ = cfg.timeZone;
        USER_UID = "1000";
        USER_GID = "100";
        GITEA__database__DB_TYPE = "mysql";
        GITEA__database__HOST = "gitea-db:3306";
        GITEA__database__NAME = "gitea";
        GITEA__database__USER = "gitea";
      };

      environmentFiles = [ config.sops.secrets."gitea_env".path ];

      volumes = [
        "/mnt/storage/containers/gitea/data:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];

      dependsOn = [ "gitea-db" ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.gitea-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.gitea.middlewares" = "gitea-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.gitea.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.gitea.entrypoints" = "websecure";
        "traefik.http.routers.gitea.tls.certresolver" = "myresolver";
        "traefik.http.services.gitea.loadbalancer.server.port" = "3000";
      };
    };

    systemd.services."podman-gitea-db".after = [ "podman-network-gitea-container-user.service" ];
    systemd.services."podman-gitea-db".requires = [ "podman-network-gitea-container-user.service" ];

    systemd.services."podman-gitea".after = [
      "podman-network-gitea-container-user.service"
      "podman-gitea-db.service"
    ];
    systemd.services."podman-gitea".requires = [
      "podman-network-gitea-container-user.service"
      "podman-gitea-db.service"
    ];
  };
}
