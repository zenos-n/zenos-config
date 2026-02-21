{
  description = "ZenOS - System Configurations";

  inputs = {
    # Update this to your absolute local path
    zenpkgs.url = "path:/home/doromiert/Projects/zenpkgs-2";
  };

  outputs =
    { self, zenpkgs }:
    let
      nixpkgs = zenpkgs.inputs.nixpkgs;
      lib = nixpkgs.lib;
      inputs = { inherit nixpkgs zenpkgs self; };

      zenCore = zenpkgs.lib.core { inherit lib inputs; };

      # 1. Base Configurations
      nixosConfigurations = zenCore.mkHosts {
        root = ./hosts;
        modules = [
          zenpkgs.nixosModules.default
        ];
      };

      # 2. ISO Configuration Generator
      # Injects the NixOS installation-cd module into a clone of the host config
      mkIso =
        hostConfig:
        hostConfig.extendModules {
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            # Optional: Speed up ISO build times for testing
            (
              { lib, ... }:
              {
                isoImage.squashfsCompression = "gzip -Xcompression-level 1";
                isoImage.isoBaseName = "zenos";
              }
            )
          ];
        };

    in
    {
      inherit nixosConfigurations;

      # 3. Expose ISOs as buildable packages
      # This dynamically creates a `-iso` target for every host in `hosts/`
      packages.x86_64-linux = lib.mapAttrs' (
        name: config: lib.nameValuePair "${name}-iso" (mkIso config).config.system.build.isoImage
      ) nixosConfigurations;
    };
}
