# helium-nix

Helium browser, packaged from source for Nix/NixOS.

Built on nixpkgs' Chromium infrastructure. Helium replaces the ungoogled patch layer with its own patch stack (ungoogled + Brave, Cromite, Inox, Iridium, Bromite, Debian patches + Manifest V2 support).

**Helium 0.12.1 / Chromium 148.0.7778.96**

## Build

```bash
nix build
```

### Requirements

- 16+ GB RAM (32 GB recommended)
- 100+ GB disk space
- Several hours (first build)

### Ccache (faster rebuilds)

```bash
sudo mkdir -p /var/cache/ccache
sudo chown root:nixbld /var/cache/ccache
sudo chmod 770 /var/cache/ccache
```

Add to your NixOS config:

```nix
nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];
```

Then build with ccache:

```bash
nix build .#helium-ccache
```


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

### Home Manager

Add the flake input and use the overlay:

```nix
inputs.helium-nix.url = "github:penal-colony/helium-nix";
```

```nix
home.packages = [
  inputs.helium-nix.packages.${system}.helium
];
```

Or with the overlay:

```nix
nixpkgs.overlays = [ inputs.helium-nix.overlays.default ];
home.packages = [ pkgs.helium ];
```

## Binary cache

Pre-built binaries available via Cachix:

```nix
nix.settings = {
  substituters = [ "https://helium-nix.cachix.org" ];
  trusted-public-keys = [ "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw=" ];
};
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
