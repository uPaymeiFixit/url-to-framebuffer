#!/bin/sh
# Static checks, run locally and in CI: shellcheck, hadolint, compose config, device guard.
set -eu
cd "$(dirname "$0")"

# Pinned container image, used when no hadolint binary is installed.
HADOLINT_IMAGE=hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d

command -v shellcheck >/dev/null 2>&1 || { echo "lint.sh: shellcheck not found" >&2; exit 1; }
find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} +
echo "shellcheck: ok"

if command -v hadolint >/dev/null 2>&1; then
  hadolint Dockerfile
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -i "$HADOLINT_IMAGE" < Dockerfile
else
  echo "lint.sh: hadolint and docker not found" >&2; exit 1
fi
echo "hadolint: ok"

# `docker compose config` only parses files and needs no running daemon.
if docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config --quiet
  echo "compose config: ok"
else
  echo "compose config: skipped (docker compose not available)"
fi

# Guard the hard requirement: no devices beyond the display card and VT nodes.
if grep -nE '^[[:space:]]*(privileged:|runtime:|gpus:)|-[[:space:]]*/dev(/dri)?:|seccomp[=:]unconfined' compose.yaml; then
  echo "lint.sh: compose.yaml exposes more than the display card and VT nodes" >&2
  exit 1
fi
echo "device guard: ok"
