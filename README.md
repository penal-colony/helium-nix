# helium-nix

Helium browser, packaged from source for Nix/NixOS.

## What is Helium?

[Helium](https://github.com/imputnet/helium) is a Chromium-based browser that combines privacy patches from ungoogled-chromium, Brave, Cromite, Inox, Iridium, Bromite, and Debian, with continued Manifest V2 extension support.

## Building from source

This is a **from-source** build, not a binary wrapper. It reuses nixpkgs' Chromium build infrastructure but replaces the ungoogled patch layer with Helium's full patch stack.

### Prerequisites

- A machine with **at least 16 GB RAM** (32 GB recommended)
- **100+ GB disk space** for the build
- Several hours of build time (depends on your hardware)

### Quick start

```bash
# Build with flake
nix build

# Or clone and build locally
git clone https://git.ashisgreat.xyz/penal-colony/helium-nix
cd helium-nix
nix build

# Install on NixOS
nix profile install .
```

### Try without installing

```bash
nix run
```

### With ccache (speed up rebuilds)

```bash
nix build --arg enableCcache true
# Make sure /cache/ccache exists and is writable by the build user
```

## Architecture

```
default.nix         — Top-level entry point: Helium version, source, deps, wrapper
helium-flags.toml   — Helium's GN build flags (converted from flags.gn + flags.linux.gn)
info.json           — Pinned Chromium version + dependency info (from nixpkgs)
chromium/
  common.nix        — Modified nixpkgs chromium common.nix (Helium patch pipeline)
  browser.nix       — Modified browser.nix (Helium branding)
  patches/          — Nixpkgs chromium patches (shared)
  files/            — Nixpkgs chromium files (shared)
  ungoogled.nix     — Unchanged (fallback for non-Helium builds)
  ungoogled-flags.toml — Unchanged (fallback)
```

### How it works

1. Fetches Chromium source (same as nixpkgs chromium, v148.0.7778.96)
2. Fetches Helium's configuration repo (patches, domain lists, GN flags)
3. Fetches Helium extras (onboarding, uBlock, search engine data)
4. Applies Helium's domain substitution
5. Applies Helium's patch series (~300 patches, includes ungoogled + extras)
6. Prunes binaries per Helium's pruning list
7. Applies name substitution and i18n
8. Builds with ninja using Helium's GN flags
9. Packages with Helium branding

## Status

**Work in progress.** The derivation structure is complete but needs:
- [ ] Test build on a machine with enough resources
- [ ] Verify patch application works correctly
- [ ] Submit to nixpkgs (eventually)

## License

GPL-3.0 (same as Helium)
