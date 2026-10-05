{ pkgs, ... }:
pkgs.writeTextDir "flake.nix" ''
  {
    description = "ZenOS installed system configuration";
    inputs.zenpkgs = {
      url = ${builtins.toJSON (import ../../flake.nix).inputs.zenpkgs.url};
    };
    outputs = inputs@{ self, zenpkgs }:
      (${builtins.readFile ./installed-hosts.nix}) {
        inherit inputs;
        configRoot = self;
      };
  }
''
