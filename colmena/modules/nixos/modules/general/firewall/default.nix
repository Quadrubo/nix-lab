{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myModules.firewall;
in
{
  options.myModules.firewall = {
    allowedTCPPortsFrom = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            port = mkOption {
              type = types.port;
              description = "TCP port to open.";
            };

            hosts = mkOption {
              type = types.listOf types.str;
              description = "IPv4 addresses allowed to connect.";
            };
          };
        }
      );
      default = [ ];
      description = "TCP ports that only the listed hosts may connect to.";
    };
  };

  config.networking.firewall =
    let
      rules =
        line:
        concatMapStrings (
          rule: concatMapStrings (host: line host (toString rule.port) + "\n") rule.hosts
        ) cfg.allowedTCPPortsFrom;
    in
    mkMerge [
      (mkIf config.networking.nftables.enable {
        extraInputRules = rules (host: port: "ip saddr ${host} tcp dport ${port} accept");
      })
      (mkIf (!config.networking.nftables.enable) {
        extraCommands = rules (
          host: port: "iptables -I nixos-fw -p tcp -s ${host} --dport ${port} -j nixos-fw-accept"
        );
      })
    ];
}
