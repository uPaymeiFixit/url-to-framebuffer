#!/bin/sh
# Install or update url-to-framebuffer under /opt/url-to-framebuffer and (re)start it.
# Run as root from a checkout. Safe to re-run; existing .env values are kept unless a flag overrides them.
#   sudo ./install.sh [--url URL] [--drm-device /dev/dri/cardN] [--vt N]
set -eu

DEST=/opt/url-to-framebuffer
umask 077

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

url_flag='' drm_flag='' vt_flag=''
while [ $# -gt 0 ]; do
  case $1 in
    --url) [ $# -ge 2 ] || usage 1; url_flag=$2; shift 2 ;;
    --drm-device) [ $# -ge 2 ] || usage 1; drm_flag=$2; shift 2 ;;
    --vt) [ $# -ge 2 ] || usage 1; vt_flag=$2; shift 2 ;;
    -h | --help) usage 0 ;;
    *) usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must run as root (try: sudo $0)"

# Docker 24+ with Compose v2.
command -v docker >/dev/null 2>&1 || die "docker not found"
docker_major=$(docker --version | sed -n 's/^Docker version \([0-9]*\)\..*/\1/p')
[ "${docker_major:-0}" -ge 24 ] || die "Docker 24 or newer is required"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin not found (docker compose version failed)"

# Copy this checkout to $DEST, dropping files that no longer exist upstream.
# .env and pages/ belong to the installation and are kept.
src=$(cd "$(dirname "$0")" && pwd -P)
mkdir -p "$DEST" "$DEST/pages"
if [ "$src" != "$(cd "$DEST" && pwd -P)" ]; then
  find "$DEST" -mindepth 1 -maxdepth 1 ! -name .env ! -name pages -exec rm -rf {} +
  (cd "$src" && tar --exclude=.git --exclude=./.env -cf - .) | tar -C "$DEST" --no-same-owner -xf -
fi
chmod 755 "$DEST" "$DEST/pages"

ENVF=$DEST/.env
[ -f "$ENVF" ] || : > "$ENVF"
chmod 600 "$ENVF"

get_var() { sed -n "s/^$1=//p" "$ENVF" | tail -n 1 | sed "s/^'//; s/'\$//"; }
set_var() {
  case $2 in *"'"*) die "$1 must not contain a single quote" ;; esac
  { grep -v "^$1=" "$ENVF" || true; printf "%s='%s'\n" "$1" "$2"; } > "$ENVF.new"
  mv "$ENVF.new" "$ENVF"
}

# Value for a setting: flag, else existing .env, else prompt (when interactive), else default.
resolve() { # name flag default prompt
  if [ -n "$2" ]; then val=$2
  else
    val=$(get_var "$1")
    if [ -z "$val" ]; then
      if [ -t 0 ]; then
        printf '%s%s: ' "$4" "${3:+ [$3]}" >&2
        read -r val
      fi
      val=${val:-$3}
    fi
  fi
  [ -n "$val" ] || die "$1 is required (use the matching flag)"
  set_var "$1" "$val"
}

resolve URL "$url_flag" "" "URL to display"
resolve DRM_DEVICE "$drm_flag" /dev/dri/card0 "Display card"
resolve VT "$vt_flag" 7 "Virtual terminal"

DRM_DEVICE=$(get_var DRM_DEVICE)
VT=$(get_var VT)

# Only a display card may be given to the container. Opening an NVIDIA node makes the
# container hold the GPU, which breaks VFIO handover to VM tenants.
# The card is identified by its device number (major:minor) through /sys/dev/char, not by
# its name: cardN numbers follow driver probe order and can change at reboot.
real=$(readlink -f "$DRM_DEVICE" 2>/dev/null || true)
case $real in
  /dev/dri/card[0-9]*) ;;
  *) die "DRM_DEVICE must be a display card (/dev/dri/cardN or a /dev/dri/by-path/*-card link), got: $DRM_DEVICE" ;;
esac
[ -c "$real" ] || die "$real is not a character device"
devnum=$(stat -c '%t:%T' "$real")
link=/sys/dev/char/$((0x${devnum%%:*})):$((0x${devnum##*:}))/device/driver
[ -e "$link" ] || die "cannot read the kernel driver of $DRM_DEVICE ($link); refusing it"
driver=$(basename "$(readlink -f "$link")")
[ "$driver" != nvidia ] || die "$DRM_DEVICE ($real) uses the nvidia driver; refusing it (pick the display-only card)"
printf '%s is %s, kernel driver: %s\n' "$DRM_DEVICE" "$real" "$driver"

stable=
for l in /dev/dri/by-path/*-card; do
  if [ -e "$l" ] && [ "$(readlink -f "$l")" = "$real" ]; then stable=$l; fi
done
if [ -n "$stable" ]; then
  printf 'Stable path for this card: %s\n' "$stable"
  [ "$DRM_DEVICE" = "$stable" ] ||
    printf 'Card numbers can change at reboot. To pin this card: sudo %s --drm-device %s\n' "$0" "$stable"
fi

case $VT in
  '' | *[!0-9]*) die "VT must be a number, got: $VT" ;;
esac
if [ "$VT" -lt 1 ] || [ "$VT" -gt 63 ]; then die "VT must be between 1 and 63"; fi
[ -c "/dev/tty$VT" ] || die "/dev/tty$VT does not exist"

cd "$DEST"
docker compose config --quiet
docker compose build --pull=false
docker compose up -d --remove-orphans
docker compose ps
