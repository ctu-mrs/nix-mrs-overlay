final: prev:

let
  rosPkgs = prev.rosPackages.jazzy;
  depsMap = builtins.fromJSON (builtins.readFile ./deps.json);

# In overlay.nix
  systemDeps = {
    "eigen" = prev.eigen;
    "libboost-dev" = prev.boost;
    "libopencv-dev" = prev.opencv;
    "yaml-cpp" = prev.yaml-cpp;
  };

  resolveDep = name:
    let
      nixName = builtins.replaceStrings ["_"] ["-"] name;
    in
    if builtins.hasAttr name systemDeps then systemDeps.${name}
    else if builtins.hasAttr name depsMap then final.${name}   
    else if builtins.hasAttr nixName rosPkgs then rosPkgs.${nixName}
    else if builtins.hasAttr name rosPkgs then rosPkgs.${name}
    else builtins.trace "⚠️ WARNING: Dependency '${name}' not found!" null;

mrsPackages = prev.lib.mapAttrs (pkgName: pkgData:
    rosPkgs.buildRosPackage {
      pname = pkgName;
      
      # THE NEW FIX: Use the extracted version instead of "dynamic"
      version = pkgData.version;
      
      src = builtins.fetchGit {
          url = pkgData.git_remote;
          ref = pkgData.git_branch;
      };
      
      buildType = "ament_cmake";
      
# Build tools (CMake, generators, pkg-config)
      nativeBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.buildtool_depends);
      
      # C++ libraries to link against
      buildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.build_depends);
      
      # Runtime dependencies and shared libraries
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.exec_depends);
      
      # Testing frameworks (gtest, ament_lint)
      checkInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.test_depends);

      doCheck = false;
      separateDebugInfo = false;
      dontStrip = true;

      # THE FIX: Force the creation of the $out folder!
      # This guarantees Nix won't crash on metapackages or macro-only repos 
      # that fail to create an install directory natively.
      postInstall = ''
        mkdir -p $out
      '';
    }
  ) depsMap;

in
mrsPackages
