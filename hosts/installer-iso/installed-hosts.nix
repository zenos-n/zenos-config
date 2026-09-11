{ inputs, configRoot }:
let
  nixpkgs = inputs.zenpkgs.inputs.nixpkgs;
  zenpkgs = inputs.zenpkgs;
  system = "x86_64-linux";
  lib = nixpkgs.lib;
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ zenpkgs.overlays.default ];
  };
  bootHooks = import (zenpkgs + "/lib/installer-boot.nix") {
    inherit pkgs lib;
    bootPackage = pkgs.zenos.theming.system.zenos-plymouth;
    refindInstaller = pkgs.zenos.system.zenos-refind-installer;
    refindTheme = pkgs.zenos.theming.system.zenos-refind-theme;
  };
  entries = builtins.readDir (configRoot + "/hosts");
  sources =
    input: [ input.outPath ] ++ lib.concatMap sources (builtins.attrValues (input.inputs or { }));
  names = builtins.filter (
    name:
    entries.${name} == "directory" && builtins.pathExists (configRoot + "/hosts/${name}/host.zcfg")
  ) (builtins.attrNames entries);
in
{
  nixosConfigurations = lib.genAttrs names (
    name:
    let
      host = configRoot + "/hosts/${name}";
      generated =
        pkgs.runCommand "zenos-installed-${name}.nix"
          {
            nativeBuildInputs = [
              zenpkgs.packages.${system}.zen-dsl
              (lib.getBin pkgs.nix)
            ];
            src = configRoot;
            hostName = name;
          }
          ''
            export NIX_REMOTE="local?root=$TMPDIR/parse-store"
            zen-dsl check "$src/hosts/$hostName/host.zcfg" --import-root "$src"
            zen-dsl compile "$src/hosts/$hostName/host.zcfg" --import-root "$src" -o "$out"
            nix-instantiate --parse "$out" >/dev/null
          '';
    in
    lib.nixosSystem {
      inherit system;
      modules = [
        zenpkgs.nixosModules.default
        bootHooks.common
        bootHooks.installed
        (import generated)
        {
          system.build.zenosGeneratedConfig = generated;
          system.extraDependencies = [
            configRoot
            generated
          ]
          ++ sources zenpkgs;
          environment.systemPackages = [ zenpkgs.packages.${system}.zen-dsl ];
          nix.registry.zenpkgs.flake = zenpkgs;
        }
      ];
    }
  );
}
