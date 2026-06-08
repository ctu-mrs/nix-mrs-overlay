{
  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/develop";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
  };

  outputs = inputs:
    let
      supportedSystems = [ 
        "x86_64-linux"    # Standard PCs / Servers
        "aarch64-linux"   # Nvidia Jetsons / Raspberry Pi
        "aarch64-darwin"  # Apple Silicon Macs
      ];

      # Load the dynamic overlay once (it is architecture-agnostic)
      mrsOverlay = import ./overlay.nix;

    in {
      # Expose the overlay for others to consume
      overlays.default = mrsOverlay;

      # 2. Iterate over every system to generate specific packages
      packages = inputs.nixpkgs.lib.genAttrs supportedSystems (system:
        let
          # Instantiate nixpkgs for THIS specific system
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              inputs.nix-ros-overlay.overlays.default
              mrsOverlay
            ];
          };

          # Parse JSON dynamically for this system
          rawDepsMap = builtins.fromJSON (builtins.readFile ./deps.json);
          cleanDepsMap = builtins.removeAttrs rawDepsMap [ "_comment" ];
          depsKeys = builtins.attrNames cleanDepsMap;
          
          # Safely pluck ONLY specific packages from the protected namespace
          mrsPackages = pkgs.lib.genAttrs depsKeys (name: pkgs.mrsCustomPkgs.${name});

          # Create the bundle derivation for this system
          mrsBundle = pkgs.symlinkJoin {
            name = "mrs-nix-overlay-${system}";
            paths = builtins.attrValues mrsPackages;
          };

        in {
          # Tell Nix what to do when someone just types `nix build`
          default = mrsBundle;

          # Keep `all` as an explicit target for CI or scripts
          all = mrsBundle;

        } // mrsPackages # Inject all individual mrs_* packages into the output
      );
    };

    nixConfig = {
      extra-substituters = [
        "https://ros.cachix.org"
        "https://ctu-mrs.cachix.org"
      ];

      extra-trusted-public-keys = [
        "ros.cachix.org-1:dSyZxI8geDCJrwgvjRqjWSbgEX/PuEf747CSPe9HnHM="
        "ctu-mrs.cachix.org-1:dnw2ixFgGHfTb4bE1MWQTetAUJe9zqKUOBlrTjDuDMI="
      ];
    };
}
