{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.helium;

  # Fetch a Chromium extension by ID from the Chrome Web Store
  fetchExtension =
    { id, hash }:
    pkgs.fetchurl {
      name = "${id}.crx";
      url = "https://clients2.google.com/service/update2/crx?response=redirect&os=linux&arch=x64&os_arch=x86_64&nacl_arch=x86-64&prod=chromiumcrx&prodchannel=stable&prodversion=120.0.0.0&acceptformat=crx3&x=id%3D${id}%26installsource%3Dondemand%26uc";
      inherit hash;
    };

  # Unpack a .crx extension into a directory Chromium can load
  unpackExtension =
    { id, hash }:
    pkgs.runCommand "helium-ext-${id}"
      {
        nativeBuildInputs = [ pkgs.unzip ];
        src = fetchExtension { inherit id hash; };
      }
      ''
        mkdir -p $out
        unzip -q $src -d $out || true
        rm -rf $out/_metadata
      '';

  resolvedExtensions = map (spec: {
    inherit (spec) id;
    unpacked = unpackExtension { inherit (spec) id hash; };
  }) cfg.extensions;

  # Extensions need to be allowlisted so Chromium doesn't disable them
  policyAttrs = {
    ExtensionInstallAllowlist = map (ext: ext.id) cfg.extensions;
  } // cfg.extraPolicies;

  loadExtensionFlag =
    if resolvedExtensions != [ ] then
      [ "--load-extension=${lib.concatStringsSep "," (map (ext: "${ext.unpacked}") resolvedExtensions)}" ]
    else
      [ ];

  # Wrap helium with user-specified flags + extensions
  # We re-wrap because the base package already has a wrapper from default.nix
  heliumConfigured = pkgs.symlinkJoin {
    name = "helium-configured";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/helium \
        ${lib.concatMapStringsSep " \\\n        " (f: "--add-flags ${lib.escapeShellArg f}") (
          loadExtensionFlag
          ++ cfg.extraFlags
        )}
    '';
  };

  configDir = "${config.xdg.configHome}/net.imput.helium";

in
{
  options.programs.helium = {
    enable = lib.mkEnableOption "Helium browser";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.helium;
      description = "The Helium browser package to use.";
    };

    extensions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.str;
              description = "Extension ID from the Chrome Web Store URL.";
            };
            hash = lib.mkOption {
              type = lib.types.str;
              description = "Nix hash of the extension .crx file (use nix-prefetch-url).";
            };
          };
        }
      );
      default = [ ];
      description = "Chromium extensions to install declaratively.";
      example = lib.literalExpression ''
        [
          { id = "nngceckbapebfimnlniiiahkandclblb"; hash = "sha256-..."; }  # Bitwarden
        ]
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional command-line flags passed to the Helium wrapper.";
      example = [ "--force-dark-mode" "--incognito" ];
    };

    extraPolicies = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Chromium enterprise policies to apply.
        See https://chromeenterprise.google/policies/ for available options.
      '';
      example = lib.literalExpression ''
        {
          PasswordManagerEnabled = false;
          BrowserSignin = 0;
        }
      '';
    };

    preferences = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Chromium preferences to merge into the Default profile.
        Visit helium://prefs-internals/ in the browser to find available keys and values.
      '';
      example = lib.literalExpression ''
        {
          browser.show_home_button = true;
          bookmark_bar.show_on_all_tabs = true;
        }
      '';
    };

    defaultBrowser = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Helium as the default web browser via XDG mimeapps.";
    };

    finalPolicyJson = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = builtins.toJSON policyAttrs;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ heliumConfigured ];

    # Write policies to the user config dir so Chromium picks them up
    xdg.configFile."net.imput.helium/policies/managed/helium-nix.json".text = cfg.finalPolicyJson;

    # Merge preferences into the Helium profile on activation
    home.activation.heliumPreferences = lib.mkIf (cfg.preferences != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        prefs_dir="${configDir}/Default"
        prefs_file="$prefs_dir/Preferences"
        nix_prefs='${builtins.toJSON cfg.preferences}'

        run mkdir -p "$prefs_dir"

        if [ -f "$prefs_file" ]; then
          merged=$(${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$prefs_file" - <<< "$nix_prefs")
          if [ -n "$merged" ]; then
            printf '%s\n' "$merged" > "$prefs_file"
          fi
        else
          printf '%s\n' "$nix_prefs" > "$prefs_file"
        fi
      ''
    );

    # Set Helium as the default browser
    xdg.mimeApps = lib.mkIf cfg.defaultBrowser {
      enable = true;
      defaultApplications = {
        "text/html" = "helium.desktop";
        "text/xml" = "helium.desktop";
        "x-scheme-handler/http" = "helium.desktop";
        "x-scheme-handler/https" = "helium.desktop";
      };
    };
  };
}
