{ newScope, lib, fetchFromGitHub, fetchurl, stdenv, buildPackages, pkgsBuildBuild
, config
, bashInteractive, gnugrep, coreutils, xdg-utils
, glib, gtk3, gtk4, adwaita-icon-theme, gsettings-desktop-schemas
, gn, fetchFromGitiles, libva, pipewire, wayland
, runCommand, libkrb5, widevine-cdm
, python3Packages, patch
, proprietaryCodecs ? true
, enableWideVine ? false
, cupsSupport ? true
, pulseSupport ? config.pulseaudio or stdenv.hostPlatform.isLinux
, commandLineArgs ? ""
, pkgs
}:

let
  heliumVersion = "0.12.1";
  chromiumVersion = "148.0.7778.96";

  llvmStdenv = pkgs.rustc.llvmPackages.stdenv;

  nixpkgsChromiumInfo = lib.importJSON ./info.json;

  heliumSrc = fetchFromGitHub {
    owner = "imputnet";
    repo = "helium";
    rev = heliumVersion;
    hash = "sha256-KGBDlnSG26h/cl0y13zP+0d22JjFlHfqrJDxwrs7I04=";
  };

  helium-patches = llvmStdenv.mkDerivation {
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

  helium-linux-src = fetchFromGitHub {
    owner = "imputnet";
    repo = "helium-linux";
    rev = "9d60bc9ff85958cba093c267b741fa5f2f081b97"; # helium-linux 0.12.1.1 / 2026-05-05
    hash = "sha256-flPvX38r0QyGJ5vzsbq8cMq2pK0FuXFXMK2tUGrz+II=";
  };
  helium-linux-patches = "${helium-linux-src}/patches/helium/linux";

  upstream-info = nixpkgsChromiumInfo.chromium // {
    version = chromiumVersion;
  };

  helium-onboarding = fetchurl {
    url = "https://github.com/imputnet/helium-onboarding/releases/download/202605050730/helium-onboarding-202605050730.tar.gz";
    hash = "sha256-GLzslddT52txU23FqhxRdmPzjrF9W/bDs297dhZcQ84";
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

  chromium = rec {
    stdenv = llvmStdenv;
    inherit upstream-info;

    mkChromiumDerivation = callPackage ./chromium/common.nix {
      inherit chromiumVersionAtLeast versionRange;
      inherit proprietaryCodecs cupsSupport pulseSupport;
      ungoogled = true;
      gnChromium = buildPackages.gn.override upstream-info.deps.gn;
      inherit helium-patches helium-onboarding helium-ublock helium-search-engines-data;
      inherit helium-linux-patches;
    };

    browser = callPackage ./chromium/browser.nix {
      inherit chromiumVersionAtLeast enableWideVine;
      ungoogled = true;
    };

    ungoogled-chromium = { rev, hash }: helium-patches;
  };

  sandboxExecutableName = chromium.browser.passthru.sandboxExecutableName;

  chromiumWV =
    let browser = chromium.browser;
    in if enableWideVine then
      runCommand (browser.name + "-wv") { version = browser.version } ''
        mkdir -p $out
        cp -a ${browser}/* $out/
        chmod u+w $out/libexec/chromium
        cp -a ${widevine-cdm}/share/google/chrome/WidevineCdm $out/libexec/chromium/
      ''
    else browser;

in
llvmStdenv.mkDerivation {
  pname = "helium";
  inherit (chromium.browser) version;

  nativeBuildInputs = [ bashInteractive ];

  buildInputs = [
    gsettings-desktop-schemas glib gtk3 gtk4
    adwaita-icon-theme libkrb5
  ];

  outputs = [ "out" "sandbox" ];

  buildCommand =
    let
      browserBinary = "${chromiumWV}/libexec/helium/helium";
      libPath = lib.makeLibraryPath [ libva pipewire wayland gtk3 gtk4 libkrb5 ];
    in
    ''
      mkdir -p "$out/bin"

      cat > "$out/bin/helium" << WRAPPER
      #! ${bashInteractive}/bin/bash -e

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

      exec -a "\$0" "${browserBinary}" \
        \''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}} \
        ${lib.escapeShellArg commandLineArgs} \
        "\$@"
      WRAPPER
      chmod +x "$out/bin/helium"

      ln -sv "${chromium.browser.sandbox}" "$sandbox"

      mkdir -p "$out/share"
      for f in '${chromium.browser}'/share/*; do
        ln -s -t "$out/share/" "$f"
      done
    '';

  meta = chromium.browser.meta // {
    longDescription = ''
      Helium is a Chromium-based browser that combines privacy patches from
      ungoogled-chromium, Brave, Cromite, Inox, Iridium, Bromite, and Debian,
      with continued Manifest V2 extension support. It strips out Google
      dependencies, telemetry, and tracking while maintaining compatibility
      with the Chromium extension ecosystem.
    '';
    maintainers = with lib.maintainers; [ ashisgreat ];
  };

  passthru = {
    inherit (chromium) upstream-info browser;
    mkDerivation = chromium.mkChromiumDerivation;
    inherit sandboxExecutableName;
    updateScript = ./update.mjs;
  };
}
