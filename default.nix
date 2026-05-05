# Helium browser — from-source build for Nix/NixOS
#
# Based on nixpkgs' chromium infrastructure.
# Helium is ungoogled-chromium + additional privacy patches from
# Brave, Cromite, Inox, Iridium, Bromite, Debian + Manifest V2 support.
#
# Helium 0.11.7 = Chromium 147.0.7727.137

{ newScope, lib, fetchFromGitHub, fetchurl, stdenv, buildPackages, pkgsBuildBuild
, config
, makeWrapper, ed, gnugrep, coreutils, xdg-utils
, glib, gtk3, gtk4, adwaita-icon-theme, gsettings-desktop-schemas
, gn, fetchgit, fetchFromGitiles, libva, pipewire, wayland
, runCommand, libkrb5, widevine-cdm, electron-source
, python3Packages, patch
, proprietaryCodecs ? true
, enableWideVine ? false
, cupsSupport ? true
, pulseSupport ? config.pulseaudio or stdenv.hostPlatform.isLinux
, commandLineArgs ? ""
, pkgs
}:

let
  heliumVersion = "0.11.7";
  chromiumVersion = "147.0.7727.137";

  # Chromium requires Clang/LLVM to build. Use the LLVM stdenv from rustc.
  stdenv = pkgs.rustc.llvmPackages.stdenv;

  # Import the nixpkgs chromium info for this version
  nixpkgsChromiumInfo = lib.importJSON ./info.json;

  # Helium's source: patches, GN flags, domain lists, pruning lists, utils
  heliumSrc = fetchFromGitHub {
    owner = "imputnet";
    repo = "helium";
    rev = heliumVersion;
    hash = "sha256-87sgs1iv30eD7vRfSV7iMUoz/yKU26Z/1gD27zSA+UU=";
  };

  # Helium patches derivation — prepares the Helium config for use
  # during the Chromium build. Mirrors the structure of nixpkgs' ungoogled.nix.
  helium-patches = stdenv.mkDerivation {
    pname = "helium-patches";
    version = heliumVersion;

    src = heliumSrc;

    dontBuild = true;

    buildInputs = [ python3Packages.python patch ];

    installPhase = ''
      mkdir $out
      cp -R * $out/
    '';
  };

  upstream-info = nixpkgsChromiumInfo.chromium // {
    version = chromiumVersion;
  };

  # Helium deps from deps.ini (external downloads not included in Chromium source)
  helium-onboarding = fetchurl {
    url = "https://github.com/imputnet/helium-onboarding/releases/download/202603080703/helium-onboarding-202603080703.tar.gz";
    hash = "sha256-aIPpDXvcpXKjf6WE28YFBNXyByo5na9YzcPRyXZOtQg=";
  };

  helium-ublock = fetchurl {
    url = "https://github.com/imputnet/uBlock/releases/download/1.70.0/uBlock0_1.70.0.chromium.zip";
    hash = "sha256-02rSUVyNrJB9F65W0BXJHJf+J5gPyh3HV10N/bpo4NQ=";
  };

  helium-search-engines-data = fetchurl {
    url = "https://gist.githubusercontent.com/wukko/2a591364dda346e10219e4adabd568b1/raw/e75ae3c4a1ce940ef7627916a48bc40882d24d40/nonfree-search-engines-data.tar.gz";
    hash = "sha256-AKhwUPo/lB0E1n+1djmR4LjqOZqItQWrDlbdJj8Ghkw=";
  };


  chromiumVersionAtLeast = min-version: lib.versionAtLeast upstream-info.version min-version;
  versionRange = min-version: upto-version:
    lib.versionAtLeast upstream-info.version min-version
    && lib.versionOlder upstream-info.version upto-version;

  callPackage = newScope chromium;

  # Helium-specific GN flags (from flags.gn + flags.linux.gn)
  heliumGnFlags = lib.importTOML ./helium-flags.toml;

  chromium = rec {
    inherit stdenv upstream-info;

    mkChromiumDerivation = callPackage ./chromium/common.nix {
      inherit chromiumVersionAtLeast versionRange;
      inherit proprietaryCodecs cupsSupport pulseSupport;
      ungoogled = true; # Helium IS ungoogled + more
      gnChromium = buildPackages.gn.override upstream-info.deps.gn;
      inherit helium-patches helium-onboarding helium-ublock helium-search-engines-data;
    };

    browser = callPackage ./chromium/browser.nix {
      inherit chromiumVersionAtLeast enableWideVine;
      ungoogled = true;
    };

    # We don't use the standard ungoogled-chromium derivation.
    # Instead, helium-patches provides all patches including ungoogled ones.
    ungoogled-chromium = pkgsBuildBuild.stdenv.mkDerivation {
      name = "helium-patches-wrapper-${heliumVersion}";
      dontUnpack = true;
      installPhase = ''
        mkdir $out
        cp -R ${helium-patches}/* $out/
      '';
    };
  };

  sandboxExecutableName = chromium.browser.passthru.sandboxExecutableName;

  chromiumWV =
    let browser = chromium.browser;
    in if enableWideVine then
      runCommand (browser.name + "-wv") { version = browser.version; } ''
        mkdir -p $out
        cp -a ${browser}/* $out/
        chmod u+w $out/libexec/chromium
        cp -a ${widevine-cdm}/share/google/chrome/WidevineCdm $out/libexec/chromium/
      ''
    else browser;

in
stdenv.mkDerivation {
  pname = "helium";
  inherit (chromium.browser) version;

  nativeBuildInputs = [ makeWrapper ed ];

  buildInputs = [
    gsettings-desktop-schemas glib gtk3 gtk4
    adwaita-icon-theme libkrb5
  ];

  outputs = [ "out" "sandbox" ];

  buildCommand =
    let
      browserBinary = "${chromiumWV}/libexec/chromium/chromium";
      libPath = lib.makeLibraryPath [ libva pipewire wayland gtk3 gtk4 libkrb5 ];
    in
    ''
      mkdir -p "$out/bin"

      makeWrapper "${browserBinary}" "$out/bin/helium" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
        --add-flags ${lib.escapeShellArg commandLineArgs}

      ed -v -s "$out/bin/helium" << EOF
      2i

      if [ -x "/run/wrappers/bin/${sandboxExecutableName}" ]
      then
        export CHROME_DEVEL_SANDBOX="/run/wrappers/bin/${sandboxExecutableName}"
      else
        export CHROME_DEVEL_SANDBOX="$sandbox/bin/${sandboxExecutableName}"
      fi

      export CHROME_WRAPPER='helium'

      ${lib.optionalString (libPath != "") ''
        export LD_LIBRARY_PATH="\$LD_LIBRARY_PATH\''${LD_LIBRARY_PATH:+:}${libPath}"
      ''}

      export LD_PRELOAD="\$(echo -n "\$LD_PRELOAD" | ${coreutils}/bin/tr ':' '\n' | ${gnugrep}/bin/grep -v /lib/libredirect\\\\.so$ | ${coreutils}/bin/tr '\n' ':')"

      export XDG_DATA_DIRS=$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH\''${XDG_DATA_DIRS:+:}\$XDG_DATA_DIRS

      ${lib.optionalString (!xdg-utils.meta.broken) ''
        export PATH="\$PATH\''${PATH:+:}${xdg-utils}/bin"
      ''}

      .
      w
      EOF

      ln -sv "${chromium.browser.sandbox}" "$sandbox"

      mkdir -p "$out/share"
      for f in '${chromium.browser}'/share/*; do
        ln -s -t "$out/share/" "$f"
      done
    '';

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    longDescription = ''
      Helium is a Chromium-based browser that combines privacy patches from
      ungoogled-chromium, Brave, Cromite, Inox, Iridium, Bromite, and Debian,
      with continued Manifest V2 extension support. It strips out Google
      dependencies, telemetry, and tracking while maintaining compatibility
      with the Chromium extension ecosystem.
    '';
    homepage = "https://github.com/imputnet/helium";
    license = if enableWideVine then lib.licenses.unfree else lib.licenses.gpl3;
    platforms = lib.platforms.linux;
    mainProgram = "helium";
    hydraPlatforms = [ "x86_64-linux" "aarch64-linux" ];
    timeout = 172800; # 48 hours
  };

  passthru = {
    inherit (chromium) upstream-info browser;
    mkDerivation = chromium.mkChromiumDerivation;
    inherit sandboxExecutableName;
  };
}
