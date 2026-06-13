{ pkgs, system, inputs }:

let
  depsMap = builtins.removeAttrs
    (builtins.fromJSON (builtins.readFile ./deps.json)) [ "_comment" ];

  mrsPkgs = builtins.attrValues (
    pkgs.lib.genAttrs (builtins.attrNames depsMap)
      (name: pkgs.mrsCustomPkgs.${name})
  );
in
pkgs.mkShell {
  name = "mrs-dev-${system}";

  packages = mrsPkgs ++ [
    pkgs.colcon
    pkgs.cmake
    pkgs.git
    pkgs.tmux
    pkgs.tmuxinator
  ];
}
