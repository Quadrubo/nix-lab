{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.onlyoffice-documentserver;
in
{
  options.myServices.onlyoffice-documentserver = {
    enable = mkEnableOption "OnlyOffice Document Server";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for OnlyOffice Document Server.";
    };

    image = mkOption {
      type = types.str;
      default = "onlyoffice/documentserver:9.3"; # renovate: docker
    };

    logsPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/onlyoffice-documentserver/logs";
      description = "Path to store OnlyOffice logs.";
    };

    dataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/onlyoffice-documentserver/Data";
      description = "Path to store OnlyOffice data.";
    };

    fontsPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/onlyoffice-documentserver/fonts";
      description = "Path to store OnlyOffice fonts.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "onlyoffice-documentserver"; }
      ];
    };

    sops.secrets."onlyoffice-documentserver_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "onlyoffice-documentserver_env";
      owner = "container-user";
      restartUnits = [
        "podman-onlyoffice-documentserver.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.logsPath} 0755 container-user users -"
      "d ${cfg.dataPath} 0755 container-user users -"
      "d ${cfg.fontsPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.onlyoffice-documentserver = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=onlyoffice-documentserver"
      ];

      environment = {
        METRICS_ENABLED = "false";
      };

      environmentFiles = [ config.sops.secrets."onlyoffice-documentserver_env".path ];

      volumes = [
        "${cfg.logsPath}:/var/log/onlyoffice"
        "${cfg.dataPath}:/var/www/onlyoffice/Data"
        "${cfg.fontsPath}:/usr/share/fonts"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.onlyoffice-documentserver.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.onlyoffice-documentserver.entrypoints" = "websecure";
        "traefik.http.routers.onlyoffice-documentserver.tls.certresolver" = "myresolver";
        "traefik.http.routers.onlyoffice-documentserver.middlewares" = "onlyoffice-headers";
        "traefik.http.middlewares.onlyoffice-headers.headers.customrequestheaders.X-Forwarded-Proto" = "https";
      };
    };

    systemd.services."podman-onlyoffice-documentserver".after = [
      "podman-network-onlyoffice-documentserver-container-user.service"
      "podman-network-traefik-container-user.service"
    ];
    systemd.services."podman-onlyoffice-documentserver".requires = [
      "podman-network-onlyoffice-documentserver-container-user.service"
      "podman-network-traefik-container-user.service"
    ];
  };
}
