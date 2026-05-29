final: prev:

let
  rosPkgs = prev.rosPackages.jazzy;
  depsMap = builtins.fromJSON (builtins.readFile ./deps.json);

  # Mapped system dependencies to match package.xml
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
      version = pkgData.version;
      
      # THE RESTORED FIX: Monorepo-safe path extraction
      # Using the '+' operator guarantees this remains a Path object for the unpackPhase.
      src = let
        fetchedRepo = builtins.fetchGit {
          url = pkgData.git_remote;
          ref = pkgData.git_branch;
          # rev = pkgData.git_rev; # Uncomment if locking commits for pure evaluation
        };
      in
      if pkgData.path == "" then fetchedRepo else fetchedRepo + "/${pkgData.path}";
      
      buildType = "ament_cmake";
      
      # Prevents Nix from crashing on packages that don't compile binaries
      separateDebugInfo = false;
      dontStrip = true;
      
      # Strictly routed ROS dependencies to prevent ARG_MAX compiler crashes
      nativeBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.buildtool_depends);
      buildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.build_depends);
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.exec_depends);
      checkInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.test_depends);

      doCheck = false;

      # Guarantees the $out directory exists for metapackages
      postInstall = ''
        mkdir -p $out
      '';
    }
  ) depsMap;

in
mrsPackages
