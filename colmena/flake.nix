{
  description = "My NixOS Cloud Infrastructure";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # TODO: switch back to 25.11 once this backport was merged https://github.com/NixOS/nixpkgs/pull/483309
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
    disko.url = "github:nix-community/disko";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      colmena,
      disko,
      sops-nix,
      ...
    }:
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
    in
    {
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

      colmena =
        let
          serverIps = builtins.fromJSON (builtins.readFile ./hosts.json);
        in
        {
          meta = {
            nixpkgs = import nixpkgs {
              inherit system;
              overlays = [ ];
            };
          };

          # Defaults for all hosts
          # defaults =
          #   { pkgs, ... }:
          #   {
          #     deployment.targetUser = "root";
          #     imports = [ ./modules/base.nix ];
          #   };
          # Host: publy
          publy =
            { ... }:
            {
              deployment = {
                targetHost = serverIps.publy;
                targetUser = "colmena";
                tags = [
                  "public"
                ];
              };

              # Import host-specific config
              imports = hostModules.publy;
            };
          servy =
            { ... }:
            {
              deployment = {
                targetHost = serverIps.servy;
                targetUser = "colmena";
                tags = [
                  "public"
                ];
              };

              # Import host-specific config
              imports = hostModules.servy;
            };
          # Host: andrea
          # andrea =
          #   { name, nodes, ... }:
          #   {
          #     deployment.targetHost = "10.0.1.4"; # Replace with Andrea's Public IP!
          #     deployment.tags = [
          #       "db"
          #       "private"
          #     ];

          #     imports = [ ./hosts/andrea.nix ];
          #   };
        };

      colmenaHive = colmena.lib.makeHive self.outputs.colmena;
    };
}
