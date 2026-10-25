# url-to-framebuffer

Show one web page full-screen on a Linux machine's local monitor, with no X11 and no
desktop, from a Docker container. It runs [Weston](https://wayland.freedesktop.org/) (the
Wayland reference compositor) on the kernel's DRM/KMS display device with its software
(pixman) renderer, and Chromium in kiosk mode on top of it. There is no compiled code in
this repository: a Dockerfile, a Compose file, one Weston config file and a few short
POSIX shell scripts.

Use it for a status dashboard on a server's console monitor, or a signage page, on a
machine that has no desktop environment and may have GPUs that must stay untouched.

## Why only the display card

The container is given exactly one display device (`DRM_DEVICE`) plus `/dev/tty0` and one
virtual terminal. It never sees `/dev/dri` as a whole, other GPUs, render nodes or
`/dev/input`, and Chromium runs with `--disable-gpu`. This matters on machines with
compute GPUs: opening an NVIDIA device node holds the GPU and breaks VFIO handover to VM
tenants, so `install.sh` refuses any card driven by `nvidia`.

## Requirements

- Linux with a KMS display device (`/dev/dri/cardN`) that is not an NVIDIA GPU. First
  deployment target: Ubuntu 22.04 with an ASPEED BMC VGA (`ast` driver, `/dev/dri/card0`,
  1920x1080).
- Docker 24+ with Compose v2 (`docker compose`).
- Root, to install and to give the container the devices.
- Nothing else may hold the display card: no X server, no other Wayland compositor.
- Network access at build time (Debian snapshot archive and the Docker Hub base image).

## Install

```sh
git clone <this repository> && cd url-to-framebuffer
sudo ./install.sh --url https://example.com
```

`install.sh` prints which kernel driver the chosen card uses, copies the checkout to
`/opt/url-to-framebuffer`, writes `/opt/url-to-framebuffer/.env` (root-only), builds the
image with `docker compose build` and starts it with `docker compose up -d`. Without flags
it prompts for the URL, card and VT. Flags: `--url`, `--drm-device /dev/dri/cardN`,
`--vt N`.

To show local files, put them in `/opt/url-to-framebuffer/pages` and use
`--url file:///pages/index.html`.

## Update

Pull the new checkout and run `sudo ./install.sh` again. Existing `.env` values are kept
unless you pass a flag; files removed upstream are removed from `/opt/url-to-framebuffer`
(`.env` and `pages/` are kept). To change a setting by hand, edit
`/opt/url-to-framebuffer/.env`, then run `docker compose up -d` in that directory.
To restart without changes use `docker compose restart`; never `docker kill` a container
(Docker then skips it at boot).

## Configuration

Set in `/opt/url-to-framebuffer/.env`; see `.env.example`.

| Variable | Default | Meaning |
|---|---|---|
| `URL` | required | Page to show |
| `DRM_DEVICE` | `/dev/dri/card0` | Display card; `install.sh` refuses `nvidia` and unreadable drivers |
| `VT` | `7` | Virtual terminal to draw on; pick one with no login prompt |
| `PAGES_DIR` | `/opt/url-to-framebuffer/pages` | Host directory mounted read-only at `/pages` |
| `CPUS` | `2` | CPU cap |
| `MEMORY_LIMIT` | `1g` | Memory cap (includes the tmpfs Chromium profile) |
| `PIDS_LIMIT` | `1024` | Process and thread cap |
| `TMP_SIZE` | `256m` | Size of the tmpfs holding the Chromium profile |
| `CHROMIUM_EXTRA_ARGS` | empty | Extra Chromium flags, space-separated |

Video mode: Weston uses the monitor's preferred mode. To force one, edit `weston.ini`
(see the comment at its end) and re-run `install.sh`.

## Returning to the text console

Stop the service: `cd /opt/url-to-framebuffer && sudo docker compose stop`. Weston puts
the VT back in text mode on exit. The screen then stays on the (blank) VT the service used,
so press Ctrl+Alt+F1 or run `sudo chvt 1`. `stop` also keeps it stopped across reboots;
`docker compose up -d` starts it again.

Ctrl+Alt+F1 does not work while it runs. No input devices are passed into the container, and
Weston's seat code switches the kernel keyboard handling off on its VT, so nothing is left to
interpret the key combination. (Read from the Weston and libseat sources; not tested on
hardware.) Use SSH.

If the host itself hangs, the screen freezes on its last frame: nothing redraws it.

## Chromium sandbox

Chromium runs with `--no-sandbox`. Its sandbox needs user namespaces, which Docker's default
seccomp profile blocks; enabling them takes a custom seccomp profile or
`seccomp=unconfined`, both broader than this container otherwise needs. The container is
therefore the isolation boundary: it has only the display card and VT devices, no GPU, no
privileged mode, runs Chromium as a non-root user with capped resources. Point it only at
pages you trust.

## Troubleshooting

Logs: `cd /opt/url-to-framebuffer && sudo docker compose logs -f`.

| Symptom, log line to look for | Cause and fix |
|---|---|
| `libseat: could not open seat`, `Could not open terminal for VT`, `cannot switch to VT` | The container cannot use the VT. Check `/dev/tty<VT>` exists and that the VT is not a login console held by something else; try another `VT`. |
| `Could not make device fd drm master: Device or resource busy` (or `ERROR: could not open DRM device`) | Something else holds the display card: an X server, another compositor, or a leftover container. Stop it (`fuser -v /dev/dri/card0` on the host shows holders). |
| `Could not make device fd drm master: Permission denied` | Unprivileged DRM master was refused. As a last resort add `SYS_ADMIN` to `cap_add` in `compose.yaml`; this widens the container, so prefer finding the other holder first. |
| `no drm device found`, `Failed to create heads` | Wrong `DRM_DEVICE`, or no monitor detected on the card. List cards with `ls /sys/class/drm`. |
| `failed to create kms fb`, `is not compatible with dumb buffers` | The driver rejects the default pixel format for software rendering. Uncomment `gbm-format=rgb565` in `weston.ini` (or try another format your driver supports) and re-run `install.sh`. |
| Chromium: `No usable sandbox`, `Failed to move to new namespace` | Only if you removed `--no-sandbox` in `entrypoint.sh`; see the section above. |
| Container restarts every few seconds | One of the two programs exits; the line `entrypoint: weston exited` or `entrypoint: chromium exited` shows which, and the lines above it say why. |
