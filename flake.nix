{
  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
    
    src_mrs_msgs = { url = "github:ctu-mrs/mrs_msgs/nix"; flake = false; };
    src_mrs_cmake = { url = "github:ctu-mrs/mrs_cmake/nix"; flake = false; };
    src_mrs_lib = { url = "github:ctu-mrs/mrs_lib/nix"; flake = false; };
    src_mrs_uav_testing = { url = "github:ctu-mrs/mrs_uav_testing/nix"; flake = false; };
    src_mrs_uav_hw_api = { url = "github:ctu-mrs/mrs_uav_hw_api/nix"; flake = false; };
    src_mrs_multirotor_simulator = { url = "github:ctu-mrs/mrs_multirotor_simulator/nix"; flake = false; };
  };

  outputs = inputs: 
    let
      system = "x86_64-linux";
      
      # 1. Define your custom overlay
      mrsOverlay = import ./overlay.nix { inherit inputs; };

      # 2. Instantiate nixpkgs with BOTH the ROS overlay and your custom overlay
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ 
          inputs.nix-ros-overlay.overlays.default 
          mrsOverlay 
        ];
      };
    in {
      # Export the overlay for other flakes to use
      overlays.default = mrsOverlay;

      # 3. Expose the built packages to the Nix CLI
      packages.${system} = {

        mrs_msgs = pkgs.mrs_msgs;
        mrs_cmake = pkgs.mrs_cmake;
        mrs_lib = pkgs.mrs_lib;
        mrs_uav_testing = pkgs.mrs_uav_testing;
        mrs_uav_hw_api = pkgs.mrs_uav_hw_api;
        mrs_multirotor_simulator = pkgs.mrs_multirotor_simulator;
        
        # ... list your other packages here ...

        # THE MAGIC TARGET: Bundle them all together for CI!
        all = pkgs.symlinkJoin {
          name = "mrs-entire-ecosystem";
          paths = [
            pkgs.mrs_msgs
            pkgs.mrs_cmake
            pkgs.mrs_lib
            pkgs.mrs_uav_testing
            pkgs.mrs_uav_hw_api
            pkgs.mrs_multirotor_simulator
          ];
        };
      };
    };
}
