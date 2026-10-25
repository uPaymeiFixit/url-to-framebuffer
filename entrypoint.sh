#!/bin/sh
# Start Weston, wait for its Wayland socket, start Chromium. If either exits, stop the
# other and exit non-zero so Docker's restart policy restarts the container.
set -eu

URL=${URL:?URL is not set}
DRM_DEVICE=${DRM_DEVICE:-/dev/dri/card0}
VT=${VT:-7}
card=${DRM_DEVICE##*/}

log() { printf 'entrypoint: %s\n' "$*"; }

# libseat's built-in backend: Weston opens the VT and DRM device itself (no logind or seatd).
export LIBSEAT_BACKEND=builtin
export XDG_RUNTIME_DIR=/run/xdg
export WAYLAND_DISPLAY=wayland-0

# Weston 14 has no --tty option: the built-in seat binds to whichever VT is active.
chvt "$VT" || { log "cannot switch to VT $VT (needs /dev/tty0, /dev/tty$VT and CAP_SYS_TTY_CONFIG)"; exit 1; }

# Each program runs under supervise(), a background subshell. When its program exits,
# supervise() signals this script (USR1), whose trap stops the other one and exits non-zero.
# A TERM from Docker takes the same path and exits 0.
wsup='' csup=''
stop() {
  trap '' USR1 TERM INT
  for p in $wsup $csup; do kill "$p" 2>/dev/null || true; done
  wait
}
trap 'stop; exit 1' USR1
trap 'stop; exit 0' TERM INT
supervise() {
  name=$1; shift
  "$@" &
  child=$!
  trap 'kill "$child" 2>/dev/null' TERM
  wait "$child" || true # returns early when TERM was trapped
  wait "$child" || true # blocks until the child is really gone
  log "$name exited"
  kill -USR1 $$
}

# Weston runs as root and creates the socket with the current umask; Chromium runs as
# another user and needs write access to it. XDG_RUNTIME_DIR itself is owned by that user
# with mode 0700, so no one else can reach the socket.
umask 000
supervise weston weston --config=/etc/weston.ini --drm-device="$card" &
wsup=$!

n=0
while [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; do
  n=$((n + 1))
  if [ "$n" -gt 30 ]; then
    log "Weston did not create $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY within 30 s; see its log above"
    stop; exit 1
  fi
  sleep 1
done
umask 022

# --no-sandbox: Chromium's sandbox needs user namespaces, which Docker's default seccomp
# profile blocks. Allowing them takes a custom seccomp profile or seccomp=unconfined, both
# broader than this container otherwise needs. The container is the isolation boundary:
# no extra devices, no GPU, no privileged mode, non-root user, capped resources.
# --disable-gpu*: software rendering only; the GPU process never opens a render node.
# CHROMIUM_EXTRA_ARGS is deliberately word-split.
# shellcheck disable=SC2086
supervise chromium setpriv --reuid=kiosk --regid=kiosk --init-groups \
  env HOME=/tmp chromium \
    --ozone-platform=wayland --kiosk --noerrdialogs --no-first-run \
    --no-sandbox --disable-gpu --disable-gpu-compositing \
    --disable-features=Translate --password-store=basic \
    --user-data-dir=/tmp/chromium-profile \
    ${CHROMIUM_EXTRA_ARGS:-} "$URL" &
csup=$!

# Block until a trap fires (a child exited or Docker sent SIGTERM).
while :; do wait || true; done
