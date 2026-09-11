{ pkgs, ... }:
pkgs.writeTextDir "flake.nix" ''
  {
    description = "ZenOS installed system configuration";
    inputs.zenpkgs.url = "github:zenos-n/zenpkgs/migration/path-derived-dsl";
    outputs = inputs@{ self, zenpkgs }:
      (${builtins.readFile ./installed-hosts.nix}) {
        inherit inputs;
        configRoot = self;
      };
  }
''
