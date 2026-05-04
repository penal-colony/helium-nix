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
nix build github:your-org/helium-nix

# Or clone and build locally
git clone https://git.ashisgreat.xyz/penal-colony/helium-nix
cd helium-nix
nix build

# Install on NixOS
nix profile install .
```

### Try without installing

```bash
nix run github:your-org/helium-nix
```

## Architecture

```
default.nix         — Top-level entry point, wraps the browser binary
helium-flags.toml   — Helium's GN build flags (converted from flags.gn)
info.json           — Pinned Chromium version info (copied from nixpkgs)
chromium/
  common.nix        — Modified nixpkgs chromium common.nix (Helium patch pipeline)
  browser.nix       — Modified browser.nix (helium branding)
  patches/          — Nixpkgs chromium patches (shared)
  files/            — Nixpkgs chromium files (shared)
  ungoogled.nix     — Unchanged (fallback, not used when helium-patches is set)
  ungoogled-flags.toml — Unchanged (fallback)
```

### How it works

1. Fetches Chromium source (same as nixpkgs chromium, v147.0.7727.137)
2. Fetches Helium's configuration repo (patches, domain lists, GN flags)
3. Applies Helium's domain substitution
4. Applies Helium's patch series (~300 patches, includes ungoogled + extras)
5. Prunes binaries per Helium's pruning list
6. Builds with ninja using Helium's GN flags
7. Packages with Helium branding

## Status

**Work in progress.** This has not been tested yet. The derivation structure is complete but needs:
- [ ] Fix hash verification (currently uses hex hash, may need nix base32)
- [ ] Test build on a machine with enough resources
- [ ] Verify patch application works correctly
- [ ] Add update script
- [ ] Submit to nixpkgs (eventually)

## License

GPL-3.0 (same as Helium)
