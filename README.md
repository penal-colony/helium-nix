# helium-nix

Helium browser, packaged from source for Nix/NixOS.

Built on nixpkgs' Chromium infrastructure. Helium replaces the ungoogled patch layer with its own patch stack (ungoogled + Brave, Cromite, Inox, Iridium, Bromite, Debian patches + Manifest V2 support).

**Helium 0.12.1 / Chromium 148.0.7778.96**

## Install

### Try it

```bash
nix run github:penal-colony/helium-nix
```

### NixOS

Add the flake input:

```nix
inputs.helium-nix.url = "github:penal-colony/helium-nix";
```

Then add the package:

```nix
environment.systemPackages = [
  inputs.helium-nix.packages.${system}.helium
];
```

### Home Manager (package only)

Add the flake input:

```nix
inputs.helium-nix.url = "github:penal-colony/helium-nix";
```

Then add the package directly:

```nix
home.packages = [
  inputs.helium-nix.packages.${system}.helium
];
```

Or use the overlay:

```nix
nixpkgs.overlays = [ inputs.helium-nix.overlays.default ];
home.packages = [ pkgs.helium ];
```

### Home Manager (declarative config)

For extension management, policies, preferences, and default browser, use the home-manager module:

```nix
# flake.nix
inputs.helium-nix.url = "github:penal-colony/helium-nix";
```

Import the NixOS module (required for policies to work):

```nix
imports = [ inputs.helium-nix.nixosModules.helium ];
```

Then configure in your home-manager user config:

```nix
imports = [ inputs.helium-nix.homeManagerModules.helium ];

programs.helium = {
  enable = true;
  defaultBrowser = true;

  extensions = [
    { id = "nngceckbapebfimnlniiiahkandclblb"; hash = "sha256-..."; }  # Bitwarden
  ];

  extraFlags = [ "--force-dark-mode" ];

  extraPolicies = {
    PasswordManagerEnabled = false;
    BrowserSignin = 0;
  };

  preferences = {
    browser.show_home_button = true;
    bookmark_bar.show_on_all_tabs = true;
  };
};
```

> **Note:** Both the NixOS module and the home-manager module are needed for policies to work correctly. The NixOS module writes policy files to `/etc/chromium/policies/managed/` based on your home-manager config.

#### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the Helium module |
| `package` | package | flake package | Helium package to use |
| `extensions` | list of `{ id, hash }` | `[]` | Extensions from Chrome Web Store |
| `extraFlags` | list of str | `[]` | CLI flags added to the wrapper |
| `extraPolicies` | attrs | `{}` | Chromium enterprise policies |
| `preferences` | attrs | `{}` | Preferences merged into profile (see `helium://prefs-internals/`) |
| `defaultBrowser` | bool | `false` | Set as default browser via XDG |

Policy reference: https://chromeenterprise.google/policies/

#### Package overrides

The Helium package accepts override arguments:

```nix
programs.helium = {
  enable = true;
  package = pkgs.helium.override {
    enableWideVine = true;
    commandLineArgs = "--force-dark-mode";
  };
};
```

| Override | Type | Default | Description |
|---|---|---|---|
| `enableWideVine` | bool | `false` | Bundle Widevine CDM for DRM content |
| `commandLineArgs` | str | `""` | CLI args baked into the package |
| `proprietaryCodecs` | bool | `true` | Build with proprietary codec support |
| `cupsSupport` | bool | `true` | Build with CUPS printing support |
| `pulseSupport` | bool | auto | Build with PulseAudio audio support |

## Binary cache

Pre-built binaries available via Cachix:

```nix
nix.settings = {
  substituters = [ "https://helium-nix.cachix.org" ];
  trusted-public-keys = [ "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw=" ];
};
```

## Building from source

```bash
nix build
```

### Requirements

- 16+ GB RAM (32 GB recommended)
- 100+ GB disk space
- Several hours (first build, varies by hardware)

### Ccache (faster rebuilds)

Ccache is built into the default build. If `CCACHE_DIR` exists, it's used automatically.

Set up the cache directory:

```bash
sudo mkdir -p /var/cache/ccache
sudo chown root:nixbld /var/cache/ccache
sudo chmod 770 /var/cache/ccache
```

Allow it in the Nix sandbox:

```nix
nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];
```

Then build as normal:

```bash
nix build
```

## Updating

```bash
node update.mjs              # latest release
node update.mjs 0.13.0       # specific version
```

Updates `default.nix` with new version, hashes, and deps. If the Chromium base version changed, it'll tell you to also update `info.json` using the chromium update script.

## Repository structure

```
default.nix          — Entry point: version, source, deps, wrapper
info.json            — Pinned Chromium dependencies (from nixpkgs)
helium-flags.toml    — GN build flags
update.mjs           — Automatic version update script
maintainers.nix      — Maintainer metadata (for nixpkgs submission)
modules/
  home-manager.nix   — Home-manager module (extensions, policies, prefs)
  nixos.nix          — NixOS module (writes policies to /etc)
chromium/
  common.nix         — Build logic (modified from nixpkgs)
  browser.nix        — Browser derivation + Helium branding
  patches/           — Nixpkgs chromium patches
  files/             — Nixpkgs chromium files
  update.mjs         — Chromium DEPS updater (from nixpkgs)
  depot_tools.py     — DEPS resolver (from nixpkgs)
```

## License

MIT. See [LICENSE](LICENSE).
