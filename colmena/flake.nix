{
  description = "My NixOS Cloud Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    colmena.url = "github:zhaofengli/colmena";
    disko.url = "github:nix-community/disko";
    # Use nixos-raspberrypi over nixos-hardware for its binary cache of the Pi kernel
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    musy-player = {
      url = "git+ssh://git@github.com/Quadrubo/musy-player";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      nixpkgs-unstable,
      colmena,
      disko,
      nixos-raspberrypi,
      musy-player,
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
          musy = [
            sops-nix.nixosModules.sops
            nixos-raspberrypi.lib.inject-overlays
            nixos-raspberrypi.nixosModules.trusted-nix-caches
            nixos-raspberrypi.nixosModules.raspberry-pi-3.base
            nixos-raspberrypi.nixosModules.sd-image
            ./hosts/musy/configuration.nix
            (
              { ... }:
              {
                networking.hostName = "musy";
              }
            )
          ];
          homy = [
            sops-nix.nixosModules.sops
            nixos-raspberrypi.lib.inject-overlays
            nixos-raspberrypi.nixosModules.trusted-nix-caches
            nixos-raspberrypi.nixosModules.raspberry-pi-4.base
            nixos-raspberrypi.nixosModules.sd-image
            ./hosts/homy/configuration.nix
            (
              { ... }:
              {
                networking.hostName = "homy";
              }
            )
          ];
        };

        serverIps = builtins.fromJSON (builtins.readFile ./hosts.json);

        nixosConfigurations = {
          publy = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit nixpkgs-unstable; };
            modules = hostModules.publy;
          };
          servy = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit nixpkgs-unstable; };
            modules = hostModules.servy;
          };
          musy = nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit nixos-raspberrypi nixpkgs-unstable musy-player;
            };
            modules = hostModules.musy;
          };
          homy = nixpkgs.lib.nixosSystem {
            specialArgs = { inherit nixos-raspberrypi nixpkgs-unstable; };
            modules = hostModules.homy;
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

              nodeNixpkgs = builtins.mapAttrs (
                _: host: import nixpkgs { system = host.config.nixpkgs.hostPlatform.system; }
              ) nixosConfigurations;
              nodeSpecialArgs = builtins.mapAttrs (_: host: host._module.specialArgs) nixosConfigurations;
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

            musy =
              { ... }:
              {
                deployment = {
                  targetHost = serverIps.musy;
                  targetUser = "colmena";
                };

                imports = hostModules.musy;
              };

            homy =
              { ... }:
              {
                deployment = {
                  targetHost = serverIps.homy;
                  targetUser = "colmena";
                };

                imports = hostModules.homy;
              };
          };

          inherit allMonitoringEndpoints;

          colmenaHive = colmena.lib.makeHive inputs.self.outputs.colmena;
        };
      }
    );
}
