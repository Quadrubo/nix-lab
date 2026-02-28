{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.obsidian-livesync;
in
{
  options.myServices.obsidian-livesync = {
    enable = mkEnableOption "Obsidian LiveSync";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Obsidian LiveSync.";
    };

    image = mkOption {
      type = types.str;
      default = "couchdb:3"; # renovate: docker
    };

    dataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/obsidian-livesync/data";
      description = "Path to store Obsidian LiveSync data.";
    };

    configPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/obsidian-livesync/etc";
      description = "Path to store Obsidian LiveSync config.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "obsidian-livesync"; }
      ];
    };

    sops.secrets."obsidian-livesync_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "obsidian-livesync_env";
      owner = "container-user";
      restartUnits = [
        "podman-obsidian-livesync.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataPath} 0755 container-user users -"
      "d ${cfg.configPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.obsidian-livesync = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=obsidian-livesync"
      ];

      environment = {
        COUCHDB_USER = "couchdb";
      };

      environmentFiles = [ config.sops.secrets."obsidian-livesync_env".path ];

      volumes = [
        "${cfg.dataPath}:/opt/couchdb/data"
        "${cfg.configPath}:/opt/couchdb/etc/local.d"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.obsidian-livesync.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.obsidian-livesync.entrypoints" = "websecure";
        "traefik.http.routers.obsidian-livesync.service" = "obsidian-livesync";
        "traefik.http.services.obsidian-livesync.loadbalancer.server.port" = "5984";
        "traefik.http.routers.obsidian-livesync.tls" = "true";
        "traefik.http.routers.obsidian-livesync.middlewares" = "obsidiancors";
        "traefik.http.routers.obsidian-livesync.tls.certresolver" = "myresolver";
        "traefik.http.middlewares.obsidiancors.headers.accesscontrolallowmethods" = "GET,PUT,POST,HEAD,DELETE";
        "traefik.http.middlewares.obsidiancors.headers.accesscontrolallowheaders" = "accept,authorization,content-type,origin,referer";
        "traefik.http.middlewares.obsidiancors.headers.accesscontrolalloworiginlist" = "app://obsidian.md,capacitor://localhost,http://localhost";
        "traefik.http.middlewares.obsidiancors.headers.accesscontrolmaxage" = "3600";
        "traefik.http.middlewares.obsidiancors.headers.addvaryheader" = "true";
        "traefik.http.middlewares.obsidiancors.headers.accessControlAllowCredentials" = "true";
      };
    };

    systemd.services."podman-obsidian-livesync".after = [
      "podman-network-obsidian-livesync-container-user.service"
      "podman-network-traefik-container-user.service"
    ];
    systemd.services."podman-obsidian-livesync".requires = [
      "podman-network-obsidian-livesync-container-user.service"
      "podman-network-traefik-container-user.service"
    ];
  };
}
