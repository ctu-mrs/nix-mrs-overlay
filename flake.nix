{
  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
  };

  outputs = inputs: 
    let
      system = "x86_64-linux";
      
      # Load the dynamic overlay
      mrsOverlay = import ./mrs-overlay.nix;

      # Instantiate nixpkgs with BOTH the ROS overlay and the dynamic MRS overlay
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ 
          inputs.nix-ros-overlay.overlays.default 
          mrsOverlay
        ];
      };

    in {
      # Expose the overlay for others to consume
      overlays.default = mrsOverlay;

      # Expose the built packages
      packages.${system} = {
        
        # The CI Target: Bundle all dynamically generated packages together
        all = pkgs.symlinkJoin {
          name = "mrs-entire-ecosystem";
          paths = builtins.attrValues (
            builtins.intersectAttrs (builtins.fromJSON (builtins.readFile ./deps.json)) pkgs
          );
        };
        
      } // (builtins.intersectAttrs (builtins.fromJSON (builtins.readFile ./deps.json)) pkgs);
    };
}
