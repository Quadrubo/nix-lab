{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.beszel;
in
{
  options.myServices.beszel = {
    enable = mkEnableOption "Beszel";

    image = mkOption {
      type = types.str;
      default = "henrygd/beszel:0.18.4"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Beszel.";
    };

    dataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/beszel/beszel_data";
      description = "Path to store Beszel data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "beszel"; }
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.beszel = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=beszel"
      ];

      volumes = [
        "${cfg.dataPath}:/beszel_data"
      ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.beszel-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.beszel.middlewares" = "beszel-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.beszel.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.beszel.entrypoints" = "websecure";
        "traefik.http.routers.beszel.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-beszel".after = [ "podman-network-beszel-container-user.service" ];
    systemd.services."podman-beszel".requires = [ "podman-network-beszel-container-user.service" ];
  };
}