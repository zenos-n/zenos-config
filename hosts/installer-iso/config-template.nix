{ inputs, pkgs, lib, ... }:
let
  # Retain the image's exact source graph, including local integration builds.
  pin = input: {
    url = "path:${input.outPath}";
  } // (if input ? inputs then {
    inputs = builtins.mapAttrs (_: pin) input.inputs;
  } else {
    flake = false;
  });
in
pkgs.writeTextDir "flake.nix" ''
  {
    description = "ZenOS installed system configuration";
    inputs.zenpkgs = ${lib.generators.toPretty { } (pin inputs.zenpkgs)};
    outputs = inputs@{ self, zenpkgs }:
      (${builtins.readFile ./installed-hosts.nix}) {
        inherit inputs;
        configRoot = self;
      };
  }
''
