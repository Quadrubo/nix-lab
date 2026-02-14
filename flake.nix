{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.colmena.url = "github:zhaofengli/colmena";

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      colmena,
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfreePredicate =
                pkg:
                builtins.elem (nixpkgs.lib.getName pkg) [
                  "terraform"
                ];
            };
            pkgs-unstable = import nixpkgs-unstable { inherit system; };
            inherit system;
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        {
          pkgs,
          system,
          pkgs-unstable,
        }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              just
              terraform
              colmena.packages.${system}.colmena
              jq
              sops
              ssh-to-age
              compose2nix
            ];
          };
        }
      );
    };
}
