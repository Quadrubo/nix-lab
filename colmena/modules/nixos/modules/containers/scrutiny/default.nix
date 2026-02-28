{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.scrutiny;
in
{
  # TODO: see if scrutiny can be replaced by beszel SMART module.
  options.myServices.scrutiny = {
    enable = mkEnableOption "Scrutiny";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/analogj/scrutiny:v0.8.6-omnibus"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Scrutiny.";
    };

    configPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/scrutiny/config";
      description = "Path to store Scrutiny config.";
    };

    influxdbPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/scrutiny/influxdb";
      description = "Path to store Scrutiny InfluxDB data.";
    };

    udevPath = mkOption {
      type = types.str;
      default = "/run/udev";
      description = "Path to host udev runtime directory.";
    };

    devices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Block devices to pass through to Scrutiny.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "scrutiny"; }
      ];
    };

    # container-user needs access to the disk group to be able to read SMART data.
    users.users.container-user.extraGroups = mkAfter [ "disk" ];

    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 container-user users -"
      "d ${cfg.influxdbPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.scrutiny = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=scrutiny"
        "--cap-add=SYS_RAWIO"
        "--cap-add=SYS_ADMIN"
        "--group-add=keep-groups"
      ] ++ map (device: "--device=${device}") cfg.devices;

      volumes = [
        "${cfg.udevPath}:/run/udev:ro"
        "${cfg.configPath}:/opt/scrutiny/config"
        "${cfg.influxdbPath}:/opt/scrutiny/influxdb"
      ];

      # TODO: migrate Traefik ip allowlist/denylist handling when ready.
      # Previously used labels (do not enable yet):
      # "traefik.http.middlewares.scrutiny-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
      # "traefik.http.routers.scrutiny.middlewares" = "scrutiny-ipallowlist@docker";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.scrutiny.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.scrutiny.entrypoints" = "websecure";
        "traefik.http.routers.scrutiny.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-scrutiny".after = [ "podman-network-scrutiny-container-user.service" ];
    systemd.services."podman-scrutiny".requires = [ "podman-network-scrutiny-container-user.service" ];
  };
}
