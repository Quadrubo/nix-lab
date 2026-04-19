{
  description = "My NixOS Cloud Infrastructure";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # TODO: switch back to 25.11 once this backport was merged https://github.com/NixOS/nixpkgs/pull/483309
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    colmena.url = "github:zhaofengli/colmena";
    disko.url = "github:nix-community/disko";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      colmena,
      disko,
      sops-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }:
      let
        system = "x86_64-linux";

        hostModules = {
          publy = [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ./hosts/publy/disko-config.nix
            ./hosts/publy/configuration.nix
            (
              { ... }:
              {
                networking.hostName = "publy";
              }
            )
          ];
          servy = [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ./hosts/servy/disko-config.nix
            ./hosts/servy/configuration.nix
            (
              { ... }:
              {
                networking.hostName = "servy";
              }
            )
          ];
        };

        serverIps = builtins.fromJSON (builtins.readFile ./hosts.json);

        nixosConfigurations = {
          publy = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = hostModules.publy;
          };
          servy = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = hostModules.servy;
          };
        };

        # Collect monitoring endpoints from all hosts
        allMonitoringEndpoints = nixpkgs.lib.concatMap (
          hostName: nixosConfigurations.${hostName}.config.myServices.monitoring.endpoints
        ) (builtins.attrNames nixosConfigurations);
      in
      {
        systems = [ system ];

        flake = {
          inherit nixosConfigurations;

          colmena = {
            meta = {
              nixpkgs = import nixpkgs {
                inherit system;
                overlays = [ ];
              };
            };

            publy =
              { ... }:
              {
                deployment = {
                  targetHost = serverIps.publy;
                  targetUser = "colmena";
                  tags = [ "public" ];
                };

                imports = hostModules.publy ++ [
                  (
                    { ... }:
                    {
                      myServices.gatus.endpoints = allMonitoringEndpoints;
                    }
                  )
                ];
              };

            servy =
              { ... }:
              {
                deployment = {
                  targetHost = serverIps.servy;
                  targetUser = "colmena";
                  tags = [ "public" ];
                };

                imports = hostModules.servy;
              };
          };

          inherit allMonitoringEndpoints;

          colmenaHive = colmena.lib.makeHive inputs.self.outputs.colmena;
        };
      }
    );
}
