{
  fetchFromGitHub,
  gperf,
  openssl,
  readline,
  zlib,
  cmake,
  lib,
  stdenv,
  writeShellApplication,
  common-updater-scripts,
  jq,
  buildPackages,

  tde2eOnly ? false,
}:

let
  updateScript = writeShellApplication {
    name = "update-tdlib";

    runtimeInputs = [
      jq
      common-updater-scripts
    ];

    text = ''
      commit_msg="^Update version to (?<v>\\\\d+.\\\\d+.\\\\d+)\\\\.$"
      commit=$(curl -s "https://api.github.com/repos/tdlib/td/commits?path=CMakeLists.txt" | jq -c "map(select(.commit.message | test(\"''${commit_msg}\"))) | first")

      rev=$(echo "$commit" | jq -r ".sha")
      version=$(echo "$commit" | jq -r ".commit.message | capture(\"''${commit_msg}\") | .v")

      update-source-version tdlib "$version" --rev="$rev"
    '';
  };
in

stdenv.mkDerivation {
  pname = if tde2eOnly then "tde2e" else "tdlib";
  version = "1.8.51";

  src = fetchFromGitHub {
    owner = "tdlib";
    repo = "td";

    # The tdlib authors do not set tags for minor versions, but
    # external programs depending on tdlib constrain the minor
    # version, hence we set a specific commit with a known version.
    rev = "bb474a201baa798784d696d2d9d762a9d2807f96";
    hash = "sha256-Jd2ojDDwO/7W54QjnKLlc1ecqTfJEFPRtT50rNlukKA=";
  };

  buildInputs = [
    openssl
    readline
    zlib
  ];

  nativeBuildInputs = [
    cmake
    gperf
  ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  preConfigure = lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
    cmake -B native-build \
      -DCMAKE_C_COMPILER=$CC_FOR_BUILD \
      -DCMAKE_CXX_COMPILER=$CXX_FOR_BUILD \
      -DCMAKE_AR=$(command -v $AR_FOR_BUILD) \
      -DCMAKE_RANLIB=$(command -v $RANLIB_FOR_BUILD) \
      -DCMAKE_STRIP=$(command -v $STRIP_FOR_BUILD) \
      -DTD_GENERATE_SOURCE_FILES=ON .
    cmake --build native-build -j $NIX_BUILD_CORES
  '';

  cmakeFlags = [
    (lib.cmakeBool "TD_E2E_ONLY" tde2eOnly)
  ];

  # https://github.com/tdlib/td/issues/1974
  postPatch = ''
    substituteInPlace CMake/GeneratePkgConfig.cmake \
      --replace 'function(generate_pkgconfig' \
                'include(GNUInstallDirs)
                 function(generate_pkgconfig' \
      --replace '\$'{prefix}/'$'{CMAKE_INSTALL_LIBDIR} '$'{CMAKE_INSTALL_FULL_LIBDIR} \
      --replace '\$'{prefix}/'$'{CMAKE_INSTALL_INCLUDEDIR} '$'{CMAKE_INSTALL_FULL_INCLUDEDIR}
  ''
  + lib.optionalString (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) ''
    sed -i "/vptr/d" test/CMakeLists.txt
  '';

  passthru.updateScript = lib.getExe updateScript;

  meta = with lib; {
    description = "Cross-platform library for building Telegram clients";
    homepage = "https://core.telegram.org/tdlib/";
    license = [ licenses.boost ];
    platforms = platforms.unix;
    maintainers = [
      maintainers.vyorkin
      maintainers.vonfry
    ];
  };
}
