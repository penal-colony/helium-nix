#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/bin:/nix/var/nix/profiles/default/bin"

REPO_REF="${1:-main}"
REPO_URL="https://git.ashisgreat.xyz/penal-colony/helium-nix.git"
BUILD_DIR="/tmp/helium-build"
SUCCESS_MARKER="/tmp/build-success"
FAILURE_MARKER="/tmp/build-failure"
BUILD_LOG="/tmp/build.log"

log() { echo "[$(date -Iseconds)] $*"; }

cleanup() {
  local exit_code=$?
  log "Build finished with exit code $exit_code"
  log "PATH was: $PATH"
  log "git location: $(which git 2>&1 || echo 'NOT FOUND')"
  log "git in /usr/bin: $(ls -la /usr/bin/git 2>&1 || echo 'NOT FOUND')"
  if [ $exit_code -ne 0 ]; then
    log "Build failed with exit code $exit_code"
    echo "$exit_code" > "$FAILURE_MARKER"
    tail -200 "$BUILD_LOG" > "${FAILURE_MARKER}.log" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log "Starting helium-nix build for ref: $REPO_REF"

# Inject cachix token from mounted secret
if [ -f /tmp/cachix.token ]; then
  export CACHIX_AUTH_TOKEN=$(cat /tmp/cachix.token)
fi

git clone --depth 1 "$REPO_URL" "$BUILD_DIR"
cd "$BUILD_DIR"
git fetch origin "$REPO_REF"
git checkout FETCH_HEAD

log "Building .#helium with cachix watch-exec"
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
export NIX_CONFIG="experimental-features = nix-command flakes"
nix run nixpkgs#cachix -- watch-exec helium-nix -- \
  nix build .#helium --cores 16 --accept-flake-config --no-link --print-out-paths \
  2>&1 | tee "$BUILD_LOG"

OUT_PATH=$(tail -1 "$BUILD_LOG")

if [ -n "$OUT_PATH" ] && nix path-info "$OUT_PATH" &>/dev/null; then
  log "Build succeeded: $OUT_PATH"
  echo "$OUT_PATH" > "$SUCCESS_MARKER"
else
  log "ERROR: Could not verify output path: $OUT_PATH"
  exit 1
fi