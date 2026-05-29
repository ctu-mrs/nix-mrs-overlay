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
    if systemDeps ? ${name} then systemDeps.${name}
    else if final ? ${name} then final.${name}
    else if rosPkgs ? ${nixName} then rosPkgs.${nixName}
    else if rosPkgs ? ${name} then rosPkgs.${name}
    else builtins.trace "⚠️ WARNING: Dependency '${name}' not found!" null;

  mrsPackages = final.lib.mapAttrs (pkgName: pkgData:
    rosPkgs.buildRosPackage {
      pname = pkgName;
      version = "dynamic";
      
      src = if pkgData.git_remote != null && pkgData.git_branch != null then
        "${builtins.fetchGit {
          url = pkgData.git_remote;
          ref = pkgData.git_branch;
        }}/${pkgData.path}"
      else
        "${workspacePath}/${pkgData.path}";
      
      buildType = "ament_cmake";
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.dependencies);
    }
  ) depsMap;

in
mrsPackages
