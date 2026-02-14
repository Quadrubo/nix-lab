{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.podman;

  networkServices = listToAttrs (
    map (net: {
      name = "podman-network-${net}";
      value = {
        path = [ pkgs.podman ];
        script = "podman network exists ${net} || podman network create ${net}";
        serviceConfig = {
          Type = "oneshot";
          User = "container-user";
          RemainAfterExit = true;
        };
        wantedBy = [ "multi-user.target" ];
      };
    }) cfg.networks
  );

  loginService = optionalAttrs cfg.ghcr.enable {
    "podman-registry-login-ghcr" = {
      description = "Login to GHCR for Podman";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "container-user";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "podman-ghcr-login" ''
          cat ${cfg.ghcr.tokenFile} | \
          ${pkgs.podman}/bin/podman login ghcr.io \
            --username ${cfg.ghcr.username} \
            --password-stdin
        '';
      };
    };
  };

in
{
  options.myServices.podman = {
    enable = mkEnableOption "Podman Helpers";

    networks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Podman networks to create automatically.";
    };

    ghcr = {
      enable = mkEnableOption "Login to GHCR";
      username = mkOption {
        type = types.str;
        default = "Quadrubo";
      };
      tokenFile = mkOption {
        type = types.path;
        description = "Path to the secret file containing the GHCR token";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services = networkServices // loginService;
  };
}
