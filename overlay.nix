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
      version = "dynamic";
      
      # (Keep your existing src fetching logic here)
      src = let
        fetchedRepo = builtins.fetchGit {
          url = pkgData.git_remote;
          ref = pkgData.git_branch;
        };
      in
      if pkgData.path == "" then fetchedRepo else "${fetchedRepo}/${pkgData.path}";
      
      buildType = "ament_cmake";
      
      # THE FIX: Safely route dependencies to their strict environments
      buildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.build_depends);
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.exec_depends);
      checkInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.test_depends);

      # Disable tests by default to prevent testing frameworks from bloating the build graph
      doCheck = false;
    }
  ) depsMap;

in
mrsPackages
