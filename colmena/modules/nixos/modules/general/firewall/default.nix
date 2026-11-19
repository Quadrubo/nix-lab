{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myModules.firewall;

  hostsOption = mkOption {
    type = types.listOf types.str;
    description = "IPv4 addresses or CIDR ranges allowed to connect.";
  };

  portOption = mkOption {
    type = types.port;
    description = "Port to open.";
  };

  # Every allowed connection as protocol, port (or from:to range) and source host
  rules =
    map (rule: rule // { protocol = "tcp"; }) cfg.allowedTCPPortsFrom
    ++ map (rule: rule // { protocol = "udp"; }) cfg.allowedUDPPortsFrom
    ++ map (
      rule:
      rule
      // {
        protocol = "tcp";
        port = "${toString rule.from}:${toString rule.to}";
      }
    ) cfg.allowedTCPPortRangesFrom;

  lines =
    line:
    concatMapStrings (
      rule: concatMapStrings (host: line rule.protocol (toString rule.port) host + "\n") rule.hosts
    ) rules;
in
{
  options.myModules.firewall = {
    allowedTCPPortsFrom = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            port = portOption;
            hosts = hostsOption;
          };
        }
      );
      default = [ ];
      description = "TCP ports that only the listed hosts may connect to.";
    };

    allowedUDPPortsFrom = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            port = portOption;
            hosts = hostsOption;
          };
        }
      );
      default = [ ];
      description = "UDP ports that only the listed hosts may send to.";
    };

    allowedTCPPortRangesFrom = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            from = portOption;
            to = portOption;
            hosts = hostsOption;
          };
        }
      );
      default = [ ];
      description = "TCP port ranges that only the listed hosts may connect to.";
    };
  };

  config.networking.firewall = mkMerge [
    (mkIf config.networking.nftables.enable {
      extraInputRules = lines (
        protocol: port: host:
        "ip saddr ${host} ${protocol} dport ${replaceStrings [ ":" ] [ "-" ] port} accept"
      );
    })
    (mkIf (!config.networking.nftables.enable) {
      extraCommands = lines (
        protocol: port: host:
        "iptables -I nixos-fw -p ${protocol} -s ${host} --dport ${port} -j nixos-fw-accept"
      );
    })
  ];
}
