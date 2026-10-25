# url-to-framebuffer

Config-only: Docker Compose runs Weston (DRM backend, pixman) plus Chromium kiosk to show
`URL` on a machine's local display. No compiled code; shell stays short and POSIX.
`README.md` has install, configuration and troubleshooting.

## Rules

- The container may open only `${DRM_DEVICE}`, `/dev/tty0` and `/dev/tty${VT}`. Never add a
  `/dev` or `/dev/dri` bind mount, `privileged`, a GPU runtime or `--gpus`. `lint.sh` greps for
  these. `install.sh` must keep refusing the `nvidia` driver and unreadable drivers.
- Never `docker kill` (Docker then skips the container at boot); use `docker compose restart`.
- Generic repo: no host names, addresses, fleet or page specifics.
- Base image is pinned by digest and apt by snapshot date (`Dockerfile`); change both
  deliberately and say so in the commit message.
- Weston 14 has no `--tty`; `entrypoint.sh` runs `chvt` instead. `--no-sandbox` is a
  deliberate decision (see README).
- `./lint.sh` before committing (CI runs the same). Needs shellcheck and hadolint (or Docker).
  Locally: `nix shell 'nixpkgs#shellcheck' 'nixpkgs#hadolint' -c ./lint.sh`.
- The display path cannot be tested without a KMS display device; say so rather than claim it works.
