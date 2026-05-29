final: prev:

let
  rosPkgs = prev.rosPackages.jazzy;
  depsMap = builtins.fromJSON (builtins.readFile ./deps.json);

  # Map custom external C++ libraries here
  systemDeps = {
    "Eigen3" = prev.eigen;
    "yaml-cpp" = prev.yaml-cpp;
    "boost" = prev.boost;
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
      
      # STRICT GIT FETCHING
      # We trust the JSON to always provide the remote and branch.
      src = let
        fetchedRepo = builtins.fetchGit {
          url = pkgData.git_remote;
          ref = pkgData.git_branch;
        };
      in
      if pkgData.path == "" then fetchedRepo else "${fetchedRepo}/${pkgData.path}";
      
      buildType = "ament_cmake";
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.dependencies);
    }
  ) depsMap;

in
mrsPackages
