{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.hedgedoc;
in
{
  options.myServices.hedgedoc = {
    enable = mkEnableOption "HedgeDoc";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "quay.io/hedgedoc/hedgedoc:1.10.5"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "postgres:17-alpine"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for HedgeDoc.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        {
          name = "hedgedoc";
        }
      ];
    };

    sops.secrets."hedgedoc_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "hedgedoc_env";
      owner = "container-user";
      restartUnits = [
        "podman-hedgedoc.service"
      ];
    };

    sops.secrets."hedgedoc-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "hedgedoc-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-hedgedoc-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/hedgedoc/uploads 0755 container-user users -"
      "d /mnt/storage/containers/hedgedoc-db/data 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.hedgedoc-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=hedgedoc"
        "--health-cmd=pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];

      environment = {
        POSTGRES_DB = "hedgedoc";
        POSTGRES_USER = "hedgedoc";
      };

      environmentFiles = [ config.sops.secrets."hedgedoc-db_env".path ];

      volumes = [
        "/mnt/storage/containers/hedgedoc-db/data:/var/lib/postgresql/data"
      ];
    };

    # App
    virtualisation.oci-containers.containers.hedgedoc = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=hedgedoc"
      ];

      environment = {
        CMD_DOMAIN = cfg.domain;
        CMD_PROTOCOL_USESSL = "true";
        CMD_URL_ADDPORT = "false";
        CMD_ALLOW_ANONYMOUS = "false";
      };

      environmentFiles = [ config.sops.secrets."hedgedoc_env".path ];

      volumes = [
        "/mnt/storage/containers/hedgedoc/uploads:/hedgedoc/public/uploads"
      ];

      dependsOn = [ "hedgedoc-db" ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.hedgedoc-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.hedgedoc.middlewares" = "hedgedoc-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.hedgedoc.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.hedgedoc.entrypoints" = "websecure";
        "traefik.http.routers.hedgedoc.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-hedgedoc-db".after = [ "podman-network-hedgedoc-container-user.service" ];
    systemd.services."podman-hedgedoc-db".requires = [ "podman-network-hedgedoc-container-user.service" ];

    systemd.services."podman-hedgedoc".after = [
      "podman-network-hedgedoc-container-user.service"
      "podman-hedgedoc-db.service"
    ];
    systemd.services."podman-hedgedoc".requires = [
      "podman-network-hedgedoc-container-user.service"
      "podman-hedgedoc-db.service"
    ];
  };
}
