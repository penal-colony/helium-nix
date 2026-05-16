#!/bin/bash
set -euo pipefail

. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
export NIX_CONFIG="experimental-features = nix-command flakes"
cd /tmp/helium-build

for check in wrapper-has-binary desktop-file-valid sandbox-exists widevine-override-evaluates commandlineargs-override-evaluates overlay-resolves; do
  echo "  -> $check"
  nix build ".#integrationChecks.x86_64-linux.$check" --accept-flake-config
done

echo "All integration checks passed!"