{
  description = "ZenOS - System Configurations";

  inputs = {
    zenpkgs.url = "path:/home/doromiert/Projects/zenpkgs-2";
    #zenpkgs.url = "github:zenos-n/zenpkgs";

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
              { lib, pkgs, ... }:
              {
                environment.systemPackages = [
                  pkgs.fzf
                  pkgs.jq
                  pkgs.parted
                ];
                image.baseName = lib.mkForce "zenos";

                environment.etc."iso-config/source".source = self;
                environment.etc."iso-config/zenpkgs".source = zenpkgs;
                environment.shellAliases.zen-install = "${pkgs.writeShellScript "zen-install" (
                  builtins.readFile ./scripts/zen-install.sh
                )}";

                # systemd-tmpfiles to make it show up at /iso-config
                systemd.tmpfiles.rules = [
                  "L+ /iso-config - - - - /etc/iso-config/source"
                ];
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
