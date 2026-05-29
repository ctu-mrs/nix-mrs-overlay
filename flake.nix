{
  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
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
      depsKeys = builtins.attrNames (builtins.fromJSON (builtins.readFile ./deps.json));

      # 2. Safely pluck ONLY those specific packages from the pkgs tree
      mrsPackages = pkgs.lib.genAttrs depsKeys (name: pkgs.${name});

    in {
      # Expose the overlay for others to consume
      overlays.default = mrsOverlay;

      # Expose the built packages safely
      packages.${system} = let
        
        # Create the bundle derivation once
        mrsBundle = pkgs.symlinkJoin {
          name = "mrs-entire-ecosystem";
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
