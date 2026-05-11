# helium-nix

Helium browser, packaged from source for Nix/NixOS.

Built on nixpkgs' Chromium infrastructure. Helium replaces the ungoogled patch layer with its own patch stack (ungoogled + Brave, Cromite, Inox, Iridium, Bromite, Debian patches + Manifest V2 support).

**Helium 0.12.1 / Chromium 148.0.7778.96**

## Build

```bash
# Standard build
nix build

# With ccache (faster rebuilds)
nix build .#helium-ccache

# Run without installing
nix run
```

### Requirements

- 16+ GB RAM (32 GB recommended)
- 100+ GB disk space
- Several hours

### Ccache setup

```bash
# Create the cache directory
sudo mkdir -p /var/cache/ccache
sudo chown $(whoami) /var/cache/ccache

# Add to your NixOS config
nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];
```

Then build with `nix build .#helium-ccache`.

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

GPL-3.0 (same as Helium)
