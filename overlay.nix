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
    else builtins.trace "⚠️ WARNING: Dependency '${name}' not found!"
    null;

  mrsPackages = prev.lib.mapAttrs (pkgName: pkgData:
    let
      # Shared source extraction for both ROS and Non-ROS packages
      fetchedRepo = builtins.fetchGit {
        url = pkgData.git_remote;
        rev = pkgData.git_rev;
        # ref = pkgData.git_branch;
      };

      srcPath = if (pkgData.path or "") == "" then fetchedRepo else fetchedRepo + "/${pkgData.path}";

      # Pre-resolve exec_depends for the raw_copy derivation
      resolvedExecDepends = builtins.filter (x: x != null) (builtins.map resolveDep (pkgData.exec_depends or []));
    in

    # --- 1. NON-ROS PACKAGE (Raw Copy) ---
    if (pkgData.build_type or "") == "raw_copy" then

      prev.stdenv.mkDerivation {

        pname = pkgName;
        version = pkgData.version;
        src = srcPath;

        # Disable standard C/C++ build phases
        dontConfigure = true;
        dontBuild = true;

        # Keep debug symbols intact for pre-compiled binaries
        dontStrip = true;

        # Target the specific sub-folder defined in the JSON (defaults to root)
        installPhase = ''
          mkdir -p $out
          cd ${pkgData.source_dir or "."}
          cp -a * $out/
        '';

        propagatedBuildInputs = resolvedExecDepends;
      }

    # --- 2. STANDARD ROS PACKAGE ---
    else

      rosPkgs.buildRosPackage {

        pname = pkgName;
        version = pkgData.version;
        src = srcPath;

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
  # Wrap the packages in a namespace so they don't overwrite NixOS system libraries!
  mrsCustomPkgs = mrsPackages;
}
