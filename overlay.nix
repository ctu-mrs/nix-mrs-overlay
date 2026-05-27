{ inputs }:

final: prev: 
let
  ros = final.rosPackages.jazzy;
in
{
  mrs_msgs = ros.buildRosPackage {
    pname = "mrs_msgs";
    version = "nix";
    src = inputs.src_mrs_msgs;
    buildType = "ament_cmake";
    nativeBuildInputs = [
      ros.ament-cmake
      ros.rosidl-default-generators
    ];

    propagatedBuildInputs = [
      ros.std-msgs
      ros.geometry-msgs
      ros.std-srvs
      ros.sensor-msgs
    ];
  };

  mrs_cmake = ros.buildRosPackage {
    pname = "mrs_cmake";
    version = "nix";
    src = inputs.src_mrs_cmake;
    buildType = "ament_cmake";
    nativeBuildInputs = [
      ros.ament-cmake
    ];
    propagatedBuildInputs = [ 
    ];
  };

  mrs_lib = ros.buildRosPackage {
    pname = "mrs_lib";
    version = "nix";
    src = inputs.src_mrs_lib;
    buildType = "ament_cmake";
    nativeBuildInputs = [ ros.ament-cmake ];
    propagatedBuildInputs = [ 
      # non-ros
      final.eigen
      final.yaml-cpp
      final.boost

      # our
      final.mrs_msgs
      final.mrs_cmake

      # official ros
      ros.sensor-msgs
      ros.nav-msgs
      ros.ros-core
      ros.tf2-geometry-msgs
      ros.tf2-eigen
    ];
  };

  mrs_uav_testing = ros.buildRosPackage {
    pname = "mrs_uav_testing";
    version = "nix";
    src = inputs.src_mrs_uav_testing;
    buildType = "ament_cmake";
    nativeBuildInputs = [ ros.ament-cmake ];
    propagatedBuildInputs = [ 
      # our
      final.mrs_lib

      # official ros
      ros.backward-ros
    ];
  };
}
