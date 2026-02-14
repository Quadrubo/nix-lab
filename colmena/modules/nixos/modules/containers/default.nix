{ config, lib, ... }:

with lib;

let
  hasContainers = config.virtualisation.oci-containers.containers != { };
in
{
  config = mkIf hasContainers {
    virtualisation.podman = {
      enable = true;
      # dockerCompat = true;
      # defaultNetwork.settings.dns_enabled = true;
      # autoPrune.enable = true;
    };

    virtualisation.oci-containers.backend = "podman";

    users.users.container-user = {
      isNormalUser = true;
      linger = true;
      uid = 1000;
      subUidRanges = [
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 65536;
        }
      ];
    };
  };
}
