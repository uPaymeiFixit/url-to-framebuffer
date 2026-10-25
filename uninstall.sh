#!/bin/sh
# Stop and remove the container. With --purge also remove the image and /opt/url-to-framebuffer
# (including .env and the default pages directory).
#   sudo ./uninstall.sh [--purge]
set -eu

DEST=/opt/url-to-framebuffer

die() { printf 'uninstall.sh: %s\n' "$*" >&2; exit 1; }

purge=0
case ${1:-} in
  '') ;;
  --purge) purge=1 ;;
  *) die "usage: $0 [--purge]" ;;
esac
[ "$(id -u)" -eq 0 ] || die "must run as root (try: sudo $0)"

if [ -f "$DEST/compose.yaml" ]; then
  (cd "$DEST" && docker compose down --remove-orphans)
else
  printf 'No installation at %s; nothing to stop.\n' "$DEST"
fi

if [ "$purge" -eq 1 ]; then
  docker image rm url-to-framebuffer:local 2>/dev/null || true
  rm -rf "$DEST"
  printf 'Removed %s and the image.\n' "$DEST"
fi
