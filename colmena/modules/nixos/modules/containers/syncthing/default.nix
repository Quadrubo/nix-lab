{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.syncthing;
in
{
  options.myServices.syncthing = {
    enable = mkEnableOption "Syncthing";

    image = mkOption {
      type = types.str;
      default = "syncthing/syncthing:2"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Syncthing.";
    };

    hostName = mkOption {
      type = types.str;
      default = "servy-syncthing";
      description = "Container hostname for Syncthing.";
    };

    dataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/syncthing/data";
      description = "Path to store Syncthing data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "syncthing"; }
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataPath} 0755 container-user users -"
    ];

    networking.firewall.allowedTCPPorts = [ 22000 ];
    networking.firewall.allowedUDPPorts = [ 22000 21027 ];

    virtualisation.oci-containers.containers.syncthing = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=syncthing"
        "--hostname=${cfg.hostName}"
      ];

      ports = [
        "22000:22000"
        "22000:22000/udp"
        "21027:21027/udp"
      ];

      # environment = {
      #   PUID = "1000";
      #   PGID = "1000";
      # };

      volumes = [
        "${cfg.dataPath}:/var/syncthing"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.syncthing.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.syncthing.entrypoints" = "websecure";
        "traefik.http.routers.syncthing.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-syncthing".after = [ "podman-network-syncthing-container-user.service" ];
    systemd.services."podman-syncthing".requires = [ "podman-network-syncthing-container-user.service" ];
  };
}
