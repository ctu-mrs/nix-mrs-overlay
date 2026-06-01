{
  inputs = {
    nix-ros-overlay.url = "github:wentasah/nix-ros-overlay/build-env-prefix";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
  };

  outputs = inputs:
    let
      system = "x86_64-linux";

      # Load the dynamic overlay
      mrsOverlay = import ./overlay.nix;

      # Instantiate nixpkgs with BOTH the ROS overlay and the dynamic MRS overlay
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.nix-ros-overlay.overlays.default
          mrsOverlay
        ];
      };

      # 1. Lazily extract just the package names from your JSON
      rawDepsMap = builtins.fromJSON (builtins.readFile ./deps.json);
      
      # 2. Strip the comment out so it doesn't get treated as a package name
      cleanDepsMap = builtins.removeAttrs rawDepsMap [ "_comment" ];
      
      # 3. Get the keys (now guaranteed to only be actual packages)
      depsKeys = builtins.attrNames cleanDepsMap;
      
      # 4. Safely pluck ONLY those specific packages from your protected namespace
      mrsPackages = pkgs.lib.genAttrs depsKeys (name: pkgs.mrsCustomPkgs.${name});

    in {
      # Expose the overlay for others to consume
      overlays.default = mrsOverlay;

      # Expose the built packages safely
      packages.${system} = let

        # Create the bundle derivation once
        mrsBundle = pkgs.symlinkJoin {
          name = "mrs-nix-overlay";
          paths = builtins.attrValues mrsPackages;
        };

      in {

        # THE FIX: Tell Nix what to do when someone just types `nix build`
        default = mrsBundle;

        # Keep `all` as an explicit target for CI or scripts
        all = mrsBundle;

      } // mrsPackages; # Inject all the individual mrs_* packages into the output dictionary
    };
}
