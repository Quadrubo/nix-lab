{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.wireguard;
in
{
  options.myServices.wireguard = {
    enable = mkEnableOption "WireGuard VPN tunnel";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing the WireGuard private key.";
    };

    address = mkOption {
      type = types.str;
      description = "IP address for this host on the WireGuard network.";
      example = "192.168.60.1/24";
    };

    listenPort = mkOption {
      type = types.int;
      default = 0;
      description = "UDP port to listen on. Set on the server (e.g. 51820). 0 for random (clients).";
    };

    forward = {
      enable = mkEnableOption "IP forwarding and NAT masquerading for tunnel traffic";

      externalInterface = mkOption {
        type = types.str;
        description = "LAN interface to masquerade on (e.g. enp4s0).";
      };
    };

    peers = mkOption {
      type = types.listOf (types.submodule {
        options = {
          publicKey = mkOption {
            type = types.str;
            description = "Public key of the peer.";
          };

          allowedIPs = mkOption {
            type = types.listOf types.str;
            description = "Allowed IP ranges for this peer.";
          };

          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Endpoint (host:port). Set on clients pointing to the server.";
          };

          persistentKeepalive = mkOption {
            type = types.int;
            default = 0;
            description = "Keepalive interval in seconds. 0 to disable. Set to 25 on clients behind NAT.";
          };
        };
      });
      default = [ ];
      description = "List of WireGuard peers.";
    };
  };

  config = mkIf cfg.enable {
    sops.secrets."wireguard_private_key" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "wireguard_private_key";
    };

    networking.wireguard.interfaces.wg0 = {
      ips = [ cfg.address ];
      listenPort = cfg.listenPort;
      privateKeyFile = config.sops.secrets."wireguard_private_key".path;

      peers = map (peer: {
        inherit (peer) publicKey allowedIPs endpoint persistentKeepalive;
      }) cfg.peers;
    };

    networking.firewall.trustedInterfaces = [ "wg0" ];
    networking.firewall.allowedUDPPorts = mkIf (cfg.listenPort != 0) [ cfg.listenPort ];

    boot.kernel.sysctl."net.ipv4.ip_forward" = mkIf cfg.forward.enable 1;

    networking.nat = mkIf cfg.forward.enable {
      enable = true;
      internalInterfaces = [ "wg0" ];
      externalInterface = cfg.forward.externalInterface;
    };
  };
}
