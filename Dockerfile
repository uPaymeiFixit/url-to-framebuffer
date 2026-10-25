# Weston (DRM backend, software renderer) plus Chromium, in one image.
# Base image pinned by digest (multi-arch index of debian:trixie, fetched 2026-10-25).
FROM debian:trixie@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308

# Packages come from a fixed snapshot of the Debian archive, so a rebuild months later
# installs the same versions. Snapshot Release files are long expired, hence
# check-valid-until=no. http: because the base image has no CA certificates yet; apt
# verifies the signed Release files itself.
ARG SNAPSHOT=20261001T000000Z

# No version pins on the packages (hadolint DL3008): the snapshot date is the pin.
# What and why:
#   weston            compositor; its DRM backend with the pixman renderer needs no GPU stack
#   chromium          the browser
#   kbd               chvt, to make the configured VT the active one before Weston starts
#   fonts-dejavu-core minimal font set so text renders
#   ca-certificates   https pages
# libgl1-mesa-dri is deliberately absent: Weston uses pixman and Chromium runs with
# --disable-gpu, so nothing in the image needs Mesa's drivers or opens a render node.
# hadolint ignore=DL3008
RUN rm -f /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list \
 && printf '%s\n' \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${SNAPSHOT}/ trixie main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${SNAPSHOT}/ trixie-updates main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${SNAPSHOT}/ trixie-security main" \
      > /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      weston chromium kbd fonts-dejavu-core ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 1000 --user-group --no-create-home --shell /usr/sbin/nologin kiosk

COPY weston.ini /etc/weston.ini
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
