{
  description = "ZenOS - System Configurations";

  inputs = {
    zenpkgs.url = "path:/home/doromiert/Projects/zenpkgs-2";
  };

  outputs =
    { self, zenpkgs }:
    let
      nixpkgs = zenpkgs.inputs.nixpkgs;
      lib = nixpkgs.lib;

      # Passed down via specialArgs so all modules can access flake inputs
      inputs = { inherit nixpkgs zenpkgs self; };

      zenCore = zenpkgs.lib.core;

      nixosConfigurations = zenCore.mkHosts {
        root = ./hosts;
        specialArgs = {
          inherit inputs;
          # Ensure pkgs is NOT defined here
        };
        modules = [
          zenpkgs.nixosModules.default
          {
            # Instruct the module system to build its own pkgs instance,
            # which safely allows ISO overlays to be merged.
            nixpkgs.hostPlatform = "x86_64-linux";
            nixpkgs.overlays = [ zenpkgs.overlays.default ];
          }
        ];
      };

      mkIso =
        hostConfig:
        hostConfig.extendModules {
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (
              { lib, ... }:
              {
                image.baseName = lib.mkForce "zenos";
              }
            )
          ];
        };
    in
    {
      inherit nixosConfigurations;

      # Correctly mapped to x86_64-linux only
      packages.x86_64-linux = lib.mapAttrs' (
        name: config: lib.nameValuePair "${name}-iso" (mkIso config).config.system.build.isoImage
      ) nixosConfigurations;
    };
}
