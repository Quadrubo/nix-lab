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
      name = "podman-network-${net.name}-${net.user}";
      value = {
        path = [ pkgs.podman ];
        script = "podman network exists ${net.name} || podman network create ${net.name}";
        serviceConfig = {
          Type = "oneshot";
          User = net.user;
          RemainAfterExit = true;
        } // optionalAttrs (net.group != null) {
          Group = net.group;
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
      type = types.listOf (types.submodule ({ ... }: {
        options = {
          name = mkOption {
            type = types.str;
            description = "Podman network name.";
          };
          user = mkOption {
            type = types.str;
            default = "container-user";
            description = "User that owns the rootless network.";
          };
          group = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Group used for the network unit, if needed.";
          };
        };
      }));
      default = [ ];
      description = "List of Podman networks to create automatically (per user).";
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
