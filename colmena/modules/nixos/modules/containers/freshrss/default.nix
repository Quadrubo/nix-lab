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

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
    };
  };

  config = mkIf cfg.enable {
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

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.freshrss-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.freshrss.middlewares" = "freshrss-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.freshrss.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.freshrss.entrypoints" = "websecure";
        "traefik.http.routers.freshrss.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-freshrss-db".after = [ "podman-network-freshrss-container-user.service" ];
    systemd.services."podman-freshrss-db".requires = [ "podman-network-freshrss-container-user.service" ];

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
