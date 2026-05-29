final: prev:

let
  rosPkgs = final.rosPackages.jazzy;
  depsMap = builtins.fromJSON (builtins.readFile ./deps.json);
  workspacePath = ./src;

  # Map custom external C++ libraries here
  systemDeps = {
    "Eigen3" = final.eigen;
    "yaml-cpp" = final.yaml-cpp;
    "boost" = final.boost;
  };

  resolveDep = name:
    let
      nixName = builtins.replaceStrings ["_"] ["-"] name;
    in
    if builtins.hasAttr name systemDeps then systemDeps.${name}
    
    # THE FIX: Safely check our JSON map using builtins.hasAttr!
    # If the dependency is one of our repos, grab it from the final Nixpkgs scope.
    else if builtins.hasAttr name depsMap then final.${name}   
    
    else if builtins.hasAttr nixName rosPkgs then rosPkgs.${nixName}
    else if builtins.hasAttr name rosPkgs then rosPkgs.${name}
    else builtins.trace "⚠️ WARNING: Dependency '${name}' not found!" null;

  mrsPackages = final.lib.mapAttrs (pkgName: pkgData:
    rosPkgs.buildRosPackage {
      pname = pkgName;
      version = "dynamic";
      
      # Dynamically fetch from Git if available, otherwise fallback to local folder
      src = if pkgData.git_remote != null && pkgData.git_branch != null then
        let
          fetchedRepo = builtins.fetchGit {
            url = pkgData.git_remote;
            ref = pkgData.git_branch;
          };
        in
        # If the package is in the root of the repo, use the repo directly.
        # If it's nested (like a monorepo), append the sub-path.
        if pkgData.path == "" then fetchedRepo else "${fetchedRepo}/${pkgData.path}"
      else
        "${workspacePath}/${pkgData.path}";
      
      buildType = "ament_cmake";
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.dependencies);
    }
  ) depsMap;

in
mrsPackages
