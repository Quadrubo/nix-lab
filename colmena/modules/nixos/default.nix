{
  config,
  pkgs,
  lib,
  inputs,
  ...

}:

with lib;

let
  cfg = config;
in
{
  imports =
    lib.fileset.toList (lib.fileset.fileFilter (file: file.name == "default.nix") ./modules/containers)
    ++ lib.fileset.toList (lib.fileset.fileFilter (file: file.name == "default.nix") ./modules/general)
    ++ lib.fileset.toList (
      lib.fileset.fileFilter (file: file.name == "default.nix") ./modules/services
    );
}
