{
  description = "The unified CTU MRS package overlay";

  inputs = {

    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";

    # We import the 50 repos strictly for their source code. 
    # We turn off "flake = true" because we DO NOT WANT their flake.nix files.
    # We only want their raw C++ source trees!
    src_mrs_msgs = { url = "github:ctu-mrs/mrs_msgs/nix"; flake = false; };
    src_mrs_cmake = { url = "github:ctu-mrs/mrs_cmake/nix"; flake = false; };
    src_mrs_lib = { url = "github:ctu-mrs/mrs_lib/nix"; flake = false; };
    # src_mrs_uav_testing = { url = "github:ctu-mrs/mrs_uav_testing/nix"; flake = false; };
  };

  outputs = inputs: {
    # We export the overlay so other flakes can use it
    overlays.default = import ./overlay.nix { inherit inputs; };
  };
}
