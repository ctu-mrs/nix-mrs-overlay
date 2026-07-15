final: prev:

let
  # --- THE TROJAN HORSE ---
  darwinDummy = name: prev.stdenv.mkDerivation {
    pname = "${name}-mac-dummy";
    version = "1.0.0";
    unpackPhase = "true";
    installPhase = "mkdir -p $out";
    meta = {
      platforms = prev.lib.platforms.all;
      badPlatforms = [];
    };
  };

  # CRITICAL FIX: This MUST track 'final' so it sees the .extend patches below!
  rosPkgs = final.rosPackages.jazzy;

  rawDepsMap = builtins.fromJSON (builtins.readFile ./deps.json);
  depsMap = builtins.removeAttrs rawDepsMap [ "_comment" ];

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
    "curl" = prev.curl;
    "libjsoncpp-dev" = prev.jsoncpp;
    "libjsoncpp" = prev.jsoncpp;
    "libtins-dev" = prev.libtins;
    "net-tools" = prev.net-tools;
    "nmap" = prev.nmap;
    "spdlog" = prev.spdlog;
    "vtk" = prev.vtk;
    "qtbase5-dev" = prev.qt5.qtbase;
  };

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
    "acl"
    "attr"
  ];

  resolveDep = name:
    let
      nixName = builtins.replaceStrings ["_"] ["-"] name;
    in
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
        # submodules = true;
      };
      srcPath = if (pkgData.path or "") == "" then fetchedRepo else fetchedRepo + "/${pkgData.path}";
      resolvedExecDepends = builtins.filter (x: x != null) (builtins.map resolveDep (pkgData.exec_depends or []));
    in
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

  mrsCustomPkgs = mrsPackages // {
    livox-sdk2 = if builtins.hasAttr "livox-sdk2" mrsPackages then 
      mrsPackages."livox-sdk2".overrideAttrs (old: {
        # Cleanly merge into the existing env attribute set to prevent Nix overlap errors
        env = (old.env or {}) // {
          NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") 
            + " -Wno-unknown-warning-option -Wno-deprecated-declarations -Wno-unused-private-field -Wno-delete-non-abstract-non-virtual-dtor -Wno-non-c-typedef-for-linkage -Wno-unused-const-variable -Wno-unused-parameter -Wno-ignored-qualifiers";
        };

        postPatch = (old.postPatch or "") + ''
          echo "Stripping aggressive -Werror flags from Livox CMake files..."
          # Livox hardcodes -Werror, which overrides Nix environment variables
          find . -type f -name "CMakeLists.txt" -exec sed -i 's/-Werror//g' {} +
          find . -type f -name "*.cmake" -exec sed -i 's/-Werror//g' {} +
          
          echo "Injecting warning suppressions directly into CMake..."
          sed -i '1i set(CMAKE_CXX_FLAGS "''${CMAKE_CXX_FLAGS} -Wno-error=deprecated-literal-operator -Wno-error=deprecated-declarations")' CMakeLists.txt
        '';
      }) 
    else {};

      rosbag2-transport = rosPrev.rosbag2-transport.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          echo "Fixing Clang TSA attribute placement vs brace initialization on macOS..."
          substituteInPlace src/rosbag2_transport/locked_priority_queue.hpp \
            --replace-fail 'size_t insert_sequence_number_{0} RCPPUTILS_TSA_GUARDED_BY(queue_mutex_);' \
                           'size_t insert_sequence_number_ RCPPUTILS_TSA_GUARDED_BY(queue_mutex_){0};'
        '';
      });

    # 2. Comprehensive fix for livox_ros_driver2 (macOS + Nix Sandbox + VTK Leak)
    livox_ros_driver2 = if builtins.hasAttr "livox_ros_driver2" mrsPackages then 
      mrsPackages."livox_ros_driver2".overrideAttrs (old: {
        buildInputs = (old.buildInputs or []) ++ [ 
          final.mrsCustomPkgs."livox-sdk2"
          prev.vtk 
          prev.qt5.qtbase 
        ];

        # Cleanly merge the C++ flags here as well
        env = (old.env or {}) // {
          NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") 
            + " -Wno-unknown-warning-option -Wno-deprecated-declarations -Wno-unused-private-field -Wno-delete-non-abstract-non-virtual-dtor -Wno-non-c-typedef-for-linkage -Wno-unused-const-variable -Wno-unused-parameter -Wno-ignored-qualifiers";
        };

        postPatch = (old.postPatch or "") + ''
	  echo "Fixing macOS 'long' vs 'long long' strictness for ROS 2 parameters..."
          find . -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \) -exec sed -i -E 's/std::vector<\s*long\s*>/std::vector<int64_t>/g' {} +
          find . -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \) -exec sed -i -E 's/std::vector<\s*long\s+int\s*>/std::vector<int64_t>/g' {} +
          find . -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \) -exec sed -i -E 's/\bvector<\s*long\s*>/vector<int64_t>/g' {} +

          echo "Bypassing pcl_ros VTK::GUISupportQt leak with a dummy target..."
          # Satisfies CMake's target requirement without actually linking Qt GUI libraries
          sed -i '1i add_library(VTK::GUISupportQt INTERFACE IMPORTED)' CMakeLists.txt

          echo "Fixing hardcoded Linux .so extensions for macOS compatibility..."
          # By removing 'lib' and '.so', CMake will dynamically search for .dylib on macOS and .so on Linux
          sed -i 's/liblivox_lidar_sdk_shared\.so/livox_lidar_sdk_shared/g' CMakeLists.txt

          echo "Stripping hardcoded /usr/local/lib path for Nix hermeticity..."
          sed -i 's|/usr/local/lib||g' CMakeLists.txt
        '';
      }) 
    else {};
  };

  lttng-tools = if prev.stdenv.isDarwin then darwinDummy "lttng-tools" else prev.lttng-tools;
  lttng-ust = if prev.stdenv.isDarwin then darwinDummy "lttng-ust" else prev.lttng-ust;
  lttng-modules = if prev.stdenv.isDarwin then darwinDummy "lttng-modules" else prev.lttng-modules;
  elfutils = if prev.stdenv.isDarwin then darwinDummy "elfutils" else prev.elfutils;
  libcap = if prev.stdenv.isDarwin then darwinDummy "libcap" else prev.libcap;
  acl = if prev.stdenv.isDarwin then darwinDummy "acl" else prev.acl;
  attr = if prev.stdenv.isDarwin then darwinDummy "attr" else prev.attr;

  glib = if prev.stdenv.isDarwin then prev.glib.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ [ "-Dlibelf=disabled" ];
  }) else prev.glib;

  openldap = if prev.stdenv.isDarwin then prev.openldap.overrideAttrs (old: {
    doCheck = false;
  }) else prev.openldap;

  laszip = if prev.stdenv.isDarwin then prev.laszip.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      echo "" > dll/CMakeLists.txt
    '';
  }) else prev.laszip;

  rosPackages = prev.rosPackages // {
    jazzy = prev.rosPackages.jazzy.overrideScope (rosFinal: rosPrev: {

      foonathan-memory-vendor = rosPrev.foonathan-memory-vendor.overrideAttrs (old: {
        # 1. The Native Nix Sledgehammer:
        # Inject the flag directly into the Nix compiler wrapper so every single
        # C++ compilation step inherits it, regardless of CMake isolation.
        NIX_CFLAGS_COMPILE = toString (old.NIX_CFLAGS_COMPILE or "") + " -Wno-error=deprecated-literal-operator";

        # 2. The CMake Top-of-File Injection:
        # Use `sed -i '1i ...'` to physically insert the warning suppression at
        # Line 1 of the file, guaranteeing it executes before ExternalProject_Add.
        postPatch = (old.postPatch or "") + ''
          sed -i '1i set(CMAKE_CXX_FLAGS "''${CMAKE_CXX_FLAGS} -Wno-error=deprecated-literal-operator")' CMakeLists.txt
        '';
      });

      libmavconn = rosPrev.libmavconn.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          # 7. Clean up Clang literal operator warnings
          find . -type f -name "*.hpp" -exec sed -i 's/operator"" _KiB/operator""_KiB/g' {} +

          echo "Injecting macOS endianness polyfill..."
          cat << 'EOF' > mac_endian.h
          #ifdef __APPLE__
          #include <libkern/OSByteOrder.h>
          #ifndef htole16
          #define htole16(x) OSSwapHostToLittleInt16(x)
          #define le16toh(x) OSSwapLittleToHostInt16(x)
          #define htole32(x) OSSwapHostToLittleInt32(x)
          #define le32toh(x) OSSwapLittleToHostInt32(x)
          #define htole64(x) OSSwapHostToLittleInt64(x)
          #define le64toh(x) OSSwapLittleToHostInt64(x)
          #endif
          #endif
          EOF

          # Inject the polyfill directly into CMakeLists.txt after the project() declaration
          sed -i '/project(/a add_compile_options("-include" "''${CMAKE_CURRENT_SOURCE_DIR}/mac_endian.h")' CMakeLists.txt
        '';
      });

      mavros = rosPrev.mavros.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          echo "Injecting macOS endianness polyfill for mavros..."
          cat << 'EOF' > mac_endian.h
          #ifdef __APPLE__
          #include <libkern/OSByteOrder.h>
          #ifndef htole16
          #define htole16(x) OSSwapHostToLittleInt16(x)
          #define le16toh(x) OSSwapLittleToHostInt16(x)
          #define htole32(x) OSSwapHostToLittleInt32(x)
          #define le32toh(x) OSSwapLittleToHostInt32(x)
          #define htole64(x) OSSwapHostToLittleInt64(x)
          #define le64toh(x) OSSwapLittleToHostInt64(x)
          #endif
          #endif
          EOF

          # Inject the polyfill directly into CMakeLists.txt after the project() declaration
          sed -i '/project(/a add_compile_options("-include" "''${CMAKE_CURRENT_SOURCE_DIR}/mac_endian.h")' CMakeLists.txt
        '';
      });

      mavros-extras = rosPrev.mavros-extras.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          echo "Injecting macOS endianness polyfill for mavros..."
          cat << 'EOF' > mac_endian.h
          #ifdef __APPLE__
          #include <libkern/OSByteOrder.h>
          #ifndef htole16
          #define htole16(x) OSSwapHostToLittleInt16(x)
          #define le16toh(x) OSSwapLittleToHostInt16(x)
          #define htole32(x) OSSwapHostToLittleInt32(x)
          #define le32toh(x) OSSwapLittleToHostInt32(x)
          #define htole64(x) OSSwapHostToLittleInt64(x)
          #define le64toh(x) OSSwapLittleToHostInt64(x)
          #endif
          #endif
          EOF

          echo "Injecting macOS dynamic lookup linker flag for mavros_extras_plugins..."

          # Append the Apple-specific linker flag to the end of CMakeLists.txt
          cat << 'EOF' >> CMakeLists.txt

          if(APPLE)
            set_target_properties(mavros_extras_plugins PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
          endif()
          EOF

          # Inject the polyfill directly into CMakeLists.txt after the project() declaration
          sed -i '/project(/a add_compile_options("-include" "''${CMAKE_CURRENT_SOURCE_DIR}/mac_endian.h")' CMakeLists.txt

          #### fixed in upstream already, should be part of the next release
          echo "Globally migrating tf2::fromMsg to tf2::transformToEigen across all plugins..."
          find src/plugins -type f -name "*.cpp" -exec sed -i -E 's/tf2::fromMsg\(([^,]*transform[^,]*),\s*([^)]+)\);/\2 = tf2::transformToEigen(\1);/gi' {} +
          
          echo "Reverting regex overshoot for quaternion and translation sub-fields..."
          # This undoes the damage if the regex accidentally caught .rotation or .translation fields
          find src/plugins -type f -name "*.cpp" -exec sed -i -E 's/([a-zA-Z0-9_]+)\s*=\s*tf2::transformToEigen\(([^)]*\.(rotation|translation))\);/tf2::fromMsg(\2, \1);/gi' {} +
          ####

          #### fixed in upstream (https://github.com/mavlink/mavros/pull/2221), will be part of the next release
          substituteInPlace src/plugins/hil.cpp \
            --replace-fail 'auto lin_vel = ftf::transform' 'Eigen::Vector3d lin_vel = ftf::transform' \
            --replace-fail 'auto ang_vel = ftf::transform' 'Eigen::Vector3d ang_vel = ftf::transform'

          substituteInPlace src/plugins/mount_control.cpp \
            --replace-fail 'auto vec = Eigen::Vector3d' 'Eigen::Vector3d vec = Eigen::Vector3d' 

          substituteInPlace src/plugins/landing_target.cpp \
            --replace-fail 'Eigen::Vector2f angle;' 'Eigen::Vector2f angle = Eigen::Vector2f::Zero();' 
          ####
        '';
      });
    });
  };
}
