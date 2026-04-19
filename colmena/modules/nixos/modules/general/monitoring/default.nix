{
  config,
  lib,
  ...
}:

with lib;

let
  endpointSubmodule =
    { ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          description = "Display name for this endpoint.";
        };

        group = mkOption {
          type = types.str;
          default = "";
          description = "Gatus group for this endpoint.";
        };

        url = mkOption {
          type = types.str;
          description = "URL to monitor.";
        };

        interval = mkOption {
          type = types.str;
          default = "1m";
          description = "How often to check this endpoint.";
        };

        conditions = mkOption {
          type = types.listOf types.str;
          default = [ "[STATUS] == 200" ];
          description = "Gatus conditions that must be met for the endpoint to be considered healthy.";
        };

        client = mkOption {
          type = types.attrs;
          default = { };
          description = "Gatus client configuration for this endpoint (e.g. ignore-redirect, timeout).";
        };

        alerts = mkOption {
          type = types.listOf types.attrs;
          default = [ ];
          description = "Per-endpoint alert overrides. Empty means use global alerting defaults.";
        };
      };
    };
in
{
  options.myServices.monitoring = {
    endpoints = mkOption {
      type = types.listOf (types.submodule endpointSubmodule);
      default = [ ];
      description = "Monitoring endpoints contributed by service modules on this host.";
    };
  };
}
