{ self, pkgs, lib, system }:

let
  heliumPkg = self.packages.${system}.helium;

  # Import info.json for consistency checks
  infoJson = lib.importJSON ../info.json;

  # ── NixOS module evaluation ──
  # We evaluate the NixOS module with mock home-manager users to verify
  # that policy files get generated correctly for each user.

  nixosConfig = lib.nixosSystem {
    inherit system;
    modules = [
      # Minimal boot stub so NixOS eval doesn't complain
      { boot.loader.grub.enable = false;
        fileSystems."/".device = "nodev";
        fileSystems."/".fsType = "ext4";
        system.stateVersion = "25.05";
      }
      # Mock home-manager.options so the NixOS module can read home-manager.users
      {
        options.home-manager = lib.mkOption {
          type = lib.types.submodule {
            options.users = lib.mkOption {
              type = lib.types.lazyAttrsOf lib.types.unspecified;
              default = {};
            };
          };
          default = {};
        };
      }
      self.nixosModules.helium
      # Mock home-manager.users with different helium configs per user
      {
        home-manager.users = {
          alice = {
            programs.helium = {
              enable = true;
              finalPolicyJson = builtins.toJSON {
                ExtensionInstallAllowlist = [];
                PasswordManagerEnabled = false;
                BrowserSignin = 0;
              };
            };
          };
          bob = {
            programs.helium = {
              enable = true;
              finalPolicyJson = builtins.toJSON {
                ExtensionInstallAllowlist = [ "nngceckbapebfimnlniiiahkandclblb" ];
                IncognitoModeAvailability = 1;
              };
            };
          };
          charlie = {
            # helium not enabled — should be filtered out by the NixOS module
          };
          dave = {
            programs.helium = {
              enable = true;
              extensions = [
                { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; }
              ];
              finalPolicyJson = builtins.toJSON {
                ExtensionInstallAllowlist = [ "cjpalhdlnbpafiamejdnhcphjbkeiagm" ];
                PasswordManagerEnabled = false;
                BlockThirdPartyCookies = true;
              };
            };
          };
        };
      }
    ];
  };

  # ── Home-manager module option evaluation ──
  # We can't use lib.homeManagerConfiguration without HM as a flake input,
  # but we can use lib.evalModules to test the module's option definitions
  # and config logic directly.

  hmModule = import ../modules/home-manager.nix { inherit self; };

  evalHMModule = heliumConfig:
    lib.evalModules {
      modules = [
        # Stub out everything the HM module reads from the HM module system
        {
          options.home = lib.mkOption {
            type = lib.types.submodule {
              options.packages = lib.mkOption {
                type = lib.types.listOf lib.types.unspecified;
                default = [];
              };
            };
            default = {};
          };
          options.xdg = lib.mkOption {
            type = lib.types.submodule {
              options = {
                configHome = lib.mkOption {
                  type = lib.types.str;
                  default = "/home/test/.config";
                };
                mimeApps = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      enable = lib.mkOption { type = lib.types.bool; default = false; };
                      defaultApplications = lib.mkOption { type = lib.types.attrsOf lib.types.unspecified; default = {}; };
                    };
                  };
                  default = {};
                };
              };
            };
            default = {};
          };
          config = {
            home.packages = [];
            xdg.configHome = "/home/test/.config";
            xdg.mimeApps.enable = false;
            xdg.mimeApps.defaultApplications = {};
          };
        }
        hmModule
        { programs.helium = heliumConfig; }
      ];
      specialArgs = { inherit lib pkgs; };
    };

in
{
  # ──────────────────────────────────────
  #  Pure-eval checks (no build needed)
  # ──────────────────────────────────────
  checks = {
    # ── Package structure (string attrs only) ──

    package-evaluates = pkgs.runCommand "test-package-evaluates" { } ''
      echo "Checking helium package attributes..."
      [[ "${heliumPkg.name}" == helium* ]] \
        || { echo "FAIL: name is '${heliumPkg.name}', expected to start with 'helium'"; exit 1; }
      [[ "${heliumPkg.meta.mainProgram}" == "helium" ]] \
        || { echo "FAIL: mainProgram is '${heliumPkg.meta.mainProgram}'"; exit 1; }
      [[ -n "${heliumPkg.version}" ]] \
        || { echo "FAIL: version is empty"; exit 1; }
      [[ "${lib.concatStringsSep "," heliumPkg.meta.platforms}" == *"linux"* ]] \
        || { echo "FAIL: no linux in platforms"; exit 1; }
      [[ -n "${heliumPkg.meta.license.spdxId or "unknown"}" ]] \
        || { echo "FAIL: no license"; exit 1; }
      echo "OK"
      touch $out
    '';

    # ── Passthru (string attrs only, no file checks on paths) ──

    passthru-attributes = pkgs.runCommand "test-passthru-attributes" { } ''
      [ -n "${heliumPkg.passthru.updateScript}" ] \
        || { echo "FAIL: updateScript is empty"; exit 1; }
      [ -n "${heliumPkg.passthru.upstream-info.version}" ] \
        || { echo "FAIL: upstream-info.version empty"; exit 1; }
      [ "${heliumPkg.passthru.sandboxExecutableName}" = "__chromium-suid-sandbox" ] \
        || { echo "FAIL: sandboxExecutableName is '${heliumPkg.passthru.sandboxExecutableName}'"; exit 1; }
      echo "OK"
      touch $out
    '';

    # ── Overlay (string comparison, no build) ──

    overlay-matches-flake-package = pkgs.runCommand "test-overlay-matches-flake" { } ''
      OLY="${(self.overlays.default pkgs pkgs).helium}"
      FLAKE="${heliumPkg}"
      [ "$OLY" = "$FLAKE" ] \
        || { echo "FAIL: overlay ($OLY) differs from flake ($FLAKE)"; exit 1; }
      echo "OK"
      touch $out
    '';

    # ── NixOS module ──

    nixos-module-evaluates = pkgs.runCommand "test-nixos-module-evaluates" {
      # Force evaluation of environment.etc — if nixosConfig failed to evaluate,
      # this would error at import time
      _ = builtins.seq nixosConfig.config.environment.etc null;
    } ''
      echo "NixOS module evaluation succeeded"
      touch $out
    '';

    nixos-generates-policy-files = pkgs.runCommand "test-nixos-policy-files" {
      # Validate at Nix eval time using builtins — avoids interpolating JSON text into bash
      _ = builtins.seq (
        assert builtins.stringLength nixosConfig.config.environment.etc."chromium/policies/managed/helium-alice.json".text > 0;
        assert builtins.stringLength nixosConfig.config.environment.etc."chromium/policies/managed/helium-bob.json".text > 0;
        true
      ) null;
    } ''
      echo "OK"
      touch $out
    '';

    nixos-extensions-merge-policies = pkgs.runCommand "test-nixos-extensions-merge-policies" {
      policy = nixosConfig.config.environment.etc."chromium/policies/managed/helium-dave.json".text;
    } ''
      [ -n "$policy" ] || { echo "FAIL: no policy file generated for dave"; exit 1; }
      echo "$policy" | ${pkgs.jq}/bin/jq -e '.ExtensionInstallAllowlist | index("cjpalhdlnbpafiamejdnhcphjbkeiagm") != null' > /dev/null \
        || { echo "FAIL: extension ID not in dave's allowlist"; exit 1; }
      echo "$policy" | ${pkgs.jq}/bin/jq -e '.PasswordManagerEnabled == false' > /dev/null \
        || { echo "FAIL: PasswordManagerEnabled not false in dave's policy"; exit 1; }
      echo "$policy" | ${pkgs.jq}/bin/jq -e '.BlockThirdPartyCookies == true' > /dev/null \
        || { echo "FAIL: BlockThirdPartyCookies not true in dave's policy"; exit 1; }
      echo "OK"
      touch $out
    '';

    nixos-skips-disabled-users = pkgs.runCommand "test-nixos-skips-disabled" { } ''
      if echo "${lib.concatStringsSep " " (builtins.attrNames nixosConfig.config.environment.etc)}" | grep -q "helium-charlie"; then
        echo "FAIL: policy file generated for charlie (helium not enabled)"
        exit 1
      fi
      echo "OK"
      touch $out
    '';

    nixos-policy-content-alice = pkgs.runCommand "test-nixos-policy-alice" {
      policy = nixosConfig.config.environment.etc."chromium/policies/managed/helium-alice.json".text;
    } ''
      POLICY="$policy"
      echo "$POLICY" | ${pkgs.jq}/bin/jq -e '.PasswordManagerEnabled == false' > /dev/null \
        || { echo "FAIL: PasswordManagerEnabled not false"; exit 1; }
      echo "$POLICY" | ${pkgs.jq}/bin/jq -e '.BrowserSignin == 0' > /dev/null \
        || { echo "FAIL: BrowserSignin not 0"; exit 1; }
      echo "$POLICY" | ${pkgs.jq}/bin/jq -e '.ExtensionInstallAllowlist | length == 0' > /dev/null \
        || { echo "FAIL: alice should have empty ExtensionInstallAllowlist"; exit 1; }
      echo "OK"
      touch $out
    '';

    nixos-policy-content-bob = pkgs.runCommand "test-nixos-policy-bob" {
      policy = nixosConfig.config.environment.etc."chromium/policies/managed/helium-bob.json".text;
    } ''
      POLICY="$policy"
      echo "$POLICY" | ${pkgs.jq}/bin/jq -e '.IncognitoModeAvailability == 1' > /dev/null \
        || { echo "FAIL: IncognitoModeAvailability not 1"; exit 1; }
      echo "$POLICY" | ${pkgs.jq}/bin/jq -e '.ExtensionInstallAllowlist | index("nngceckbapebfimnlniiiahkandclblb") != null' > /dev/null \
        || { echo "FAIL: extension ID not in allowlist"; exit 1; }
      echo "OK"
      touch $out
    '';

    # ── Home-manager module (evalModules) ──

    hm-defaults-evaluate = pkgs.runCommand "test-hm-defaults" {
      _ = builtins.seq (evalHMModule { enable = true; }).config null;
    } ''
      echo "OK"
      touch $out
    '';

    hm-policy-json-content = pkgs.runCommand "test-hm-policy-json-content" {
      policyJson = (evalHMModule {
        enable = true;
        extraPolicies = {
          PasswordManagerEnabled = false;
          BrowserSignin = 0;
        };
      }).config.programs.helium.finalPolicyJson;
    } ''
      echo "$policyJson" | ${pkgs.jq}/bin/jq -e '.' > /dev/null \
        || { echo "FAIL: finalPolicyJson is not valid JSON"; exit 1; }
      echo "$policyJson" | ${pkgs.jq}/bin/jq -e '.PasswordManagerEnabled == false' > /dev/null \
        || { echo "FAIL: PasswordManagerEnabled not false"; exit 1; }
      echo "$policyJson" | ${pkgs.jq}/bin/jq -e '.BrowserSignin == 0' > /dev/null \
        || { echo "FAIL: BrowserSignin not 0"; exit 1; }
      echo "$policyJson" | ${pkgs.jq}/bin/jq -e '.ExtensionInstallAllowlist | length == 0' > /dev/null \
        || { echo "FAIL: ExtensionInstallAllowlist should be empty when no extensions configured"; exit 1; }
      echo "OK"
      touch $out
    '';

    hm-policies-evaluate = pkgs.runCommand "test-hm-policies" {
      _ = builtins.seq (evalHMModule {
        enable = true;
        extraPolicies = {
          PasswordManagerEnabled = false;
          BrowserSignin = 0;
          BlockThirdPartyCookies = true;
        };
      }).config null;
    } ''
      echo "OK"
      touch $out
    '';

    hm-preferences-evaluate = pkgs.runCommand "test-hm-preferences" {
      _ = builtins.seq (evalHMModule {
        enable = true;
        preferences = {
          "browser.show_home_button" = true;
          "bookmark_bar.show_on_all_tabs" = true;
          "some.number" = 42;
          "some.null" = null;
        };
      }).config null;
    } ''
      echo "OK"
      touch $out
    '';

    hm-flags-evaluate = pkgs.runCommand "test-hm-flags" {
      _ = builtins.seq (evalHMModule {
        enable = true;
        extraFlags = [ "--force-dark-mode" "--disable-features=SomeFeature" ];
      }).config null;
    } ''
      echo "OK"
      touch $out
    '';

    hm-default-browser-evaluate =
      let
        ev = (evalHMModule {
          enable = true;
          defaultBrowser = true;
        }).config;
        mimeKeys = builtins.attrNames ev.xdg.mimeApps.defaultApplications;
      in
      pkgs.runCommand "test-hm-default-browser" {
        # Force evaluation of the mime apps config
        _ = builtins.seq ev.xdg.mimeApps.defaultApplications null;
      } ''
        echo "${builtins.concatStringsSep " " mimeKeys}" | grep -q 'text/html' \
          || { echo "FAIL: missing text/html mime type"; exit 1; }
        echo "${builtins.concatStringsSep " " mimeKeys}" | grep -q 'text/xml' \
          || { echo "FAIL: missing text/xml mime type"; exit 1; }
        echo "${builtins.concatStringsSep " " mimeKeys}" | grep -q 'x-scheme-handler/http' \
          || { echo "FAIL: missing x-scheme-handler/http mime type"; exit 1; }
        echo "${builtins.concatStringsSep " " mimeKeys}" | grep -q 'x-scheme-handler/https' \
          || { echo "FAIL: missing x-scheme-handler/https mime type"; exit 1; }
        # Check that helium.desktop is set as the handler for key mime types
        [ "${ev.xdg.mimeApps.defaultApplications."text/html"}" = "helium.desktop" ] \
          || { echo "FAIL: text/html handler is not helium.desktop"; exit 1; }
        echo "OK"
        touch $out
      '';

    hm-disabled-is-noop =
      let
        pkgCount = builtins.length (evalHMModule { enable = false; }).config.home.packages;
      in
      pkgs.runCommand "test-hm-disabled-noop" { } ''
        [ "${toString pkgCount}" -eq 0 ] || { echo "FAIL: home.packages is not empty when disabled"; exit 1; }
        echo "OK"
        touch $out
      '';

    # ── Version consistency ──

    version-consistency = pkgs.runCommand "test-version-consistency" {
      readme = builtins.readFile "${self}/README.md";
      # Expected README format: "**Helium 0.12.3 / Chromium ..." or "**Helium v0.12.3 / Chromium ..."
      # The regex captures the version number after "Helium", with an optional leading "v".
    } ''
      README_VER=$(echo "$readme" | grep -oP 'Helium\s+v?\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      PKG_VER="${heliumPkg.version}"
      echo "README=$README_VER  PKG=$PKG_VER"
      [ "$README_VER" = "$PKG_VER" ] \
        || { echo "FAIL: README ($README_VER) != package ($PKG_VER)"; exit 1; }
      echo "OK"
      touch $out
    '';

    chromium-version-consistency = pkgs.runCommand "test-chromium-version" {
      infoVer = infoJson.chromium.version;
      pkgVer = heliumPkg.passthru.upstream-info.version;
    } ''
      echo "info.json=$infoVer  default.nix=$pkgVer"
      [ "$infoVer" = "$pkgVer" ] \
        || { echo "FAIL: info.json chromium ($infoVer) != default.nix ($pkgVer)"; exit 1; }
      echo "OK"
      touch $out
    '';
  };

  # ──────────────────────────────────────
  #  Integration checks (require build)
  # ──────────────────────────────────────
  integrationChecks = {
    wrapper-has-binary = pkgs.runCommand "test-wrapper-has-binary" { } ''
      BINARY="${heliumPkg}/bin/helium"
      [ -f "$BINARY" ] || { echo "FAIL: $BINARY does not exist"; exit 1; }
      [ -x "$BINARY" ] || { echo "FAIL: $BINARY is not executable"; exit 1; }
      grep -qE 'exec -a' "$BINARY" || { echo "FAIL: wrapper does not contain 'exec -a' invocation"; exit 1; }
      grep -q 'CHROME_DEVEL_SANDBOX' "$BINARY" || { echo "FAIL: wrapper missing CHROME_DEVEL_SANDBOX"; exit 1; }
      grep -q 'NIXOS_OZONE_WL' "$BINARY" || { echo "FAIL: wrapper missing NIXOS_OZONE_WL"; exit 1; }
      echo "OK"
      touch $out
    '';

    desktop-file-valid = pkgs.runCommand "test-desktop-file-valid" { } ''
      DESKTOP="${heliumPkg}/share/applications/helium.desktop"
      [ -f "$DESKTOP" ] || { echo "FAIL: $DESKTOP does not exist"; exit 1; }
      if grep -q '@@' "$DESKTOP"; then
        echo "FAIL: desktop file contains unsubstituted @@ placeholders"
        grep '@@' "$DESKTOP"
        exit 1
      fi
      grep -q 'Name=Helium' "$DESKTOP" || { echo "FAIL: missing Name=Helium"; exit 1; }
      grep -q 'Exec=helium' "$DESKTOP" || { echo "FAIL: missing Exec=helium"; exit 1; }
      grep -q 'StartupWMClass=helium-browser' "$DESKTOP" || { echo "FAIL: missing StartupWMClass"; exit 1; }
      echo "OK"
      touch $out
    '';

    sandbox-exists = pkgs.runCommand "test-sandbox-exists" { } ''
      SANDBOX="${heliumPkg.sandbox}"
      [ -n "$SANDBOX" ] || { echo "FAIL: sandbox output is empty"; exit 1; }
      SUID_BIN="$SANDBOX/bin/__chromium-suid-sandbox"
      [ -f "$SUID_BIN" ] || { echo "FAIL: $SUID_BIN does not exist"; exit 1; }
      [ -x "$SUID_BIN" ] || { echo "FAIL: $SUID_BIN is not executable"; exit 1; }
      echo "OK: $SUID_BIN"
      touch $out
    '';

    man-page-exists = pkgs.runCommand "test-man-page-exists" { } ''
      MAN="${heliumPkg}/share/man/man1/helium.1"
      [ -f "$MAN" ] || { echo "FAIL: $MAN does not exist"; exit 1; }
      echo "OK"
      touch $out
    '';

    icons-installed = pkgs.runCommand "test-icons-installed" { } ''
      ICON_DIR="${heliumPkg}/share/icons/hicolor"
      [ -d "$ICON_DIR" ] || { echo "FAIL: $ICON_DIR does not exist"; exit 1; }
      ICON_COUNT=$(find "$ICON_DIR" -name "helium.png" | wc -l)
      [ "$ICON_COUNT" -gt 0 ] || { echo "FAIL: no helium.png icons found"; exit 1; }
      echo "OK: $ICON_COUNT icons"
      touch $out
    '';

    widevine-override-evaluates =
      let
        pkgsAllowUnfree = import pkgs.path { inherit system; config = { allowUnfree = true; }; };
        wv = (pkgsAllowUnfree.callPackage ../default.nix { enableWideVine = true; });
      in
      pkgs.runCommand "test-widevine-override" { } ''
        # Force evaluation: reference the store path so the derivation can't be lazy-skipped
        [ -d "${wv}/bin" ] || { echo "FAIL: widevine override has no bin directory"; exit 1; }
        echo "OK"
        touch $out
      '';

    commandlineargs-override-evaluates =
      let
        customPkg = heliumPkg.override { commandLineArgs = "--force-dark-mode --incognito"; };
      in
      pkgs.runCommand "test-commandlineargs-override" {
        # Expose the wrapper path so we can grep the binary for actual flags
        wrapper = "${customPkg}/bin/helium";
      } ''
        grep -q 'force-dark-mode' "$wrapper" \
          || { echo "FAIL: --force-dark-mode not found in wrapper"; exit 1; }
        grep -q 'incognito' "$wrapper" \
          || { echo "FAIL: --incognito not found in wrapper"; exit 1; }
        echo "OK"
        touch $out
      '';

    overlay-resolves = pkgs.runCommand "test-overlay-resolves" { } ''
      OLY="${(self.overlays.default pkgs pkgs).helium}"
      [ -d "$OLY/bin" ] || { echo "FAIL: overlay result has no bin dir"; exit 1; }
      echo "OK"
      touch $out
    '';
  };
}
