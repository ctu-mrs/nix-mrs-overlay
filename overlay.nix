final: prev:

let
  # --- THE TROJAN HORSE ---
  # An empty package that tricks Nix into passing the strict architecture evaluation,
  # while tricking CMake into gracefully falling back to macOS dummy macros.
  darwinDummy = name: prev.stdenv.mkDerivation {
    pname = "${name}-mac-dummy";
    version = "1.0.0";
    unpackPhase = "true";
    installPhase = "mkdir -p $out";
  };

  rosPkgs = prev.rosPackages.jazzy;

  # 1. Load the raw JSON and safely strip the comment using native builtins
  rawDepsMap = builtins.fromJSON (builtins.readFile ./deps.json);
  depsMap = builtins.removeAttrs rawDepsMap [ "_comment" ];

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
    "libpcl-all-dev" = prev.pcl;
    "apr" = prev.apr;
    "git" = prev.git;
  };

  # Keep our internal filter for your custom packages
  linuxOnlyDeps = [ 
    "lttng-tools" 
    "lttng-ust" 
    "lttng-modules" 
    "tracetools" 
    "ros2trace"
    "tracetools-launch"
    "tracetools-read"
    "tracetools-trace"
    "elfutils"
    "libcap"
  ];

  resolveDep = name:
    let
      nixName = builtins.replaceStrings ["_"] ["-"] name;
    in
    # Intercept and drop Linux-only packages if we are on a Mac
    if prev.stdenv.isDarwin && (builtins.elem name linuxOnlyDeps || builtins.elem nixName linuxOnlyDeps) then 
      builtins.trace "⚠️ MAC WORKAROUND: Dropping Linux-only dependency '${name}'" null

    else if builtins.hasAttr name systemDeps then systemDeps.${name}
    else if builtins.hasAttr name depsMap then final.mrsCustomPkgs.${name}
    else if builtins.hasAttr nixName rosPkgs then rosPkgs.${nixName}
    else if builtins.hasAttr name rosPkgs then rosPkgs.${name}
    else builtins.trace "⚠️ WARNING: Dependency '${name}' not found!"
    null;

  mrsPackages = prev.lib.mapAttrs (pkgName: pkgData:
    let
      fetchedRepo = builtins.fetchGit {
        url = pkgData.git_remote;
        rev = pkgData.git_rev;
      };

      srcPath = if (pkgData.path or "") == "" then fetchedRepo else fetchedRepo + "/${pkgData.path}";
      resolvedExecDepends = builtins.filter (x: x != null) (builtins.map resolveDep (pkgData.exec_depends or []));
    in

    # --- 1. NON-ROS PACKAGE (Raw Copy) ---
    if (pkgData.build_type or "") == "raw_copy" then
      prev.stdenv.mkDerivation {
        pname = pkgName;
        version = pkgData.version;
        src = srcPath;
        dontConfigure = true;
        dontBuild = true;
        dontStrip = true;
        installPhase = let
          mapping = pkgData.install_mapping or { "*" = "."; };
          copyCommands = prev.lib.mapAttrsToList (src: dest: 
            if src == "*" && dest == "." then "cp -a * $out/" 
            else "mkdir -p \"$out/$(dirname \"${dest}\")\"\ncp -a \"${src}\" \"$out/${dest}\""
          ) mapping;
        in "mkdir -p $out\n${builtins.concatStringsSep "\n" copyCommands}";
        propagatedBuildInputs = resolvedExecDepends;
      }

    else if pkgData.build_type == "cmake" then
        prev.stdenv.mkDerivation {
          pname = pkgName;
          version = pkgData.version;
          src = "${fetchedRepo}/${pkgData.path}";
          nativeBuildInputs = [ prev.cmake prev.pkg-config ];
          buildInputs = map resolveDep pkgData.build_depends;
          cmakeFlags = [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
        }

    # --- 2. STANDARD ROS PACKAGE ---
    else
      rosPkgs.buildRosPackage {
        pname = pkgName;
        version = pkgData.version;
        src = srcPath;
        buildType = "ament_cmake";
        __structuredAttrs = true;
        cmakeFlags = [ "-DCMAKE_NINJA_FORCE_RESPONSE_FILE=1" ];
        env.NIX_CFLAGS_COMPILE = "-Wno-error=nonnull -Wno-nonnull -Wno-register -DPyEval_CallObject=PyObject_CallObject";
        separateDebugInfo = false;
        dontStrip = true;
        nativeBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.buildtool_depends);
        buildInputs = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.build_depends);
        propagatedBuildInputs = builtins.filter (x: x != null) (builtins.map resolveDep (pkgData.exec_depends ++ (pkgData.build_export_depends or [])));
        passthru.test_depends = builtins.filter (x: x != null) (builtins.map resolveDep pkgData.test_depends);
        doCheck = false;
        postInstall = "mkdir -p $out";
      }
  ) depsMap;

in {
  mrsCustomPkgs = mrsPackages;

  # --- INJECT THE TROJAN HORSE INTO UPSTREAM ---
  # If we are on Darwin, overwrite the actual system tracing packages with our empty dummies.
  # nix-ros-overlay will blindly pull these instead of the real ones!
  lttng-tools = if prev.stdenv.isDarwin then darwinDummy "lttng-tools" else prev.lttng-tools;
  lttng-ust = if prev.stdenv.isDarwin then darwinDummy "lttng-ust" else prev.lttng-ust;
  lttng-modules = if prev.stdenv.isDarwin then darwinDummy "lttng-modules" else prev.lttng-modules;
  elfutils = if prev.stdenv.isDarwin then darwinDummy "elfutils" else prev.elfutils;
  libcap = if prev.stdenv.isDarwin then darwinDummy "libcap" else prev.libcap;
}
