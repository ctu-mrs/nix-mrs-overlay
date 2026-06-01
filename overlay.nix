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
    "moreutils" = prev.moreutils;
    "tmux" = prev.tmux;
    "tmuxinator" = prev.tmuxinator;
    "libncurses" = prev.ncurses;
    "libncurses-dev" = prev.ncurses;
  };

  resolveDep = name:
    let
      nixName = builtins.replaceStrings ["_"] ["-"] name;
    in
    if builtins.hasAttr name systemDeps then systemDeps.${name}

    # THE FIX: Route internal ROS dependencies to your protected namespace!
    else if builtins.hasAttr name depsMap then final.mrsCustomPkgs.${name}

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
          rev = pkgData.git_rev;
          # ref = pkgData.git_branch;
        };
      in
      if pkgData.path == "" then fetchedRepo else fetchedRepo + "/${pkgData.path}";

      buildType = "ament_cmake";

      # This will automatically propagate to ExternalProject_Add builds like NLopt!
      env.NIX_CFLAGS_COMPILE = "-Wno-error=nonnull -Wno-nonnull -Wno-register -DPyEval_CallObject=PyObject_CallObject";

      # Prevents Nix from crashing on packages that don't compile binaries
      separateDebugInfo = false;
      dontStrip = true;

      # Strictly routed ROS dependencies to prevent ARG_MAX compiler crashes
      nativeBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.buildtool_depends);
      buildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.build_depends);
      propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep (pkgData.exec_depends ++ (pkgData.build_export_depends or [])));
      checkInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.test_depends);

      doCheck = false;

      # Guarantees the $out directory exists for metapackages
      postInstall = ''
        mkdir -p $out
      '';
    }
  ) depsMap;

in {
  # THE FIX: Wrap the packages in a namespace so they don't overwrite NixOS system libraries!
  mrsCustomPkgs = mrsPackages;
}
