![Architecture](docs/img/architecture.png)
# Homelab: self-hosted media and photo server

A small, always-on home server that runs my personal media library and photo backup. It replaced an aging laptop, and it is built to be reproducible, remotely reachable and easy to recover.

> **Status:** running 24/7 on a ~$200 mini PC. Everything is Dockerised, monitored by a single health-check script, and reachable from anywhere over a private mesh VPN (never exposed to the public internet).

## Why I built it

My first server was a 2012 laptop. It was fine until it had to play 4K HEVC HDR video: its CPU can't hardware-decode 10-bit HEVC, so playback stuttered and every audio/subtitle change blacked the screen out while the transcode restarted. I diagnosed the bottleneck (decoder support, not raw CPU speed), picked hardware that fixes it, and migrated everything with no data loss.

## Architecture

```
 Phone / TV / laptop
        |
   (LAN)|                          (away from home)
        v                                   |
  AdGuard Home  --DNS rewrite-->  *.diyvideo.app -> 10.0.0.105
        |                                   |
        v                                   v
  Nginx Proxy Manager  <-----------  Tailscale (WireGuard mesh)
   (reverse proxy, TLS)
        |
        +--> Jellyfin   :8096   media streaming, Intel QuickSync decode
        +--> Immich     :2283   photo backup and search
        +--> Homepage   :3000   dashboard
        +--> Portainer  :9443   container admin
        |
   4 TB HDD (USB, ext4)  /srv/data   media + photos
   256 GB SSD            /opt        configs and app data
```

## Hardware

| Part | Detail |
|---|---|
| Machine | Dell OptiPlex 3060 Micro |
| CPU / GPU | Intel i5-8400T, UHD 630 (hardware decode for H.264, HEVC, 10-bit HEVC, VP9) |
| RAM / SSD | 8 GB DDR4-2666 / 256 GB SATA |
| Bulk storage | 4 TB drive in a USB enclosure |
| Cost | about $200 including a monitor |

## Software

| Service | Purpose |
|---|---|
| Ubuntu Server 26.04 LTS | Host OS, installed unattended (autoinstall / cloud-init) |
| Docker + Compose | All services in containers |
| Jellyfin | Media server, QuickSync hardware transcoding and HDR tone mapping |
| Immich | Self-hosted photo/video backup with search |
| Nginx Proxy Manager | Reverse proxy, TLS certificates |
| AdGuard Home | Network-wide DNS filtering and local DNS rewrites |
| Tailscale | Private remote access, no open ports |
| Homepage, Portainer | Dashboard and container management |

## Things worth reading

**1. Hardware transcoding.** Confirmed the iGPU exposes `VAProfileHEVCMain10 : VAEntrypointVLD` with `vainfo` inside the container, enabled QSV in Jellyfin, and verified with `intel_gpu_top` that the Video engine did the work while CPU stayed low.

**2. Unattended install on a machine with no keyboard.** The only keyboard I had was Bluetooth, which doesn't work in BIOS or an installer. I switched the disk to AHCI and set the boot order from Windows using Dell Command | Configure, then installed Ubuntu with a cloud-init `autoinstall` USB. Pitfall: the autoinstall flags belong on the GRUB `linux` line, and the `user-data` / `meta-data` files must have no hidden `.txt` extension.

**3. Zero-surprise migration.** Stopped the old server's containers, dumped the Immich database, archived all configs and app data to a tar on the data drive, moved the drive, restored by UUID, and brought services up in dependency order (DNS first). Then re-addressed the new host to the old IP so DNS rewrites and bookmarks kept working.

**4. A flaky USB enclosure.** The drive's bridge chip dropped under autosuspend. Fixed with kernel parameters (`usbcore.autosuspend=-1`, `usb-storage.quirks=...:u`) and a `nofail,x-systemd.device-timeout` fstab entry so a missing drive can't block boot.

**5. One-command health check.** `scripts/healthcheck.sh` reports container health, HTTP endpoints, DNS resolution, drive mount and free space, GPU device, Tailscale, RAM, temperature and kernel USB errors, and exits non-zero on failure.

## Repo layout

```
.
├── compose/
│   ├── docker-compose.yml            # Jellyfin
│   ├── docker-compose.tools.yml      # NPM, Portainer, Homepage
│   ├── .env.example                  # merges the two files above
│   ├── adguard/docker-compose.yml
│   └── immich/
│       ├── docker-compose.yml        # based on Immich's official file
│       └── .env.example
├── scripts/healthcheck.sh
└── docs/
    ├── migration.md
    └── autoinstall-user-data.example # placeholders only
```

## Quick start

```bash
git clone https://github.com/mansoor00727/homelab.git && cd homelab/compose
cp .env.example .env
docker compose up -d                    # Jellyfin + NPM + Portainer + Homepage
(cd adguard && docker compose up -d)    # DNS (free port 53 first, see the file header)
(cd immich && cp .env.example .env && nano .env && docker compose up -d)
sudo ../scripts/healthcheck.sh
```

Paths such as `/opt/appdata` and `/srv/data` and the render group ID are specific to my host. Edit them to match yours.

## Security notes

- Nothing is port-forwarded. Remote access is Tailscale only.
- Secrets live in `.env` files that are git-ignored. This repo contains `.env.example` with placeholders.
- No password hashes, API keys or tokens are committed.

## What I'd do next

- Offsite backup of photos and app data (3-2-1), tested restores.
- Monitoring and alerting (Uptime Kuma or similar).
- Family accounts on Immich.

## What I learned

- Check codec and decoder support before blaming CPU speed.
- A migration plan is mostly ordering: DNS first, data second, verify before deleting anything.
- Write the recovery path down before you need it.
