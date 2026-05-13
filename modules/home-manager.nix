{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.helium;

  archInfo =
    let
      platform = pkgs.stdenv.hostPlatform;
    in
    if platform.isAarch64 then {
      arch = "arm64";
      osArch = "aarch64";
      naclArch = "aarch64";
    } else {
      arch = "x64";
      osArch = "x86_64";
      naclArch = "x86-64";
    };

  fetchExtension =
    { id, hash }:
    pkgs.fetchurl {
      name = "${id}.crx";
      url = "https://clients2.google.com/service/update2/crx?response=redirect&os=linux&arch=${archInfo.arch}&os_arch=${archInfo.osArch}&nacl_arch=${archInfo.naclArch}&prod=chromiumcrx&prodchannel=stable&prodversion=${cfg.package.version or "130.0.0.0"}&acceptformat=crx3&x=id%3D${id}%26installsource%3Dondemand%26uc";
      inherit hash;
    };

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
        [ -n "$(ls -A $out 2>/dev/null)" ] || { echo "ERROR: unpacking $src produced no files" >&2; exit 1; }
        rm -rf $out/_metadata
      '';

  resolvedExtensions = map (spec: {
    inherit (spec) id;
    unpacked = unpackExtension { inherit (spec) id hash; };
  }) cfg.extensions;

  policyAttrs = {
    ExtensionInstallAllowlist = map (ext: ext.id) cfg.extensions;
  } // cfg.extraPolicies;

  loadExtensionFlags =
    if resolvedExtensions != [ ] then
      [ "--load-extension=${lib.concatStringsSep "," (map (ext: "${ext.unpacked}") resolvedExtensions)}" ]
    else
      [ ];

  configDir = "${config.xdg.configHome}/net.imput.helium";

  preferencesJson = pkgs.writeText "helium-preferences.json" (builtins.toJSON cfg.preferences);

  mergePrefsScript =
    if cfg.preferences != { } then
      pkgs.writeShellScript "merge-helium-prefs" ''
        prefs_dir="${configDir}/Default"
        prefs_file="$prefs_dir/Preferences"
        ${pkgs.coreutils}/bin/mkdir -p "$prefs_dir"
        if [ -f "$prefs_file" ]; then
          merged=$(${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$prefs_file" "${preferencesJson}" 2>/dev/null)
          if [ -n "$merged" ]; then
            printf '%s\n' "$merged" > "$prefs_file.tmp" && ${pkgs.coreutils}/bin/mv "$prefs_file.tmp" "$prefs_file"
          fi
        else
          ${pkgs.coreutils}/bin/cp "${preferencesJson}" "$prefs_file"
        fi
      ''
    else
      null;

  heliumConfigured = pkgs.symlinkJoin {
    name = "helium-configured";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/helium \
        ${lib.concatMapStringsSep " \\\n        " (f: "--add-flags ${lib.escapeShellArg f}") (
          loadExtensionFlags
          ++ cfg.extraFlags
        )}${lib.optionalString (cfg.preferences != { }) \
          " --run ${lib.escapeShellArg (lib.getExe mergePrefsScript)}"}
    '';
  };

  jsonValue = lib.types.mkOptionType {
    name = "jsonValue";
    description = "JSON-compatible value (bool, int, float, str, list, attrset, or null)";
    check = v:
      v == null
      || builtins.isBool v
      || builtins.isInt v
      || builtins.isFloat v
      || builtins.isString v
      || (builtins.isList v && builtins.all jsonValue.check v)
      || (builtins.isAttrs v && builtins.all jsonValue.check (builtins.attrValues v));
  };

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
      type = lib.types.attrsOf jsonValue;
      default = { };
      description = ''
        Chromium enterprise policies to apply.
        Requires the NixOS module (nixosModules.helium) to be imported, since
        Chromium only reads policies from /etc/chromium/policies/managed/.
        Key names are not validated; see https://chromeenterprise.google/policies/
        for available options.
      '';
      example = lib.literalExpression ''
        {
          PasswordManagerEnabled = false;
          BrowserSignin = 0;
        }
      '';
    };

    preferences = lib.mkOption {
      type = lib.types.attrsOf jsonValue;
      default = { };
      description = ''
        Chromium preferences to merge into the Default profile.
        Key names are not validated; visit helium://prefs-internals/ in the browser
        to find available keys and values.
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
