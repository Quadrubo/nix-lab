{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.julweb;
in
{
  options.myServices.julweb = {
    enable = mkEnableOption "JulWeb";

    sopsFile = mkOption {
      type = types.path;
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/quadrubo/julweb:v0.1.1";
    };

    domain = mkOption {
      type = types.str;
      default = "julweb.dev";
    };

    dbImage = mkOption {
      type = types.str;
      default = "mariadb:10.11";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [ "julweb" ];
    };

    # Secrets
    sops.secrets."julweb_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "julweb_env";
      owner = "container-user";
      restartUnits = [ "podman-julweb.service" ];
    };

    sops.secrets."julweb-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "julweb-db_env";
      owner = "container-user";
      restartUnits = [ "podman-julweb-db.service" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/julweb/data 0755 container-user users -"

      "d /mnt/storage/containers/julweb/storage 0755 container-user users -"
      "d /mnt/storage/containers/julweb/storage/app 0755 container-user users -"

      "d /mnt/storage/containers/julweb-db/mysql 0755 container-user users -"
    ];

    # Container
    virtualisation.oci-containers.containers.julweb-db = {
      image = cfg.dbImage;
      autoStart = true;

      extraOptions = [ "--network=julweb" ];

      podman.user = "container-user";

      environment = {
        MYSQL_DATABASE = "julweb";
        MYSQL_USER = "julweb";
      };

      environmentFiles = [ config.sops.secrets."julweb-db_env".path ];

      volumes = [
        "/mnt/storage/containers/julweb-db/mysql:/var/lib/mysql"
      ];
    };

    systemd.services."podman-julweb-db".after = [ "podman-network-julweb.service" ];
    systemd.services."podman-julweb-db".requires = [ "podman-network-julweb.service" ];

    virtualisation.oci-containers.containers.julweb = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=traefik"
        "--network=julweb"
      ];

      podman.user = "container-user";

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.julweb.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.julweb.entrypoints" = "websecure";
        "traefik.http.routers.julweb.tls.certresolver" = "myresolver";
      };

      environment = {
        AUTORUN_ENABLED = "true";
        AUTORUN_LARAVEL_STORAGE_LINK = "true";
        AUTORUN_LARAVEL_MIGRATION = "true";
        AUTORUN_LARAVEL_SEEDING = "true";

        APP_NAME = "JulWeb";
        APP_ENV = "production";
        APP_URL = "https://${cfg.domain}";
        APP_LOCALE = "de";

        DB_CONNECTION = "mysql";
        DB_HOST = "julweb-db";
        DB_DATABASE = "julweb";
        DB_USERNAME = "julweb";

        UMAMI_URL = "https://analytics.julweb.dev/script.js";
        UMAMI_WEBSITE_ID = "86a956e4-a3c8-43f0-a5ec-c3aa0396a275";
      };

      environmentFiles = [ config.sops.secrets."julweb_env".path ];

      volumes = [
        "/mnt/storage/containers/julweb/data:/data"
        "/mnt/storage/containers/julweb/storage/app:/var/www/html/storage/app"
      ];

      dependsOn = [ "julweb-db" ];
    };

    systemd.services."podman-julweb".after = [
      "podman-registry-login-ghcr.service"
      "podman-network-julweb.service"
    ];
    systemd.services."podman-julweb".requires = [
      "podman-registry-login-ghcr.service"
      "podman-network-julweb.service"
    ];
  };
}
