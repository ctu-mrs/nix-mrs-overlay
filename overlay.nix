{ inputs }:

final: prev: 
let
  ros = final.rosPackages.jazzy;
in
{
  mrs_msgs = ros.buildRosPackage {
    pname = "mrs_msgs";
    version = "nix";
    src = inputs.mrs_msgs;
    buildType = "ament_cmake";
    nativeBuildInputs = [
      ros.ament-cmake
      ros.rosidl-default-generators
    ];

    propagatedBuildInputs = [
      ros.std-msgs
      ros.geometry-msgs
    ];
  };


  mrs_uav_testing = ros.buildRosPackage {
    pname = "mrs_cmake";
    version = "nix";
    src = inputs.mrs_cmake;
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
    src = inputs.mrs_lib;
    buildType = "ament_cmake";
    nativeBuildInputs = [ ros.ament-cmake ];
    propagatedBuildInputs = [ 
      final.mrs_msgs
      ros.sensor-msgs
      final.mrs_cmake
    ];
  };
}
